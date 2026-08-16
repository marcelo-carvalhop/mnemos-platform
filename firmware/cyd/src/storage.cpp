#include "storage.h"

#include <ArduinoJson.h>
#include <LittleFS.h>

namespace {
constexpr char LIBRARY_PATH[] = "/library.json";
constexpr char TEMP_LIBRARY_PATH[] = "/library.tmp";
constexpr char STATE_PATH[] = "/state.json";
constexpr char TEMP_STATE_PATH[] = "/state.tmp";
constexpr char REVIEW_LOG_PATH[] = "/reviews.ndjson";
constexpr char SESSION_PATH[] = "/session.json";
constexpr char TEMP_SESSION_PATH[] = "/session.tmp";
}

bool Storage::begin() {
    if (LittleFS.begin(true)) {
        Serial.println("[storage] LittleFS montado");
        return true;
    }
    Serial.println("[storage] falha ao montar LittleFS");
    return false;
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
        cards[count].id = obj["id"] | "";
        cards[count].deckId = obj["deckId"] | "";
        cards[count].deck = obj["deck"] | "Sem baralho";
        cards[count].type = obj["type"] | "basic";
        cards[count].format = obj["format"] | "plain";
        cards[count].question = obj["question"] | "";
        cards[count].answer = obj["answer"] | "";
        cards[count].revision = obj["revision"] | 1ULL;

        states[count] = CardState{};
        states[count].id = cards[count].id;
        states[count].dueAt = obj["dueAt"] | 0U;
        states[count].intervalSeconds = obj["intervalSeconds"] | 0U;
        states[count].repetitions = obj["repetitions"] | 0U;
        states[count].lapses = obj["lapses"] | 0U;
        states[count].lastRating = obj["lastRating"] | 0U;
        ++count;
    }

    Serial.printf("[storage] biblioteca carregada: %u cartoes\n", static_cast<unsigned>(count));
    return true;
}

bool Storage::saveLibrary(const CardDefinition* cards, const CardState* states, size_t count) {
    JsonDocument doc;
    doc["schema"] = 1;
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
        obj["dueAt"] = states[i].dueAt;
        obj["intervalSeconds"] = states[i].intervalSeconds;
        obj["repetitions"] = states[i].repetitions;
        obj["lapses"] = states[i].lapses;
        obj["lastRating"] = states[i].lastRating;
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
    DeserializationError error = deserializeJson(doc, file);
    file.close();
    if (error) return false;

    JsonArrayConst cards = doc["cards"].as<JsonArrayConst>();
    for (JsonObjectConst obj : cards) {
        const String id = obj["id"] | "";
        for (size_t i = 0; i < count; ++i) {
            if (states[i].id != id) continue;
            states[i].dueAt = obj["dueAt"] | 0U;
            states[i].intervalSeconds = obj["intervalSeconds"] | 0U;
            states[i].repetitions = obj["repetitions"] | 0U;
            states[i].lapses = obj["lapses"] | 0U;
            states[i].lastRating = obj["lastRating"] | 0U;
            break;
        }
    }
    return true;
}

