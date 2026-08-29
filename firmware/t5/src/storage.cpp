#include "storage.h"

#include <ArduinoJson.h>
#include <LittleFS.h>
#include <algorithm>

namespace {
constexpr char LIBRARY_PATH[] = "/library.json";
constexpr char TEMP_LIBRARY_PATH[] = "/library.tmp";
constexpr char STATE_PATH[] = "/state.json";
constexpr char TEMP_STATE_PATH[] = "/state.tmp";
constexpr char REVIEW_HISTORY_PATH[] = "/review_history.ndjson";
constexpr char REVIEW_OUTBOX_PATH[] = "/review_outbox.ndjson";
constexpr char LEGACY_REVIEW_LOG_PATH[] = "/reviews.ndjson";
constexpr char SESSION_PATH[] = "/session.json";
constexpr char TEMP_SESSION_PATH[] = "/session.tmp";
}

bool Storage::begin() {
    if (!LittleFS.begin(true, "/littlefs", 10, "littlefs")) {
        Serial.println("[storage] falha ao montar LittleFS");
        return false;
    }
    Serial.println("[storage] LittleFS montado");
    migrateLegacyReviewLog();
    return true;
}

bool Storage::loadLibrary(CardDefinition* cards, CardState* states, size_t maxCards, size_t& count) {
    count = 0;
    if (!LittleFS.exists(LIBRARY_PATH)) return false;

    File file = LittleFS.open(LIBRARY_PATH, "r");
    if (!file) return false;

    JsonDocument doc;
    const DeserializationError error = deserializeJson(doc, file);
    file.close();
    if (error) {
        Serial.printf("[storage] library.json invalido: %s\n", error.c_str());
        return false;
    }

    JsonArrayConst items = doc["cards"].as<JsonArrayConst>();
    for (JsonObjectConst obj : items) {
        if (count >= maxCards) break;
        CardDefinition& card = cards[count];
        card = CardDefinition{};
        card.id = obj["id"] | "";
        card.deckId = obj["deckId"] | "";
        card.deck = obj["deck"] | "Sem baralho";
        card.type = obj["type"] | "open_recall";
        if (card.type == "basic") card.type = "open_recall";  // migração v1
        card.format = obj["format"] | "plain";
        card.question = obj["question"].is<const char*>() ? String(obj["question"].as<const char*>()) : String(obj["prompt"] | "");
        card.answer = obj["answer"] | "";
        card.revision = obj["revision"] | 1ULL;
        card.optionCount = 0;
        card.correctOptionIndex = obj["correctOptionIndex"] | -1;
        for (JsonVariantConst option : obj["options"].as<JsonArrayConst>()) {
            if (card.optionCount >= Config::MAX_CARD_OPTIONS) break;
            card.options[card.optionCount++] = option.as<String>();
        }
        if (card.type == "true_false" && card.optionCount == 0) {
            card.options[0] = "Verdadeiro";
            card.options[1] = "Falso";
            card.optionCount = 2;
        }

        states[count] = CardState{};
        states[count].id = card.id;
        ++count;
    }

    Serial.printf("[storage] biblioteca carregada: %u cartoes\n", static_cast<unsigned>(count));
    return true;
}

bool Storage::saveLibrary(const CardDefinition* cards, const CardState* states, size_t count) {
    JsonDocument doc;
    doc["schema"] = "mnemos.local-library/v2";
    JsonArray items = doc["cards"].to<JsonArray>();

    for (size_t i = 0; i < count; ++i) {
        JsonObject obj = items.add<JsonObject>();
        obj["id"] = cards[i].id;
        obj["deckId"] = cards[i].deckId;
        obj["deck"] = cards[i].deck;
        obj["type"] = cards[i].type;
        obj["format"] = cards[i].format;
        obj["question"] = cards[i].question;
        obj["answer"] = cards[i].answer;
        obj["revision"] = cards[i].revision;
        if (cards[i].optionCount > 0) {
            JsonArray options = obj["options"].to<JsonArray>();
            for (uint8_t o = 0; o < cards[i].optionCount; ++o) options.add(cards[i].options[o]);
            obj["correctOptionIndex"] = cards[i].correctOptionIndex;
        }
        (void)states;  // estados vivem em state.json; argumento preserva API transacional.
    }

    File file = LittleFS.open(TEMP_LIBRARY_PATH, "w");
    if (!file) return false;
    const size_t written = serializeJson(doc, file);
    file.flush();
    file.close();
    if (written == 0) {
        LittleFS.remove(TEMP_LIBRARY_PATH);
        return false;
    }
    LittleFS.remove(LIBRARY_PATH);
    return LittleFS.rename(TEMP_LIBRARY_PATH, LIBRARY_PATH);
}

