#include "metrics_service.h"

#include <ArduinoJson.h>
#include <algorithm>
#include "config.h"
#include "storage.h"
#include "time_service.h"

MetricsService::MetricsService(Storage& storage,
                               TimeService& clock,
                               CardDefinition* cards,
                               CardState* states,
                               size_t& cardCount)
    : storage_(storage), clock_(clock), cards_(cards), states_(states), cardCount_(cardCount) {}

int MetricsService::findCardIndex(const String& cardId) const {
    for (size_t i = 0; i < cardCount_; ++i) if (cards_[i].id == cardId) return static_cast<int>(i);
    return -1;
}

String MetricsService::buildJson() const {
    const uint32_t nowEpoch = clock_.now();
    const uint32_t window30 = nowEpoch > 30U * 86400U ? nowEpoch - 30U * 86400U : 0U;
    const uint32_t window56 = nowEpoch > 56U * 86400U ? nowEpoch - 56U * 86400U : 0U;

    uint32_t scheduledTotal30 = 0;
    uint32_t scheduledCorrect30 = 0;
    uint32_t scheduledIncorrect30 = 0;
    uint32_t overconfidentIncorrect30 = 0;
    uint32_t responseCount30 = 0;
    uint64_t responseMs30 = 0;
    uint16_t daily[30] = {0};
    uint16_t weeklyTotal[8] = {0};
    uint16_t weeklyCorrect[8] = {0};

    struct DeckAgg {
        String id;
        String name;
        uint32_t total = 0;
        uint32_t correct = 0;
    };
    DeckAgg decks[Config::MAX_DEVICE_CARDS];
    size_t deckCount = 0;

    const String history = storage_.reviewHistoryNdjson();
    int start = 0;
    while (start < static_cast<int>(history.length())) {
        int end = history.indexOf('\n', start);
        if (end < 0) end = static_cast<int>(history.length());
        const String line = history.substring(start, end);
        start = end + 1;
        if (line.length() == 0) continue;

        JsonDocument row;
        if (deserializeJson(row, line)) continue;
        if (String(row["schema"] | "") != "mnemos.review/v2") continue;

        const uint32_t reviewedAt = row["reviewedAt"] | 0U;
        const bool affects = row["affectsSchedule"] | false;
        const String sessionMode = row["sessionMode"] | "review";
        const String outcome = row["outcome"] | "unknown";
        const uint8_t confidence = row["confidence"] | 0U;
        const uint32_t responseMs = row["responseTimeMs"] | 0U;
        const bool scheduled = affects && sessionMode == "review";

        if (reviewedAt >= window30) {
            const uint32_t ageDays = nowEpoch >= reviewedAt ? (nowEpoch - reviewedAt) / 86400U : 0U;
            if (ageDays < 30) ++daily[29U - ageDays];
            if (responseMs > 0) { ++responseCount30; responseMs30 += responseMs; }
            if (scheduled) {
                ++scheduledTotal30;
                if (outcome == "correct") ++scheduledCorrect30;
                else if (outcome == "incorrect") {
                    ++scheduledIncorrect30;
                    if (confidence >= 70U) ++overconfidentIncorrect30;
                }

                String deckId = row["deckId"] | "";
                String deckName;
                const int cardIndex = findCardIndex(row["cardId"] | "");
                if (cardIndex >= 0) {
                    if (deckId.length() == 0) deckId = cards_[cardIndex].deckId;
                    deckName = cards_[cardIndex].deck;
                }
                if (deckId.length() > 0) {
                    size_t d = 0;
                    while (d < deckCount && decks[d].id != deckId) ++d;
                    if (d == deckCount && deckCount < Config::MAX_DEVICE_CARDS) {
                        decks[d].id = deckId;
                        decks[d].name = deckName;
                        ++deckCount;
                    }
                    if (d < deckCount) {
                        ++decks[d].total;
                        if (outcome == "correct") ++decks[d].correct;
                    }
                }
            }
        }

        if (scheduled && reviewedAt >= window56) {
            const uint32_t ageDays = nowEpoch >= reviewedAt ? (nowEpoch - reviewedAt) / 86400U : 0U;
            const uint8_t weekAge = static_cast<uint8_t>(std::min<uint32_t>(7U, ageDays / 7U));
            const uint8_t slot = 7U - weekAge;
            ++weeklyTotal[slot];
            if (outcome == "correct") ++weeklyCorrect[slot];
        }
    }

    uint16_t maturityNew = 0, maturityLearning = 0, maturityYoung = 0, maturityMature = 0;
    uint16_t difficultyBins[10] = {0};
    uint16_t forecast[30] = {0};
    for (size_t i = 0; i < cardCount_; ++i) {
        const CardState& state = states_[i];
        if (state.lastReviewedAt == 0) ++maturityNew;
        else if (state.stabilityDays < 1.0f) ++maturityLearning;
        else if (state.stabilityDays < 21.0f) ++maturityYoung;
        else ++maturityMature;

        int bin = static_cast<int>(state.difficulty) - 1;
        bin = std::max(0, std::min(9, bin));
        ++difficultyBins[bin];

        if (state.dueAt >= nowEpoch) {
            const uint32_t day = (state.dueAt - nowEpoch) / 86400U;
            if (day < 30) ++forecast[day];
        }
    }

    JsonDocument doc;
    doc["schema"] = "mnemos.metrics/v1";
    doc["generatedAt"] = nowEpoch;
    doc["retentionTarget"] = Config::RETENTION_TARGET;
    doc["retention30d"]["total"] = scheduledTotal30;
    doc["retention30d"]["correct"] = scheduledCorrect30;
    doc["retention30d"]["percent"] = scheduledTotal30 == 0 ? 0.0f : 100.0f * scheduledCorrect30 / scheduledTotal30;
    doc["metacognition"]["incorrect"] = scheduledIncorrect30;
    doc["metacognition"]["overconfidentIncorrect"] = overconfidentIncorrect30;
    doc["metacognition"]["overconfidencePercent"] = scheduledIncorrect30 == 0 ? 0.0f : 100.0f * overconfidentIncorrect30 / scheduledIncorrect30;
    doc["responseTime30d"]["samples"] = responseCount30;
    doc["responseTime30d"]["meanMs"] = responseCount30 == 0 ? 0U : static_cast<uint32_t>(responseMs30 / responseCount30);

    JsonArray consistency = doc["consistency30d"].to<JsonArray>();
    for (uint8_t i = 0; i < 30; ++i) consistency.add(daily[i]);

    JsonArray weekly = doc["weeklyRetention"].to<JsonArray>();
    for (uint8_t i = 0; i < 8; ++i) {
        JsonObject item = weekly.add<JsonObject>();
        item["weekOffset"] = static_cast<int>(i) - 7;
        item["total"] = weeklyTotal[i];
        item["percent"] = weeklyTotal[i] == 0 ? 0.0f : 100.0f * weeklyCorrect[i] / weeklyTotal[i];
    }

    doc["maturity"]["new"] = maturityNew;
    doc["maturity"]["learning"] = maturityLearning;
    doc["maturity"]["young"] = maturityYoung;
    doc["maturity"]["mature"] = maturityMature;

    JsonArray future = doc["reviewForecast30d"].to<JsonArray>();
    for (uint8_t i = 0; i < 30; ++i) future.add(forecast[i]);

    JsonArray byDeck = doc["retentionByDeck"].to<JsonArray>();
    for (size_t i = 0; i < deckCount; ++i) {
        JsonObject item = byDeck.add<JsonObject>();
        item["deckId"] = decks[i].id;
        item["deckName"] = decks[i].name;
        item["total"] = decks[i].total;
        item["percent"] = decks[i].total == 0 ? 0.0f : 100.0f * decks[i].correct / decks[i].total;
    }

    JsonArray histogram = doc["difficultyHistogram"].to<JsonArray>();
    for (uint8_t i = 0; i < 10; ++i) histogram.add(difficultyBins[i]);

    // Índice composto opcional. Consistência = fração de dias com ao menos uma revisão.
    uint8_t activeDays = 0;
    for (uint8_t i = 0; i < 30; ++i) if (daily[i] > 0) ++activeDays;
    const float retention = scheduledTotal30 == 0 ? 0.0f : 100.0f * scheduledCorrect30 / scheduledTotal30;
    const float calibration = scheduledIncorrect30 == 0 ? 100.0f : 100.0f - (100.0f * overconfidentIncorrect30 / scheduledIncorrect30);
    const float consistencyScore = 100.0f * activeDays / 30.0f;
    doc["readinessIndex"] = (retention + calibration + consistencyScore) / 3.0f;

    String body;
    serializeJson(doc, body);
    return body;
}
