#include "sync_codec.h"

#include <ArduinoJson.h>
#include <new>
#include <vector>

#include "config.h"
#include "platform_sync_config.h"
#include "storage.h"
#include "text_sanitizer.h"

namespace {

constexpr size_t MAX_REMOTE_ID_LENGTH = 36U;  // String(36) no backend
constexpr size_t MAX_LOCAL_ID_LENGTH = 64U;

bool supportedType(const String& type) {
    // Servidor <-> terminal: somente open_recall (revelar + autoavaliar).
    return type == "open_recall";
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
    out.type = item["type"] | "";
    out.revision = item["metadata"]["revision"] | 1ULL;

    if (out.id.length() == 0 || out.id.length() > MAX_LOCAL_ID_LENGTH) {
        error = "invalid_card_id";
        return false;
    }
    if (out.deckId.length() == 0) {
        error = "missing_deck";
        return false;
    }
    if (!supportedType(out.type)) {
        error = "unsupported_card_type";
        return false;
    }

    // O terminal desenha texto puro. Qualquer formato chega como texto.
    out.format = "plain";
    out.question = TextSanitizer::forDisplay(String(item["content"]["prompt"]["text"] | ""));
    out.answer = TextSanitizer::forDisplay(String(item["content"]["answer"]["text"] | ""));

    String deck = TextSanitizer::forDisplay(deckNameFor(snapshot, out.deckId));
    if (deck.length() == 0) deck = "Baralho";
    out.deck = deck;

    if (out.question.length() == 0) {
        error = "empty_prompt";
        return false;
    }

    if (out.type == "multiple_choice") {
        JsonArrayConst options = item["options"].as<JsonArrayConst>();
        if (options.size() < 2 || options.size() > Config::MAX_CARD_OPTIONS) {
            error = "invalid_option_count";
            return false;
        }
        for (JsonVariantConst option : options) {
            out.options[out.optionCount++] = TextSanitizer::forDisplay(option.as<String>());
        }
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
        // Verso vazio no app ainda é um cartão válido para recordar.
        out.answer = "(sem resposta cadastrada)";
    }

    return true;
}

bool sameCatalog(const CardDefinition* current,
                 size_t currentCount,
                 const CardDefinition* next,
                 size_t nextCount) {
    if (currentCount != nextCount) return false;
    for (size_t i = 0; i < nextCount; ++i) {
        const CardDefinition& candidate = next[i];
        const CardDefinition* match = nullptr;
        if (i < currentCount && current[i].id == candidate.id) {
            match = &current[i];
        } else {
            for (size_t j = 0; j < currentCount; ++j) {
                if (current[j].id == candidate.id) {
                    match = &current[j];
                    break;
                }
            }
        }
        if (match == nullptr) return false;
        if (match->revision != candidate.revision || match->deckId != candidate.deckId ||
            match->deck != candidate.deck || match->type != candidate.type) {
            return false;
        }
    }
    return true;
}

}  // namespace

