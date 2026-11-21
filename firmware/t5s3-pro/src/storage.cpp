#include "storage.h"
#include "mnemos_contract_generated.h"

#include <ArduinoJson.h>
#include <LittleFS.h>
#include <algorithm>
#include <cstring>
#include <string>

#include "platform_sync_config.h"

namespace {
constexpr char LIBRARY_PATH[] = "/library.json";
constexpr char TEMP_LIBRARY_PATH[] = "/library.tmp";
constexpr char STATE_PATH[] = "/state.json";
constexpr char TEMP_STATE_PATH[] = "/state.tmp";
constexpr char REVIEW_HISTORY_PATH[] = "/review_history.ndjson";
constexpr char REVIEW_OUTBOX_PATH[] = "/review_outbox.ndjson";
constexpr char PROGRESS_RESET_HISTORY_PATH[] = "/progress_resets.ndjson";
constexpr char LEGACY_REVIEW_LOG_PATH[] = "/reviews.ndjson";
constexpr char SESSION_PATH[] = "/session.json";
constexpr char TEMP_SESSION_PATH[] = "/session.tmp";
constexpr char SYNC_META_PATH[] = "/sync_meta.json";
constexpr char TEMP_SYNC_META_PATH[] = "/sync_meta.tmp";
constexpr char TEMP_REVIEW_OUTBOX_PATH[] = "/review_outbox.tmp";
constexpr char REJECTED_REVIEWS_PATH[] = "/review_rejected.ndjson";
constexpr char REJECTED_REVIEWS_OLD_PATH[] = "/review_rejected.old";

// Extrai o valor de "id" de uma linha NDJSON sem desserializar a linha
// inteira. Linhas são objetos planos cujo "id" é uma string sem escapes (UUID
// ou id local). Tolera espaços em volta de ':' (linhas gravadas por outras
// ferramentas).
std::string lineId(const char* line, size_t length) {
    static const char KEY[] = "\"id\"";
    const size_t keyLength = sizeof(KEY) - 1;
    for (size_t i = 0; i + keyLength <= length; ++i) {
        if (memcmp(line + i, KEY, keyLength) != 0) continue;
        size_t p = i + keyLength;
        while (p < length && (line[p] == ' ' || line[p] == '\t')) ++p;
        if (p >= length || line[p] != ':') continue;
        ++p;
        while (p < length && (line[p] == ' ' || line[p] == '\t')) ++p;
        if (p >= length || line[p] != '"') continue;
        const size_t start = p + 1;
        size_t end = start;
        while (end < length && line[end] != '"') ++end;
        if (end >= length) return std::string();
        return std::string(line + start, end - start);
    }
    return std::string();
}

std::string lineId(const String& line) {
    return lineId(line.c_str(), line.length());
}

uint64_t idHash(const std::string& id) {
    uint64_t hash = 14695981039346656037ULL;  // FNV-1a 64
    for (unsigned char c : id) {
        hash ^= c;
        hash *= 1099511628211ULL;
    }
    return hash;
}

template <typename Fn>
void forEachLine(const String& text, Fn&& fn) {
    const char* data = text.c_str();
    const size_t length = text.length();
    size_t start = 0;
    while (start < length) {
        const char* newline = static_cast<const char*>(
            memchr(data + start, '\n', length - start));
        const size_t end = newline ? static_cast<size_t>(newline - data) : length;
        if (end > start) fn(data + start, end - start);
        start = end + 1;
    }
}
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
    // Contrato §5.2: só modos que alimentam o scheduler geram revisão na
    // conta. Prática livre continua no histórico local (métricas, replay
    // ignora) e não sobe para app/web.
    if (!event.affectsSchedule) return historyOk;
    const bool outboxOk = appendReviewToPath(REVIEW_OUTBOX_PATH, event);
    return historyOk && outboxOk;
}

