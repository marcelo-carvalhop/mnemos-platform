#include "study_engine.h"

#include <algorithm>
#include <esp_system.h>
#include "config.h"
#include "storage.h"
#include "time_service.h"

StudyEngine::StudyEngine(CardDefinition* cards,
                         CardState* states,
                         size_t count,
                         Storage& storage,
                         TimeService& clock)
    : cards_(cards),
      states_(states),
      count_(count),
      storage_(storage),
      clock_(clock) {}

void StudyEngine::initializeStates() {
    for (size_t i = 0; i < count_; ++i) {
        if (states_[i].id.length() == 0) states_[i].id = cards_[i].id;
    }
    storage_.loadStates(states_, count_);
}

uint16_t StudyEngine::dueCount() {
    const uint32_t current = clock_.now();
    uint16_t due = 0;
    for (size_t i = 0; i < count_; ++i) {
        if (states_[i].dueAt == 0 || states_[i].dueAt <= current) ++due;
    }
    return due;
}

bool StudyEngine::startSession() {
    sessionCount_ = 0;
    currentPosition_ = 0;
    confidence_ = Confidence::None;
    responseTimeMs_ = 0;
    stats_ = SessionStats{};
    stats_.startedAtMs = millis();

    const uint32_t current = clock_.now();
    for (size_t i = 0; i < count_ && sessionCount_ < Config::SESSION_MAX_CARDS; ++i) {
        if (states_[i].dueAt == 0 || states_[i].dueAt <= current) {
            queue_[sessionCount_++] = static_cast<uint8_t>(i);
        }
    }

    if (sessionCount_ == 0) {
        const size_t practice = std::min<size_t>(count_, Config::PRACTICE_CARD_LIMIT);
        for (size_t i = 0; i < practice; ++i) {
            queue_[sessionCount_++] = static_cast<uint8_t>(i);
        }
    }

    questionShownAtMs_ = millis();
    return sessionCount_ > 0;
}

const CardDefinition& StudyEngine::currentCard() const {
    return cards_[queue_[currentPosition_]];
}

const CardState& StudyEngine::currentState() const {
    return states_[queue_[currentPosition_]];
}

void StudyEngine::setConfidence(Confidence confidence) {
    confidence_ = confidence;
}

void StudyEngine::revealCurrent() {
    if (!canReveal()) return;
    responseTimeMs_ = millis() - questionShownAtMs_;
}

uint32_t StudyEngine::intervalFor(Rating rating, const CardState& state) const {
    if (Config::DEMO_INTERVALS) {
        switch (rating) {
            case Rating::Again: return 30U;
            case Rating::Hard: return 120U;
            case Rating::Good: return 300U;
            case Rating::Easy: return 600U;
        }
    }

    constexpr uint32_t MINUTE = 60U;
    constexpr uint32_t DAY = 86400U;

    switch (rating) {
        case Rating::Again:
            return 10U * MINUTE;
        case Rating::Hard:
            return state.intervalSeconds == 0
                ? DAY
                : std::max<uint32_t>(DAY, state.intervalSeconds * 12U / 10U);
        case Rating::Good:
            return state.intervalSeconds == 0
                ? 3U * DAY
                : std::max<uint32_t>(3U * DAY, state.intervalSeconds * 2U);
        case Rating::Easy:
            return state.intervalSeconds == 0
                ? 7U * DAY
                : std::max<uint32_t>(7U * DAY, state.intervalSeconds * 3U);
    }
    return DAY;
}

bool StudyEngine::rateCurrent(Rating rating) {
    const uint8_t stateIndex = queue_[currentPosition_];
    CardState& state = states_[stateIndex];

    const uint32_t previousInterval = state.intervalSeconds;
    const uint32_t newInterval = intervalFor(rating, state);
    const uint32_t reviewedAt = clock_.now();

    state.intervalSeconds = newInterval;
    state.dueAt = reviewedAt + newInterval;
    state.lastRating = static_cast<uint8_t>(rating);

    if (rating == Rating::Again) {
        state.repetitions = 0;
        ++state.lapses;
    } else {
        ++state.repetitions;
    }

    ReviewEvent event;
    event.id = String(reviewedAt) + "-" + String(millis()) + "-" + String(esp_random(), HEX);
    event.cardId = state.id;
    event.reviewedAt = reviewedAt;
    event.responseTimeMs = responseTimeMs_;
    event.intervalBefore = previousInterval;
    event.intervalAfter = newInterval;
    event.confidence = static_cast<uint8_t>(confidence_);
    event.rating = static_cast<uint8_t>(rating);

    storage_.appendReview(event);
    storage_.saveStates(states_, count_);
    clock_.checkpoint();

    ++stats_.reviewed;
    const uint8_t ratingIndex = static_cast<uint8_t>(rating) - 1U;
    if (ratingIndex < 4) ++stats_.ratingCounts[ratingIndex];

    ++currentPosition_;
    if (currentPosition_ >= sessionCount_) {
        stats_.endedAtMs = millis();
        return true;
    }

    confidence_ = Confidence::None;
    responseTimeMs_ = 0;
    questionShownAtMs_ = millis();
    return false;
}