bool Storage::saveStates(const CardState* states, size_t count) {
    JsonDocument doc;
    doc["schema"] = 1;
    JsonArray cards = doc["cards"].to<JsonArray>();

    for (size_t i = 0; i < count; ++i) {
        JsonObject obj = cards.add<JsonObject>();
        obj["id"] = states[i].id;
        obj["dueAt"] = states[i].dueAt;
        obj["intervalSeconds"] = states[i].intervalSeconds;
        obj["repetitions"] = states[i].repetitions;
        obj["lapses"] = states[i].lapses;
        obj["lastRating"] = states[i].lastRating;
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
                          const SessionStats& stats) {
    if (sessionCount == 0 || currentPosition >= sessionCount) return clearSession();

    JsonDocument doc;
    doc["schema"] = 1;
    doc["position"] = currentPosition;
    JsonArray ids = doc["cardIds"].to<JsonArray>();
    for (uint8_t i = 0; i < sessionCount; ++i) ids.add(cards[queue[i]].id);
    doc["stats"]["reviewed"] = stats.reviewed;
    JsonArray ratings = doc["stats"]["ratings"].to<JsonArray>();
    for (uint8_t i = 0; i < 4; ++i) ratings.add(stats.ratingCounts[i]);

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
                          SessionStats& stats) {
    sessionCount = 0;
    currentPosition = 0;
    stats = SessionStats{};
    if (!LittleFS.exists(SESSION_PATH)) return false;

    File file = LittleFS.open(SESSION_PATH, "r");
    if (!file) return false;
    JsonDocument doc;
    const DeserializationError error = deserializeJson(doc, file);
    file.close();
    if (error || (doc["schema"] | 0) != 1) {
        clearSession();
        return false;
    }

    const uint8_t savedPosition = doc["position"] | 0U;
    JsonArrayConst ids = doc["cardIds"].as<JsonArrayConst>();
    if (ids.size() == 0 || savedPosition >= ids.size()) {
        clearSession();
        return false;
    }

    // Restore only the unfinished suffix. Mapping by stable card id makes the
    // session tolerant to library reordering and safely drops removed cards.
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
    stats.reviewed = doc["stats"]["reviewed"] | 0U;
    JsonArrayConst ratings = doc["stats"]["ratings"].as<JsonArrayConst>();
    for (uint8_t i = 0; i < 4; ++i) {
        stats.ratingCounts[i] = i < ratings.size()
            ? ratings[i].as<uint16_t>()
            : 0U;
    }
    stats.startedAtMs = millis();
    return true;
}

bool Storage::clearSession() {
    bool ok = true;
    if (LittleFS.exists(SESSION_PATH)) ok &= LittleFS.remove(SESSION_PATH);
    if (LittleFS.exists(TEMP_SESSION_PATH)) ok &= LittleFS.remove(TEMP_SESSION_PATH);
    return ok;
}

bool Storage::appendReview(const ReviewEvent& event) {
    File file = LittleFS.open(REVIEW_LOG_PATH, "a");
    if (!file) return false;

    JsonDocument doc;
    doc["schema"] = "mnemos.review/v1";
    doc["id"] = event.id;
    doc["cardId"] = event.cardId;
    doc["reviewedAt"] = event.reviewedAt;
    doc["responseTimeMs"] = event.responseTimeMs;
    doc["confidence"] = event.confidence;
    doc["rating"] = event.rating;
    doc["intervalBeforeSeconds"] = event.intervalBefore;
    doc["intervalAfterSeconds"] = event.intervalAfter;
    doc["source"] = "terminal";

    const size_t written = serializeJson(doc, file);
    file.println();
    file.flush();
    file.close();
    ++reviewSequence_;
    return written > 0;
}

String Storage::reviewsNdjson() const {
    if (!LittleFS.exists(REVIEW_LOG_PATH)) return String();
    File file = LittleFS.open(REVIEW_LOG_PATH, "r");
    if (!file) return String();
    String data;
    data.reserve(file.size() + 16);
    while (file.available()) data += static_cast<char>(file.read());
    file.close();
    return data;
}

bool Storage::clearReviews() {
    if (!LittleFS.exists(REVIEW_LOG_PATH)) return true;
    return LittleFS.remove(REVIEW_LOG_PATH);
}

bool Storage::resetAll() {
    bool ok = true;
    if (LittleFS.exists(LIBRARY_PATH)) ok &= LittleFS.remove(LIBRARY_PATH);
    if (LittleFS.exists(TEMP_LIBRARY_PATH)) ok &= LittleFS.remove(TEMP_LIBRARY_PATH);
    if (LittleFS.exists(STATE_PATH)) ok &= LittleFS.remove(STATE_PATH);
    if (LittleFS.exists(TEMP_STATE_PATH)) ok &= LittleFS.remove(TEMP_STATE_PATH);
    if (LittleFS.exists(REVIEW_LOG_PATH)) ok &= LittleFS.remove(REVIEW_LOG_PATH);
    if (LittleFS.exists(SESSION_PATH)) ok &= LittleFS.remove(SESSION_PATH);
    if (LittleFS.exists(TEMP_SESSION_PATH)) ok &= LittleFS.remove(TEMP_SESSION_PATH);
    return ok;
}