bool Storage::loadStates(CardState* states, size_t count) {
    if (!LittleFS.exists(STATE_PATH)) return false;
    File file = LittleFS.open(STATE_PATH, "r");
    if (!file) return false;

    JsonDocument doc;
    const DeserializationError error = deserializeJson(doc, file);
    file.close();
    if (error) return false;

    for (JsonObjectConst obj : doc["cards"].as<JsonArrayConst>()) {
        const String id = obj["id"] | "";
        for (size_t i = 0; i < count; ++i) {
            if (states[i].id != id) continue;
            states[i].difficulty = obj["difficulty"] | 5.0f;
            states[i].stabilityDays = obj["stabilityDays"] | 0.0f;
            states[i].dueAt = obj["dueAt"] | 0U;
            states[i].lastReviewedAt = obj["lastReviewedAt"] | 0U;
            states[i].repetitions = obj["repetitions"] | 0U;
            states[i].lapses = obj["lapses"] | 0U;
            states[i].lastRating = obj["lastRating"] | 0U;
            states[i].illusionOfMastery = obj["illusionOfMastery"] | false;

            JsonObjectConst fsrs = obj["fsrs"].as<JsonObjectConst>();
            if (!fsrs.isNull()) {
                states[i].fsrsDifficulty =
                    fsrs["difficulty"] | 0.0;

                states[i].fsrsStabilityDays =
                    fsrs["stabilityDays"] | 0.0;

                states[i].fsrsDueAtMs =
                    fsrs["dueAtMs"].is<uint64_t>()
                        ? fsrs["dueAtMs"].as<uint64_t>()
                        : 0ULL;

                states[i].fsrsLastReviewAtMs =
                    fsrs["lastReviewAtMs"].is<uint64_t>()
                        ? fsrs["lastReviewAtMs"].as<uint64_t>()
                        : 0ULL;

                states[i].fsrsRepetitions =
                    fsrs["repetitions"] | 0U;

                states[i].fsrsLapses =
                    fsrs["lapses"] | 0U;

                states[i].fsrsPhase =
                    fsrs["phase"] | 1U;

                states[i].fsrsStep =
                    fsrs["step"] | 0;

                states[i].fsrsInitialized =
                    fsrs["initialized"] | false;
            }

            // Migração de v0.4: aproxima S pelo último intervalo se o campo D/S ainda não existia.
            if (states[i].stabilityDays <= 0.0f && obj["intervalSeconds"].is<uint32_t>()) {
                const uint32_t seconds = obj["intervalSeconds"].as<uint32_t>();
                if (seconds > 0) states[i].stabilityDays = std::max(0.05f, static_cast<float>(seconds) / 86400.0f);
            }
            break;
        }
    }
    return true;
}

bool Storage::saveStates(const CardState* states, size_t count) {
    JsonDocument doc;
    doc["schema"] = "mnemos.local-card-state/v3";
    JsonArray cards = doc["cards"].to<JsonArray>();

    for (size_t i = 0; i < count; ++i) {
        JsonObject obj = cards.add<JsonObject>();
        obj["id"] = states[i].id;
        obj["difficulty"] = states[i].difficulty;
        obj["stabilityDays"] = states[i].stabilityDays;
        obj["dueAt"] = states[i].dueAt;
        obj["lastReviewedAt"] = states[i].lastReviewedAt;
        obj["repetitions"] = states[i].repetitions;
        obj["lapses"] = states[i].lapses;
        obj["lastRating"] = states[i].lastRating;
        obj["illusionOfMastery"] = states[i].illusionOfMastery;

        JsonObject fsrs = obj["fsrs"].to<JsonObject>();
        fsrs["difficulty"] = states[i].fsrsDifficulty;
        fsrs["stabilityDays"] = states[i].fsrsStabilityDays;
        fsrs["dueAtMs"] = states[i].fsrsDueAtMs;
        fsrs["lastReviewAtMs"] = states[i].fsrsLastReviewAtMs;
        fsrs["repetitions"] = states[i].fsrsRepetitions;
        fsrs["lapses"] = states[i].fsrsLapses;
        fsrs["phase"] = states[i].fsrsPhase;
        fsrs["step"] = states[i].fsrsStep;
        fsrs["initialized"] = states[i].fsrsInitialized;
    }

    File file = LittleFS.open(TEMP_STATE_PATH, "w");
    if (!file) return false;
    const size_t written = serializeJson(doc, file);
    file.flush();
    file.close();
    if (written == 0) {
        LittleFS.remove(TEMP_STATE_PATH);
        return false;
    }
    LittleFS.remove(STATE_PATH);
    return LittleFS.rename(TEMP_STATE_PATH, STATE_PATH);
}

