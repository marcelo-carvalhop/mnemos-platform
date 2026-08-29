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
    bool startReviewSession();
    bool startPracticeSession();
    bool resumeSession();
    bool hasResumableSession() const { return resumableSession_; }

    const CardDefinition& currentCard() const;
    const CardState& currentState() const;
    uint8_t currentPosition() const { return currentPosition_; }
    uint8_t sessionCount() const { return sessionCount_; }
    SessionMode mode() const { return mode_; }
    const SessionStats& stats() const { return stats_; }

    bool currentIsObjective() const { return currentCard().isObjective(); }
    bool selectOption(uint8_t index);
    int8_t selectedOptionIndex() const { return selectedOptionIndex_; }

    void setConfidence(Confidence confidence) { confidence_ = confidence; }
    Confidence confidence() const { return confidence_; }

    void markResponseReady();
    Outcome evaluateAutomatic();
    Outcome outcome() const { return outcome_; }

    bool commitCurrent(Outcome outcome, Effort effort);

private:
    struct Candidate {
        uint8_t index = 0;
        bool isNew = false;
        bool illusion = false;
        uint64_t dueAtMs = 0;
    };

    CardDefinition* cards_;
    CardState* states_;
    size_t count_;
    Storage& storage_;
    TimeService& clock_;

    uint8_t queue_[Config::MAX_DEVICE_CARDS] = {0};
    uint8_t sessionCount_ = 0;
    uint8_t currentPosition_ = 0;
    SessionMode mode_ = SessionMode::Review;
    Confidence confidence_ = Confidence::None;
    Outcome outcome_ = Outcome::Unknown;
    int8_t selectedOptionIndex_ = -1;
    uint32_t questionShownAtMs_ = 0;
    uint32_t responseTimeMs_ = 0;
    SessionStats stats_{};
    bool resumableSession_ = false;

    void resetCardInteraction();
    void persistSession();
    uint8_t allowedNewCards(uint64_t nowMs) const;
    bool appendCandidateWithInterleaving(const Candidate* candidates,
                                         size_t candidateCount,
                                         bool* used,
                                         uint8_t& consecutiveSameDeck,
                                         String& lastDeck);
    void buildReviewQueue();
};