namespace SyncCodec {

void buildSnapshotFilter(JsonDocument& filter) {
    filter.clear();
    filter["schema"] = true;
    JsonObject deck = filter["decks"].add<JsonObject>();
    deck["id"] = true;
    deck["name"] = true;
    JsonObject card = filter["cards"].add<JsonObject>();
    card["schema"] = true;
    card["id"] = true;
    card["deckId"] = true;
    card["type"] = true;
    card["content"]["prompt"]["text"] = true;
    card["content"]["prompt"]["format"] = true;
    card["content"]["answer"]["text"] = true;
    card["options"] = true;
    card["evaluation"] = true;
    card["metadata"]["revision"] = true;
}

bool applySnapshotDocument(JsonDocument& doc,
                           CardDefinition* cards,
                           CardState* states,
                           size_t maxCards,
                           size_t& cardCount,
                           Storage& storage,
                           bool fromBackend,
                           SnapshotApplyResult& result,
                           String& error) {
    result = SnapshotApplyResult{};
    error = "";

    if (String(doc["schema"] | "") != "mnemos.sync/v2") {
        error = "unsupported_sync_schema";
        return false;
    }

    JsonArrayConst items = doc["cards"].as<JsonArrayConst>();
    result.received = static_cast<uint16_t>(items.size());

    if (fromBackend && items.size() == 0 && cardCount > 0 && !storage.libraryFromBackend()) {
        // Conexão não é seleção de conteúdo: a conta ainda não escolheu
        // baralhos para este terminal. Mantém o que já estava no aparelho.
        result.cards = cardCount;
        result.keptLocalLibrary = true;
        return true;
    }

    CardDefinition* nextCards = new (std::nothrow) CardDefinition[maxCards];
    if (nextCards == nullptr) {
        error = "out_of_memory";
        return false;
    }

    size_t next = 0;
    for (JsonObjectConst item : items) {
        if (next >= maxCards) {
            delete[] nextCards;
            error = "terminal_capacity_exceeded";
            return false;
        }

        String reason;
        if (!parseCard(item, doc, nextCards[next], reason)) {
            ++result.skipped;
            if (result.firstSkipReason.length() == 0) result.firstSkipReason = reason;
            continue;
        }

        bool duplicate = false;
        for (size_t k = 0; k < next; ++k) {
            if (nextCards[k].id == nextCards[next].id) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) {
            ++result.duplicates;
            continue;
        }
        ++next;
    }

    const bool sourceChanged = storage.libraryFromBackend() != fromBackend;
    if (!sourceChanged && sameCatalog(cards, cardCount, nextCards, next)) {
        delete[] nextCards;
        result.cards = cardCount;
        result.changed = false;
        return true;
    }

    CardState* nextStates = new (std::nothrow) CardState[maxCards];
    if (nextStates == nullptr) {
        delete[] nextCards;
        error = "out_of_memory";
        return false;
    }

    const size_t oldCount = cardCount;
    for (size_t i = 0; i < next; ++i) {
        CardState preserved{};
        preserved.id = nextCards[i].id;
        for (size_t old = 0; old < oldCount; ++old) {
            if (states[old].id == preserved.id) {
                preserved = states[old];
                break;
            }
        }
        nextStates[i] = preserved;
    }

    if (!storage.saveStates(nextStates, next) || !storage.saveLibrary(nextCards, nextStates, next)) {
        delete[] nextCards;
        delete[] nextStates;
        error = "storage_failed";
        return false;
    }
    storage.setLibraryFromBackend(fromBackend);

    for (size_t i = 0; i < next; ++i) {
        cards[i] = nextCards[i];
        states[i] = nextStates[i];
    }
    for (size_t i = next; i < oldCount && i < maxCards; ++i) {
        cards[i] = CardDefinition{};
        states[i] = CardState{};
    }
    cardCount = next;
    delete[] nextCards;
    delete[] nextStates;

    result.cards = next;
    result.changed = true;
    return true;
}

bool applySnapshotV2(const String& body,
                     CardDefinition* cards,
                     CardState* states,
                     size_t maxCards,
                     size_t& cardCount,
                     Storage& storage,
                     String& error) {
    error = "";
    if (body.length() == 0 || body.length() > PlatformSync::SNAPSHOT_MAX_BYTES) {
        error = "payload_too_large";
        return false;
    }

    JsonDocument filter;
    buildSnapshotFilter(filter);
    JsonDocument doc;
    if (deserializeJson(doc, body, DeserializationOption::Filter(filter))) {
        error = "invalid_json";
        return false;
    }

    SnapshotApplyResult result;
    return applySnapshotDocument(doc, cards, states, maxCards, cardCount, storage, false, result, error);
}

bool applyReviewDeltaV2(
    const String& body,
    Storage& storage,
    ReviewDeltaApplyResult& result,
    String& error) {

    result = ReviewDeltaApplyResult{};
    error = "";

    if (body.length() == 0 || body.length() > PlatformSync::SNAPSHOT_MAX_BYTES) {
        error = "review_delta_payload_too_large";
        return false;
    }

    JsonDocument doc;
    if (deserializeJson(doc, body)) {
        error = "invalid_review_delta_json";
        return false;
    }

    if (String(doc["schema"] | "") != "mnemos.review-delta/v2") {
        error = "unsupported_review_delta_schema";
        return false;
    }

    if (!doc["cursor"].is<uint64_t>()) {
        error = "invalid_review_cursor";
        return false;
    }

    result.cursor = doc["cursor"].as<uint64_t>();
    result.hasMore = doc["hasMore"] | false;

    std::vector<String> lines;
    JsonArrayConst reviews = doc["reviews"].as<JsonArrayConst>();
    lines.reserve(reviews.size());

    for (JsonObjectConst review : reviews) {
        if (String(review["schema"] | "") != "mnemos.review/v2") {
            error = "invalid_remote_review_schema";
            return false;
        }

        const String id = review["id"] | "";
        const String cardId = review["cardId"] | "";
        const uint8_t rating = review["schedulerRating"] | 0U;

        if (id.length() == 0 || cardId.length() == 0 || rating < 1 || rating > 4 ||
            !review["reviewedAtMs"].is<uint64_t>()) {
            // Um evento malformado não deve travar o cursor para sempre.
            continue;
        }

        String line;
        serializeJson(review, line);
        lines.push_back(line);
    }

    result.received = static_cast<uint16_t>(lines.size());
    uint16_t inserted = 0;
    if (!storage.appendRemoteReviewLines(lines, inserted)) {
        error = "remote_review_storage_failed";
        return false;
    }
    result.appended = inserted;

    // Cursor só avança depois que todos os eventos da página estão gravados.
    if (!storage.saveReviewCursor(result.cursor)) {
        error = "review_cursor_storage_failed";
        return false;
    }

    return true;
}

bool applyProgressResetDeltaV2(
    const String& body,
    Storage& storage,
    ProgressResetDeltaApplyResult& result,
    String& error) {

    result = ProgressResetDeltaApplyResult{};
    error = "";

    JsonDocument doc;
    if (deserializeJson(doc, body)) {
        error = "invalid_progress_reset_delta_json";
        return false;
    }

    if (String(doc["schema"] | "") != "mnemos.progress-reset-delta/v2") {
        error = "unsupported_progress_reset_delta_schema";
        return false;
    }

    if (!doc["cursor"].is<uint64_t>()) {
        error = "invalid_progress_reset_cursor";
        return false;
    }

    result.cursor = doc["cursor"].as<uint64_t>();
    result.hasMore = doc["hasMore"] | false;

    std::vector<String> lines;
    for (JsonObjectConst reset : doc["resets"].as<JsonArrayConst>()) {
        if (String(reset["schema"] | "") != "mnemos.progress-reset/v2") {
            error = "invalid_progress_reset_schema";
            return false;
        }

        const String id = reset["id"] | "";
        const String cardId = reset["cardId"] | "";

        if (id.length() == 0 || cardId.length() == 0 || !reset["resetAtMs"].is<uint64_t>()) {
            continue;
        }

        String line;
        serializeJson(reset, line);
        lines.push_back(line);
    }

    uint16_t inserted = 0;
    if (!storage.appendRemoteProgressResetLines(lines, inserted)) {
        error = "progress_reset_storage_failed";
        return false;
    }
    result.appended = inserted;

    // O cursor só avança depois de todos os eventos da página estarem
    // persistidos.
    if (!storage.saveProgressResetCursor(result.cursor)) {
        error = "progress_reset_cursor_storage_failed";
        return false;
    }

    return true;
}

bool applyUserSettingDeltaV2(
    const String& body,
    Storage& storage,
    UserSettingDeltaApplyResult& result,
    String& error) {

    result = UserSettingDeltaApplyResult{};
    error = "";

    JsonDocument doc;
    if (deserializeJson(doc, body)) {
        error = "invalid_user_setting_delta_json";
        return false;
    }

    if (String(doc["schema"] | "") != "mnemos.user-setting-delta/v2") {
        error = "unsupported_user_setting_delta_schema";
        return false;
    }

    if (!doc["cursor"].is<uint64_t>()) {
        error = "invalid_user_setting_cursor";
        return false;
    }

    result.cursor = doc["cursor"].as<uint64_t>();
    result.hasMore = doc["hasMore"] | false;

    for (JsonObjectConst setting : doc["settings"].as<JsonArrayConst>()) {
        if (String(setting["schema"] | "") != "mnemos.user-setting/v2") {
            error = "invalid_user_setting_schema";
            return false;
        }

        const String key = setting["key"] | "";
        if (key != "desired_retention") {
            // Backend já filtra, mas o firmware também aplica sua whitelist.
            continue;
        }

        const String value = setting["value"] | "";
        const double retention = value.toDouble();
        if (value.length() == 0 || retention <= 0.0 || retention >= 1.0) {
            // Valor inválido de outro cliente: ignora, não trava o cursor.
            continue;
        }

        const double current = storage.desiredRetention();
        if (retention > current - 1e-6 && retention < current + 1e-6) {
            continue;  // igual ao vigente: evita replay completo à toa
        }

        if (!storage.saveDesiredRetention(retention)) {
            error = "desired_retention_storage_failed";
            return false;
        }

        ++result.applied;
    }

    if (!storage.saveSettingsCursor(result.cursor)) {
        error = "user_setting_cursor_storage_failed";
        return false;
    }

    return true;
}

OutboxLineKind convertOutboxLine(const String& line,
                                 JsonObject remote,
                                 String& id,
                                 String& cardId,
                                 String& reason) {
    id = "";
    cardId = "";
    reason = "";

    JsonDocument local;
    if (deserializeJson(local, line)) {
        reason = "invalid_json";
        return OutboxLineKind::Reject;
    }

    id = local["id"] | "";
    cardId = local["cardId"] | "";

    if (!(local["affectsSchedule"] | true)) {
        return OutboxLineKind::DropNotScheduled;
    }

    if (id.length() == 0 || id.length() > MAX_REMOTE_ID_LENGTH) {
        reason = "invalid_review_id";
        return OutboxLineKind::Reject;
    }
    if (cardId.length() == 0 || cardId.length() > MAX_REMOTE_ID_LENGTH) {
        reason = "invalid_card_id";
        return OutboxLineKind::Reject;
    }

    const uint8_t rating = local["schedulerRating"] | 0U;
    if (rating < 1 || rating > 4) {
        reason = "invalid_rating";
        return OutboxLineKind::Reject;
    }

    const uint64_t reviewedAtMs =
        local["reviewedAtMs"].is<uint64_t>()
            ? local["reviewedAtMs"].as<uint64_t>()
            : static_cast<uint64_t>(local["reviewedAt"] | 0ULL) * 1000ULL;

    if (reviewedAtMs < PlatformSync::MIN_VALID_REVIEW_EPOCH_MS) {
        reason = "untrusted_clock";
        return OutboxLineKind::Reject;
    }

    uint64_t dueAfterMs =
        local["dueAfterMs"].is<uint64_t>()
            ? local["dueAfterMs"].as<uint64_t>()
            : static_cast<uint64_t>(local["dueAfter"] | 0ULL) * 1000ULL;
    if (dueAfterMs < reviewedAtMs) dueAfterMs = reviewedAtMs;

    remote["schema"] = "mnemos.review/v2";
    remote["id"] = id;
    remote["cardId"] = cardId;
    remote["reviewedAtMs"] = reviewedAtMs;
    remote["dueAfterMs"] = dueAfterMs;
    remote["schedulerRating"] = rating;
    remote["responseTimeMs"] = local["responseTimeMs"] | 0U;

    const String cardType = local["cardType"] | "";
    remote["source"] = cardType == "multiple_choice" ? "multiple_choice" : "standard";

    // Valores consultivos (§5.2): o estado canônico vem sempre do replay.
    if (local["stabilityAfterDays"].is<float>()) {
        remote["stabilityAfterDays"] = local["stabilityAfterDays"].as<float>();
    }
    if (local["difficultyAfter"].is<float>()) {
        remote["difficultyAfter"] = local["difficultyAfter"].as<float>();
    }

    return OutboxLineKind::Push;
}

String buildReviewBatchV2(const Storage& storage) {
    JsonDocument batch;
    batch["schema"] = "mnemos.review-batch/v2";
    JsonArray reviews = batch["reviews"].to<JsonArray>();

    std::vector<String> lines;
    storage.loadReviewOutboxLines(lines);

    for (const String& line : lines) {
        JsonDocument converted;
        JsonObject remote = converted.to<JsonObject>();
        String id;
        String cardId;
        String reason;
        if (convertOutboxLine(line, remote, id, cardId, reason) != OutboxLineKind::Push) continue;
        reviews.add(remote);
    }

    String body;
    serializeJson(batch, body);
    return body;
}

}  // namespace SyncCodec