bool Storage::saveSession(const CardDefinition* cards,
                          const uint8_t* queue,
                          uint8_t sessionCount,
                          uint8_t currentPosition,
                          SessionMode mode,
                          const SessionStats& stats) {
    if (sessionCount == 0 || currentPosition >= sessionCount) return clearSession();

    JsonDocument doc;
    doc["schema"] = "mnemos.local-session/v2";
    doc["position"] = currentPosition;
    doc["mode"] = sessionModeName(mode);
    JsonArray ids = doc["cardIds"].to<JsonArray>();
    for (uint8_t i = 0; i < sessionCount; ++i) ids.add(cards[queue[i]].id);
    doc["stats"]["reviewed"] = stats.reviewed;
    doc["stats"]["correct"] = stats.correct;
    doc["stats"]["incorrect"] = stats.incorrect;

    File file = LittleFS.open(TEMP_SESSION_PATH, "w");
    if (!file) return false;
    const size_t written = serializeJson(doc, file);
    file.flush();
    file.close();
    if (written == 0) {
        LittleFS.remove(TEMP_SESSION_PATH);
        return false;
    }
    LittleFS.remove(SESSION_PATH);
    return LittleFS.rename(TEMP_SESSION_PATH, SESSION_PATH);
}

bool Storage::loadSession(const CardDefinition* cards,
                          size_t cardCount,
                          uint8_t* queue,
                          uint8_t maxQueue,
                          uint8_t& sessionCount,
                          uint8_t& currentPosition,
                          SessionMode& mode,
                          SessionStats& stats) {
    sessionCount = 0;
    currentPosition = 0;
    mode = SessionMode::Review;
    stats = SessionStats{};
    if (!LittleFS.exists(SESSION_PATH)) return false;

    File file = LittleFS.open(SESSION_PATH, "r");
    if (!file) return false;
    JsonDocument doc;
    const DeserializationError error = deserializeJson(doc, file);
    file.close();
    if (error) {
        clearSession();
        return false;
    }

    const uint8_t savedPosition = doc["position"] | 0U;
    JsonArrayConst ids = doc["cardIds"].as<JsonArrayConst>();
    if (ids.size() == 0 || savedPosition >= ids.size()) {
        clearSession();
        return false;
    }

    const String modeText = doc["mode"] | "review";
    if (modeText == "practice") mode = SessionMode::Practice;
    else if (modeText == "cram") mode = SessionMode::Cram;

    for (size_t saved = savedPosition; saved < ids.size() && sessionCount < maxQueue; ++saved) {
        const String id = ids[saved] | "";
        for (size_t card = 0; card < cardCount; ++card) {
            if (cards[card].id == id) {
                queue[sessionCount++] = static_cast<uint8_t>(card);
                break;
            }
        }
    }
    if (sessionCount == 0) {
        clearSession();
        return false;
    }

    currentPosition = 0;
    stats.mode = mode;
    stats.reviewed = doc["stats"]["reviewed"] | 0U;
    stats.correct = doc["stats"]["correct"] | 0U;
    stats.incorrect = doc["stats"]["incorrect"] | 0U;
    stats.startedAtMs = millis();
    return true;
}

bool Storage::clearSession() {
    bool ok = true;
    if (LittleFS.exists(SESSION_PATH)) ok &= LittleFS.remove(SESSION_PATH);
    if (LittleFS.exists(TEMP_SESSION_PATH)) ok &= LittleFS.remove(TEMP_SESSION_PATH);
    return ok;
}