String Storage::readTextFile(const char* path) const {
    if (!LittleFS.exists(path)) return String();
    File file = LittleFS.open(path, "r");
    if (!file) return String();
    String data;
    data.reserve(file.size() + 16);
    // Leitura em blocos: byte a byte custava segundos em históricos longos.
    uint8_t buffer[512];
    while (file.available()) {
        const size_t n = file.read(buffer, sizeof(buffer));
        if (n == 0) break;
        data.concat(reinterpret_cast<const char*>(buffer), n);
    }
    file.close();
    return data;
}

String Storage::reviewOutboxNdjson() const { return readTextFile(REVIEW_OUTBOX_PATH); }
String Storage::reviewHistoryNdjson() const { return readTextFile(REVIEW_HISTORY_PATH); }

bool Storage::reviewHistoryContainsId(
    const String& id) const {

    if (id.length() == 0) {
        return false;
    }

    const std::string wanted(id.c_str());
    bool found = false;
    forEachLine(reviewHistoryNdjson(), [&](const char* line, size_t length) {
        if (!found && lineId(line, length) == wanted) found = true;
    });
    return found;
}


bool Storage::appendUniqueLines(
    const char* path,
    const std::vector<String>& lines,
    uint16_t& inserted) {

    inserted = 0;
    if (lines.empty()) return true;

    // Hash de 64 bits por id num vetor ordenado: alguns milhares de revisões
    // custam poucos kB num único bloco (vai para a PSRAM), em vez de milhares
    // de alocações pequenas na RAM interna.
    std::vector<uint64_t> known;
    forEachLine(readTextFile(path), [&](const char* line, size_t length) {
        const std::string id = lineId(line, length);
        if (!id.empty()) known.push_back(idHash(id));
    });
    std::sort(known.begin(), known.end());

    File file = LittleFS.open(path, "a");
    if (!file) return false;

    bool ok = true;
    for (const String& line : lines) {
        const std::string id = lineId(line);
        if (id.empty()) continue;
        const uint64_t hash = idHash(id);
        const auto position = std::lower_bound(known.begin(), known.end(), hash);
        if (position != known.end() && *position == hash) continue;  // já existe (retry/queda)
        known.insert(position, hash);
        const size_t written = file.print(line);
        file.print('\n');
        if (written != line.length()) {
            ok = false;
            break;
        }
        ++inserted;
    }
    file.flush();
    file.close();
    return ok;
}


bool Storage::appendRemoteReviewLines(
    const std::vector<String>& lines,
    uint16_t& inserted) {

    return appendUniqueLines(REVIEW_HISTORY_PATH, lines, inserted);
}


bool Storage::appendRemoteProgressResetLines(
    const std::vector<String>& lines,
    uint16_t& inserted) {

    return appendUniqueLines(PROGRESS_RESET_HISTORY_PATH, lines, inserted);
}


bool Storage::loadReviewOutboxLines(std::vector<String>& lines) const {
    lines.clear();
    forEachLine(reviewOutboxNdjson(), [&](const char* line, size_t length) {
        String value;
        value.concat(line, length);
        value.trim();
        if (value.length() > 0) lines.push_back(value);
    });
    return true;
}


bool Storage::rewriteReviewOutbox(const std::vector<String>& lines) {
    if (lines.empty()) return clearReviewOutbox();

    File file = LittleFS.open(TEMP_REVIEW_OUTBOX_PATH, "w");
    if (!file) return false;
    bool ok = true;
    for (const String& line : lines) {
        if (file.print(line) != line.length()) {
            ok = false;
            break;
        }
        file.print('\n');
    }
    file.flush();
    file.close();
    if (!ok) {
        LittleFS.remove(TEMP_REVIEW_OUTBOX_PATH);
        return false;
    }
    LittleFS.remove(REVIEW_OUTBOX_PATH);
    return LittleFS.rename(TEMP_REVIEW_OUTBOX_PATH, REVIEW_OUTBOX_PATH);
}


