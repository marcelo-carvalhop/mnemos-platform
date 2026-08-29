#include "sync_codec.h"

#include <ArduinoJson.h>
#include <new>
#include "config.h"
#include "storage.h"

namespace {

bool supportedType(const String& type) {
    return type == "open_recall" || type == "cloze" ||
           type == "multiple_choice" || type == "true_false" ||
           type == "application";
}

String deckNameFor(JsonDocument& doc, const String& deckId) {
    for (JsonObjectConst deck : doc["decks"].as<JsonArrayConst>()) {
        if (String(deck["id"] | "") == deckId) return String(deck["name"] | "");
    }
    return String();
}

bool parseCard(JsonObjectConst item, JsonDocument& snapshot, CardDefinition& out, String& error) {
    if (String(item["schema"] | "") != "mnemos.card/v2") {
        error = "invalid_card_schema";
        return false;
    }

    out = CardDefinition{};
    out.id = item["id"] | "";
    out.deckId = item["deckId"] | "";
    out.deck = deckNameFor(snapshot, out.deckId);
    out.type = item["type"] | "";
    out.format = item["content"]["prompt"]["format"] | "plain";
    out.question = item["content"]["prompt"]["text"] | "";
    out.answer = item["content"]["answer"]["text"] | "";
    out.revision = item["metadata"]["revision"] | 1ULL;

    if (out.id.length() == 0 || out.id.length() > 64 || out.deckId.length() == 0 ||
        out.deck.length() == 0 || out.question.length() == 0 || !supportedType(out.type) ||
        out.format != "plain") {
        error = "invalid_or_unsupported_card";
        return false;
    }

    if (out.type == "multiple_choice") {
        JsonArrayConst options = item["options"].as<JsonArrayConst>();
        if (options.size() < 2 || options.size() > Config::MAX_CARD_OPTIONS) {
            error = "invalid_option_count";
            return false;
        }
        for (JsonVariantConst option : options) out.options[out.optionCount++] = option.as<String>();
        out.correctOptionIndex = item["evaluation"]["correctOptionIndex"] | -1;
        if (out.correctOptionIndex < 0 || out.correctOptionIndex >= out.optionCount) {
            error = "invalid_correct_option";
            return false;
        }
        if (out.answer.length() == 0) out.answer = out.options[out.correctOptionIndex];
    } else if (out.type == "true_false") {
        out.options[0] = "Verdadeiro";
        out.options[1] = "Falso";
        out.optionCount = 2;
        if (item["evaluation"]["correctOptionIndex"].is<int>()) {
            out.correctOptionIndex = item["evaluation"]["correctOptionIndex"].as<int>();
        } else {
            const bool correct = item["evaluation"]["correctValue"] | false;
            out.correctOptionIndex = correct ? 0 : 1;
        }
        if (out.correctOptionIndex < 0 || out.correctOptionIndex > 1) {
            error = "invalid_true_false_answer";
            return false;
        }
        if (out.answer.length() == 0) out.answer = out.options[out.correctOptionIndex];
    } else if (out.answer.length() == 0) {
        error = "missing_reference_answer";
        return false;
    }

    return true;
}

}