bool Storage::appendReviewToPath(const char* path, const ReviewEvent& event) {
    File file = LittleFS.open(path, "a");
    if (!file) return false;

    JsonDocument doc;
    doc["schema"] = "mnemos.review/v2";
    doc["id"] = event.id;
    doc["cardId"] = event.cardId;
    doc["deckId"] = event.deckId;
    doc["cardType"] = event.cardType;
    doc["reviewedAt"] = event.reviewedAt;
    doc["responseTimeMs"] = event.responseTimeMs;
    doc["confidence"] = event.confidence;
    doc["outcome"] = outcomeName(event.outcome);
    doc["effort"] = effortName(event.effort);
    doc["schedulerRating"] = static_cast<uint8_t>(event.schedulerRating);
    doc["sessionMode"] = sessionModeName(event.sessionMode);
    doc["affectsSchedule"] = event.affectsSchedule;
    doc["automaticEvaluation"] = event.automaticEvaluation;
    if (event.selectedOptionIndex >= 0) doc["selectedOptionIndex"] = event.selectedOptionIndex;
    doc["difficultyBefore"] = event.difficultyBefore;
    doc["difficultyAfter"] = event.difficultyAfter;
    doc["stabilityBeforeDays"] = event.stabilityBefore;
    doc["stabilityAfterDays"] = event.stabilityAfter;
    doc["retrievabilityBefore"] = event.retrievabilityBefore;
    doc["dueBefore"] = event.dueBefore;
    doc["dueAfter"] = event.dueAfter;
    doc["source"] = "terminal";

    const size_t written = serializeJson(doc, file);
    file.println();
    file.flush();
    file.close();
    return written > 0;
}

bool Storage::appendReview(const ReviewEvent& event) {
    const bool historyOk = appendReviewToPath(REVIEW_HISTORY_PATH, event);
    const bool outboxOk = appendReviewToPath(REVIEW_OUTBOX_PATH, event);
    return historyOk && outboxOk;
}

String Storage::readTextFile(const char* path) const {
    if (!LittleFS.exists(path)) return String();
    File file = LittleFS.open(path, "r");
    if (!file) return String();
    String data;
    data.reserve(file.size() + 16);
    while (file.available()) data += static_cast<char>(file.read());
    file.close();
    return data;
}

String Storage::reviewOutboxNdjson() const { return readTextFile(REVIEW_OUTBOX_PATH); }
String Storage::reviewHistoryNdjson() const { return readTextFile(REVIEW_HISTORY_PATH); }

bool Storage::clearReviewOutbox() {
    if (!LittleFS.exists(REVIEW_OUTBOX_PATH)) return true;
    return LittleFS.remove(REVIEW_OUTBOX_PATH);
}

uint16_t Storage::pendingReviewCount() const {
    const String data = reviewOutboxNdjson();
    if (data.length() == 0) return 0;
    uint16_t count = 0;
    for (size_t i = 0; i < data.length(); ++i) if (data[i] == '\n') ++count;
    if (!data.endsWith("\n")) ++count;
    return count;
}

bool Storage::migrateLegacyReviewLog() {
    if (!LittleFS.exists(LEGACY_REVIEW_LOG_PATH)) return true;
    const String legacy = readTextFile(LEGACY_REVIEW_LOG_PATH);
    if (legacy.length() == 0) {
        LittleFS.remove(LEGACY_REVIEW_LOG_PATH);
        return true;
    }
    // Mantém o evento legado literalmente. Métricas v0.5 ignoram linhas sem
    // outcome v2, mas o histórico não é descartado durante a migração.
    File history = LittleFS.open(REVIEW_HISTORY_PATH, "a");
    File outbox = LittleFS.open(REVIEW_OUTBOX_PATH, "a");
    if (!history || !outbox) {
        if (history) history.close();
        if (outbox) outbox.close();
        return false;
    }
    history.print(legacy);
    outbox.print(legacy);
    history.close();
    outbox.close();
    return LittleFS.remove(LEGACY_REVIEW_LOG_PATH);
}

bool Storage::resetAll() {
    const char* paths[] = {
        LIBRARY_PATH, TEMP_LIBRARY_PATH, STATE_PATH, TEMP_STATE_PATH,
        REVIEW_HISTORY_PATH, REVIEW_OUTBOX_PATH, LEGACY_REVIEW_LOG_PATH,
        SESSION_PATH, TEMP_SESSION_PATH,
    };
    bool ok = true;
    for (const char* path : paths) {
        if (LittleFS.exists(path)) ok &= LittleFS.remove(path);
    }
    return ok;
}