bool Storage::quarantineReviewLines(
    const std::vector<String>& lines,
    const String& reason) {

    if (lines.empty()) return true;

    if (LittleFS.exists(REJECTED_REVIEWS_PATH)) {
        File current = LittleFS.open(REJECTED_REVIEWS_PATH, "r");
        const size_t size = current ? current.size() : 0;
        if (current) current.close();
        if (size > PlatformSync::REJECTED_REVIEWS_MAX_BYTES) {
            LittleFS.remove(REJECTED_REVIEWS_OLD_PATH);
            LittleFS.rename(REJECTED_REVIEWS_PATH, REJECTED_REVIEWS_OLD_PATH);
        }
    }

    File file = LittleFS.open(REJECTED_REVIEWS_PATH, "a");
    if (!file) return false;
    for (const String& line : lines) {
        JsonDocument wrapper;
        wrapper["reason"] = reason;
        JsonDocument review;
        if (!deserializeJson(review, line)) {
            wrapper["review"] = review.as<JsonVariantConst>();
        } else {
            wrapper["raw"] = line;
        }
        serializeJson(wrapper, file);
        file.print('\n');
    }
    file.flush();
    file.close();
    return true;
}


uint16_t Storage::rejectedReviewCount() const {
    uint16_t count = 0;
    forEachLine(readTextFile(REJECTED_REVIEWS_PATH), [&](const char*, size_t) { ++count; });
    return count;
}


bool Storage::appendRemoteReviewJson(
    const String& line,
    bool& inserted) {

    inserted = false;
    if (line.length() == 0) return false;

    JsonDocument row;
    if (deserializeJson(row, line)) return false;
    if (String(row["schema"] | "") != "mnemos.review/v2") return false;
    if (String(row["id"] | "").length() == 0) return false;

    uint16_t count = 0;
    const std::vector<String> lines{line};
    if (!appendRemoteReviewLines(lines, count)) return false;
    inserted = count > 0;
    return true;
}


bool Storage::clearReviewOutbox() {
    if (!LittleFS.exists(REVIEW_OUTBOX_PATH)) return true;
    return LittleFS.remove(REVIEW_OUTBOX_PATH);
}

