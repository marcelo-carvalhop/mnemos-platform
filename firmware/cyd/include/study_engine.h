#pragma once

#include <cstddef>
#include "models.h"

class Storage;
class TimeService;

class StudyEngine {
public:
    StudyEngine(CardDefinition* cards,
                CardState* states,
                size_t count,
                Storage& storage,
                TimeService& clock);

    void initializeStates();
    uint16_t dueCount();
    bool startSession();

    const CardDefinition& currentCard() const;
    const CardState& currentState() const;
    uint8_t currentPosition() const { return currentPosition_; }
    uint8_t sessionCount() const { return sessionCount_; }

    void setConfidence(Confidence confidence);
    Confidence confidence() const { return confidence_; }
    bool canReveal() const { return confidence_ != Confidence::None; }
    void revealCurrent();
    bool rateCurrent(Rating rating);

    const SessionStats& stats() const { return stats_; }

private:
    uint32_t intervalFor(Rating rating, const CardState& state) const;

    CardDefinition* cards_;
    CardState* states_;
    size_t count_;
    Storage& storage_;
    TimeService& clock_;

    uint8_t queue_[48] = {0};
    uint8_t sessionCount_ = 0;
    uint8_t currentPosition_ = 0;
    Confidence confidence_ = Confidence::None;
    uint32_t questionShownAtMs_ = 0;
    uint32_t responseTimeMs_ = 0;
    SessionStats stats_{};
};
