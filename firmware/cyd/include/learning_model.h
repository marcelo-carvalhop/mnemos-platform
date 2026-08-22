#pragma once

#include <Arduino.h>
#include "models.h"

class LearningModel {
public:
    float retrievability(const CardState& state, uint32_t nowEpoch) const;
    bool isDue(const CardState& state, uint32_t nowEpoch, float retentionTarget) const;
    Rating ratingFor(Outcome outcome, Effort effort) const;
    uint32_t apply(CardState& state,
                   Rating rating,
                   SessionMode mode,
                   uint32_t reviewedAt,
                   float retentionTarget) const;

private:
    float initialDifficulty(Rating rating) const;
    float initialStability(Rating rating) const;
    float updatedDifficulty(float current, Rating rating) const;
    float successfulStability(float currentS, float difficulty, float retrievability) const;
    float failedStability(float currentS, float difficulty, float retrievability) const;
    uint32_t intervalSeconds(float stabilityDays, float retentionTarget, Rating rating) const;
};