namespace SyncCodec {

bool applySnapshotV2(const String& body,
                     CardDefinition* cards,
                     CardState* states,
                     size_t maxCards,
                     size_t& cardCount,
                     Storage& storage,
                     String& error) {
    error = "";
    if (body.length() == 0 || body.length() > 120000U) {
        error = "payload_too_large";
        return false;
    }

    JsonDocument doc;
    if (deserializeJson(doc, body)) {
        error = "invalid_json";
        return false;
    }
    if (String(doc["schema"] | "") != "mnemos.sync/v2") {
        error = "unsupported_sync_schema";
        return false;
    }

    JsonArrayConst items = doc["cards"].as<JsonArrayConst>();
    if (items.size() > maxCards) {
        error = "terminal_capacity_exceeded";
        return false;
    }

    CardDefinition* nextCards = new (std::nothrow) CardDefinition[maxCards];
    CardState* nextStates = new (std::nothrow) CardState[maxCards];
    if (nextCards == nullptr || nextStates == nullptr) {
        delete[] nextCards;
        delete[] nextStates;
        error = "out_of_memory";
        return false;
    }

    const size_t oldCount = cardCount;
    size_t next = 0;
    for (JsonObjectConst item : items) {
        if (!parseCard(item, doc, nextCards[next], error)) {
            delete[] nextCards;
            delete[] nextStates;
            return false;
        }

        CardState preserved{};
        preserved.id = nextCards[next].id;
        for (size_t old = 0; old < oldCount; ++old) {
            if (states[old].id == preserved.id) {
                preserved = states[old];
                break;
            }
        }
        nextStates[next] = preserved;
        ++next;
    }

    if (!storage.saveStates(nextStates, next) || !storage.saveLibrary(nextCards, nextStates, next)) {
        delete[] nextCards;
        delete[] nextStates;
        error = "storage_failed";
        return false;
    }

    for (size_t i = 0; i < next; ++i) {
        cards[i] = nextCards[i];
        states[i] = nextStates[i];
    }
    cardCount = next;
    delete[] nextCards;
    delete[] nextStates;
    return true;
}

bool applyReviewDeltaV2(
    const String& body,
    Storage& storage,
    ReviewDeltaApplyResult& result,
    String& error) {

    result =
        ReviewDeltaApplyResult{};

    error = "";

    if (
        body.length() == 0 ||
        body.length() > 120000U
    ) {
        error =
            "review_delta_payload_too_large";
        return false;
    }

    JsonDocument doc;

    if (deserializeJson(doc, body)) {
        error =
            "invalid_review_delta_json";
        return false;
    }

    if (
        String(doc["schema"] | "") !=
        "mnemos.review-delta/v2"
    ) {
        error =
            "unsupported_review_delta_schema";
        return false;
    }

    if (!doc["cursor"].is<uint64_t>()) {
        error =
            "invalid_review_cursor";
        return false;
    }

    result.cursor =
        doc["cursor"].as<uint64_t>();

    result.hasMore =
        doc["hasMore"] | false;

    JsonArrayConst reviews =
        doc["reviews"].as<JsonArrayConst>();

    for (
        JsonObjectConst review :
        reviews
    ) {
        if (
            String(review["schema"] | "") !=
            "mnemos.review/v2"
        ) {
            error =
                "invalid_remote_review_schema";
            return false;
        }

        const String id =
            review["id"] | "";

        const String cardId =
            review["cardId"] | "";

        const uint8_t rating =
            review["schedulerRating"] | 0U;

        if (
            id.length() == 0 ||
            cardId.length() == 0 ||
            rating < 1 ||
            rating > 4 ||
            !review["reviewedAtMs"]
                .is<uint64_t>()
        ) {
            error =
                "invalid_remote_review";
            return false;
        }

        String line;
        serializeJson(review, line);

        bool inserted = false;

        if (
            !storage.appendRemoteReviewJson(
                line,
                inserted)
        ) {
            error =
                "remote_review_storage_failed";
            return false;
        }

        if (inserted) {
            ++result.appended;
        }
    }

    // Cursor só avança depois que todos os eventos da página
    // estão duravelmente gravados.
    if (
        !storage.saveReviewCursor(
            result.cursor)
    ) {
        error =
            "review_cursor_storage_failed";
        return false;
    }

    return true;
}


bool applyProgressResetDeltaV2(
    const String& body,
    Storage& storage,
    ProgressResetDeltaApplyResult& result,
    String& error) {

    result =
        ProgressResetDeltaApplyResult{};

    error = "";

    JsonDocument doc;

    if (deserializeJson(doc, body)) {
        error =
            "invalid_progress_reset_delta_json";
        return false;
    }

    if (
        String(doc["schema"] | "") !=
        "mnemos.progress-reset-delta/v2"
    ) {
        error =
            "unsupported_progress_reset_delta_schema";
        return false;
    }

    if (!doc["cursor"].is<uint64_t>()) {
        error =
            "invalid_progress_reset_cursor";
        return false;
    }

    result.cursor =
        doc["cursor"].as<uint64_t>();

    result.hasMore =
        doc["hasMore"] | false;

    JsonArrayConst resets =
        doc["resets"].as<JsonArrayConst>();

    for (
        JsonObjectConst reset :
        resets
    ) {
        if (
            String(reset["schema"] | "") !=
            "mnemos.progress-reset/v2"
        ) {
            error =
                "invalid_progress_reset_schema";
            return false;
        }

        const String id =
            reset["id"] | "";

        const String cardId =
            reset["cardId"] | "";

        if (
            id.length() == 0 ||
            cardId.length() == 0 ||
            !reset["resetAtMs"]
                .is<uint64_t>()
        ) {
            error =
                "invalid_progress_reset";
            return false;
        }

        String line;

        serializeJson(
            reset,
            line);

        bool inserted = false;

        if (
            !storage
                .appendRemoteProgressResetJson(
                    line,
                    inserted)
        ) {
            error =
                "progress_reset_storage_failed";
            return false;
        }

        if (inserted) {
            ++result.appended;
        }
    }

    // O cursor só avança depois de todos os eventos
    // da página estarem persistidos.
    if (
        !storage.saveProgressResetCursor(
            result.cursor)
    ) {
        error =
            "progress_reset_cursor_storage_failed";
        return false;
    }

    return true;
}


bool applyUserSettingDeltaV2(
    const String& body,
    Storage& storage,
    UserSettingDeltaApplyResult& result,
    String& error) {

    result =
        UserSettingDeltaApplyResult{};

    error = "";

    JsonDocument doc;

    if (deserializeJson(doc, body)) {
        error =
            "invalid_user_setting_delta_json";
        return false;
    }

    if (
        String(doc["schema"] | "") !=
        "mnemos.user-setting-delta/v2"
    ) {
        error =
            "unsupported_user_setting_delta_schema";
        return false;
    }

    if (!doc["cursor"].is<uint64_t>()) {
        error =
            "invalid_user_setting_cursor";
        return false;
    }

    result.cursor =
        doc["cursor"].as<uint64_t>();

    result.hasMore =
        doc["hasMore"] | false;

    JsonArrayConst settings =
        doc["settings"]
            .as<JsonArrayConst>();

    for (
        JsonObjectConst setting :
        settings
    ) {
        if (
            String(setting["schema"] | "") !=
            "mnemos.user-setting/v2"
        ) {
            error =
                "invalid_user_setting_schema";
            return false;
        }

        const String key =
            setting["key"] | "";

        if (
            key !=
            "desired_retention"
        ) {
            // Backend já filtra, mas o firmware também
            // aplica sua própria whitelist.
            continue;
        }

        const String value =
            setting["value"] | "";

        if (value.length() == 0) {
            error =
                "missing_desired_retention";
            return false;
        }

        const double retention =
            value.toDouble();

        if (
            retention <= 0.0 ||
            retention >= 1.0
        ) {
            error =
                "invalid_desired_retention";
            return false;
        }

        if (
            !storage.saveDesiredRetention(
                retention)
        ) {
            error =
                "desired_retention_storage_failed";
            return false;
        }

        // Mesmo que seja um retry do mesmo valor,
        // repetir o replay é seguro e evita um caso de
        // queda de energia entre setting e cursor.
        ++result.applied;
    }

    if (
        !storage.saveSettingsCursor(
            result.cursor)
    ) {
        error =
            "user_setting_cursor_storage_failed";
        return false;
    }

    return true;
}


String buildReviewBatchV2(const Storage& storage) {
    JsonDocument batch;
    batch["schema"] = "mnemos.review-batch/v2";
    JsonArray reviews = batch["reviews"].to<JsonArray>();
    const String ndjson = storage.reviewOutboxNdjson();

    int start = 0;
    while (start < static_cast<int>(ndjson.length())) {
        int end = ndjson.indexOf('\n', start);
        if (end < 0) end = static_cast<int>(ndjson.length());
        const String line = ndjson.substring(start, end);
        start = end + 1;
        if (line.length() == 0) continue;
        JsonDocument row;
        if (!deserializeJson(row, line)) reviews.add(row.as<JsonObject>());
    }

    String body;
    serializeJson(batch, body);
    return body;
}

}  // namespace SyncCodec