uint16_t Storage::pendingReviewCount() const {
    uint16_t count = 0;
    forEachLine(reviewOutboxNdjson(), [&](const char* line, size_t length) {
        for (size_t i = 0; i < length; ++i) {
            if (line[i] != ' ' && line[i] != '\r') {
                ++count;
                return;
            }
        }
    });
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

uint64_t Storage::syncCursor(
    const char* key) const {

    if (!LittleFS.exists(SYNC_META_PATH)) {
        return 0ULL;
    }

    File file =
        LittleFS.open(
            SYNC_META_PATH,
            "r");

    if (!file) {
        return 0ULL;
    }

    JsonDocument doc;

    const DeserializationError error =
        deserializeJson(doc, file);

    file.close();

    if (error) {
        return 0ULL;
    }

    JsonObjectConst cursors =
        doc["cursors"].as<JsonObjectConst>();

    if (
        !cursors.isNull() &&
        cursors[key].is<uint64_t>()
    ) {
        return
            cursors[key].as<uint64_t>();
    }

    // Migração transparente do formato v1.
    if (
        String(key) == "reviews" &&
        doc["reviewsCursor"].is<uint64_t>()
    ) {
        return
            doc["reviewsCursor"].as<uint64_t>();
    }

    return 0ULL;
}


bool Storage::saveSyncCursor(
    const char* key,
    uint64_t cursor) {

    JsonDocument doc;

    if (LittleFS.exists(SYNC_META_PATH)) {
        File existing =
            LittleFS.open(
                SYNC_META_PATH,
                "r");

        if (existing) {
            if (deserializeJson(doc, existing)) {
                doc.clear();
            }

            existing.close();
        }
    }

    uint64_t legacyReviews = 0ULL;

    if (
        doc["reviewsCursor"].is<uint64_t>()
    ) {
        legacyReviews =
            doc["reviewsCursor"].as<uint64_t>();
    }

    doc["schema"] =
        "mnemos.local-sync-meta/v2";

    JsonObject cursors;

    if (
        doc["cursors"].is<JsonObject>()
    ) {
        cursors =
            doc["cursors"].as<JsonObject>();
    } else {
        cursors =
            doc["cursors"].to<JsonObject>();
    }

    if (
        !cursors["reviews"].is<uint64_t>() &&
        legacyReviews > 0
    ) {
        cursors["reviews"] =
            legacyReviews;
    }

    cursors[key] =
        cursor;

    doc.remove("reviewsCursor");

    File file =
        LittleFS.open(
            TEMP_SYNC_META_PATH,
            "w");

    if (!file) {
        return false;
    }

    const size_t written =
        serializeJson(doc, file);

    file.flush();
    file.close();

    if (written == 0) {
        LittleFS.remove(
            TEMP_SYNC_META_PATH);
        return false;
    }

    LittleFS.remove(
        SYNC_META_PATH);

    return LittleFS.rename(
        TEMP_SYNC_META_PATH,
        SYNC_META_PATH);
}


uint64_t Storage::reviewCursor() const {
    return syncCursor("reviews");
}


bool Storage::saveReviewCursor(
    uint64_t cursor) {

    return saveSyncCursor(
        "reviews",
        cursor);
}


uint64_t Storage::progressResetCursor() const {
    return syncCursor(
        "progressResets");
}


bool Storage::saveProgressResetCursor(
    uint64_t cursor) {

    return saveSyncCursor(
        "progressResets",
        cursor);
}


bool Storage::appendRemoteProgressResetJson(
    const String& line,
    bool& inserted) {

    inserted = false;

    JsonDocument row;
    if (deserializeJson(row, line)) return false;
    if (String(row["schema"] | "") != "mnemos.progress-reset/v2") return false;
    if (String(row["id"] | "").length() == 0) return false;

    uint16_t count = 0;
    const std::vector<String> lines{line};
    if (!appendRemoteProgressResetLines(lines, count)) return false;
    inserted = count > 0;
    return true;
}


String Storage::progressResetHistoryNdjson()
    const {

    return readTextFile(
        PROGRESS_RESET_HISTORY_PATH);
}



uint64_t Storage::settingsCursor() const {
    return syncCursor(
        "userSettings");
}


bool Storage::saveSettingsCursor(
    uint64_t cursor) {

    return saveSyncCursor(
        "userSettings",
        cursor);
}


double Storage::desiredRetention() const {

    const double fallback =
        MnemosContract::DESIRED_RETENTION;

    if (!LittleFS.exists(SYNC_META_PATH)) {
        return fallback;
    }

    File file =
        LittleFS.open(
            SYNC_META_PATH,
            "r");

    if (!file) {
        return fallback;
    }

    JsonDocument doc;

    const DeserializationError error =
        deserializeJson(doc, file);

    file.close();

    if (error) {
        return fallback;
    }

    JsonVariantConst value =
        doc["settings"]
           ["desiredRetention"];

    if (!value.is<double>()) {
        return fallback;
    }

    const double retention =
        value.as<double>();

    if (
        retention <= 0.0 ||
        retention >= 1.0
    ) {
        return fallback;
    }

    return retention;
}


bool Storage::saveDesiredRetention(
    double value) {

    if (
        value <= 0.0 ||
        value >= 1.0
    ) {
        return false;
    }

    JsonDocument doc;

    if (LittleFS.exists(SYNC_META_PATH)) {
        File existing =
            LittleFS.open(
                SYNC_META_PATH,
                "r");

        if (existing) {
            if (
                deserializeJson(
                    doc,
                    existing)
            ) {
                doc.clear();
            }

            existing.close();
        }
    }

    // Migração transparente do metadata v1.
    uint64_t legacyReviews = 0ULL;

    if (
        doc["reviewsCursor"]
            .is<uint64_t>()
    ) {
        legacyReviews =
            doc["reviewsCursor"]
                .as<uint64_t>();
    }

    doc["schema"] =
        "mnemos.local-sync-meta/v2";

    JsonObject cursors =
        doc["cursors"]
            .as<JsonObject>();

    if (cursors.isNull()) {
        cursors =
            doc["cursors"]
                .to<JsonObject>();
    }

    if (
        !cursors["reviews"]
            .is<uint64_t>() &&
        legacyReviews > 0
    ) {
        cursors["reviews"] =
            legacyReviews;
    }

    JsonObject settings =
        doc["settings"]
            .as<JsonObject>();

    if (settings.isNull()) {
        settings =
            doc["settings"]
                .to<JsonObject>();
    }

    settings["desiredRetention"] =
        value;

    doc.remove("reviewsCursor");

    File file =
        LittleFS.open(
            TEMP_SYNC_META_PATH,
            "w");

    if (!file) {
        return false;
    }

    const size_t written =
        serializeJson(
            doc,
            file);

    file.flush();
    file.close();

    if (written == 0) {
        LittleFS.remove(
            TEMP_SYNC_META_PATH);
        return false;
    }

    LittleFS.remove(
        SYNC_META_PATH);

    return LittleFS.rename(
        TEMP_SYNC_META_PATH,
        SYNC_META_PATH);
}


bool Storage::resetAll() {
    const char* paths[] = {
        LIBRARY_PATH, TEMP_LIBRARY_PATH, STATE_PATH, TEMP_STATE_PATH,
        REVIEW_HISTORY_PATH, REVIEW_OUTBOX_PATH, PROGRESS_RESET_HISTORY_PATH, LEGACY_REVIEW_LOG_PATH,
        SESSION_PATH, TEMP_SESSION_PATH,
        SYNC_META_PATH, TEMP_SYNC_META_PATH,
        TEMP_REVIEW_OUTBOX_PATH, REJECTED_REVIEWS_PATH, REJECTED_REVIEWS_OLD_PATH,
    };
    bool ok = true;
    for (const char* path : paths) {
        if (LittleFS.exists(path)) ok &= LittleFS.remove(path);
    }
    return ok;
}


bool Storage::readSyncMeta(JsonDocument& doc) const {
    doc.clear();
    if (!LittleFS.exists(SYNC_META_PATH)) return false;
    File file = LittleFS.open(SYNC_META_PATH, "r");
    if (!file) return false;
    const DeserializationError error = deserializeJson(doc, file);
    file.close();
    if (error) {
        doc.clear();
        return false;
    }
    return true;
}


bool Storage::writeSyncMeta(JsonDocument& doc) {
    doc["schema"] = "mnemos.local-sync-meta/v2";
    File file = LittleFS.open(TEMP_SYNC_META_PATH, "w");
    if (!file) return false;
    const size_t written = serializeJson(doc, file);
    file.flush();
    file.close();
    if (written == 0) {
        LittleFS.remove(TEMP_SYNC_META_PATH);
        return false;
    }
    LittleFS.remove(SYNC_META_PATH);
    return LittleFS.rename(TEMP_SYNC_META_PATH, SYNC_META_PATH);
}


String Storage::syncMetaString(const char* key) const {
    JsonDocument doc;
    if (!readSyncMeta(doc)) return String();
    return String(doc["platform"][key] | "");
}


bool Storage::saveSyncMetaString(const char* key, const String& value) {
    JsonDocument doc;
    readSyncMeta(doc);
    JsonObject platform = doc["platform"].as<JsonObject>();
    if (platform.isNull()) platform = doc["platform"].to<JsonObject>();
    if (String(platform[key] | "") == value) return true;
    platform[key] = value;
    return writeSyncMeta(doc);
}


bool Storage::libraryFromBackend() const {
    return syncMetaString("librarySource") == "backend";
}


bool Storage::setLibraryFromBackend(bool value) {
    return saveSyncMetaString("librarySource", value ? "backend" : "local");
}


bool Storage::resetSyncCursors() {
    JsonDocument doc;
    readSyncMeta(doc);
    doc.remove("reviewsCursor");
    JsonObject cursors = doc["cursors"].to<JsonObject>();
    cursors["reviews"] = 0ULL;
    cursors["progressResets"] = 0ULL;
    cursors["userSettings"] = 0ULL;
    return writeSyncMeta(doc);
}
