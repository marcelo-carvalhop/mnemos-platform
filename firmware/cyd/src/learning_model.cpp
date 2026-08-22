#include "learning_model.h"

#include <algorithm>
#include <cmath>
#include "config.h"

namespace {
float clampf(float value, float low, float high) {
    return std::max(low, std::min(high, value));
}
}

float LearningModel::retrievability(const CardState& state, uint32_t nowEpoch) const {
    if (state.stabilityDays <= 0.0f || state.lastReviewedAt == 0) return 0.0f;
    const uint32_t elapsedSeconds = nowEpoch > state.lastReviewedAt ? nowEpoch - state.lastReviewedAt : 0U;
    const float elapsedDays = static_cast<float>(elapsedSeconds) / 86400.0f;
    return 1.0f / (1.0f + elapsedDays / (9.0f * state.stabilityDays));
}

bool LearningModel::isDue(const CardState& state, uint32_t nowEpoch, float retentionTarget) const {
    (void)retentionTarget;
    // dueAt e a fonte de verdade do agendamento. Isso preserva a regra de que
    // mudancas futuras de meta de retencao nao recalculam cards retroativamente
    // e evita tratar um primeiro erro como imediatamente vencido depois de ele
    // receber um intervalo curto de reaprendizado.
    if (state.dueAt == 0) return true;
    return state.dueAt <= nowEpoch;
}

Rating LearningModel::ratingFor(Outcome outcome, Effort effort) const {
    if (outcome != Outcome::Correct) return Rating::Again;
    switch (effort) {
        case Effort::Difficult: return Rating::Hard;
        case Effort::Easy: return Rating::Easy;
        case Effort::Normal:
        case Effort::None:
        default: return Rating::Good;
    }
}

float LearningModel::initialDifficulty(Rating rating) const {
    switch (rating) {
        case Rating::Again: return 7.0f;
        case Rating::Hard: return 6.0f;
        case Rating::Good: return 5.0f;
        case Rating::Easy: return 4.0f;
    }
    return 5.0f;
}

float LearningModel::initialStability(Rating rating) const {
    switch (rating) {
        case Rating::Again: return 0.10f;
        case Rating::Hard: return 0.50f;
        case Rating::Good: return 1.00f;
        case Rating::Easy: return 3.00f;
    }
    return 1.00f;
}

float LearningModel::updatedDifficulty(float current, Rating rating) const {
    float delta = 0.0f;
    switch (rating) {
        case Rating::Again: delta = 0.80f; break;
        case Rating::Hard: delta = 0.30f; break;
        case Rating::Good: delta = -0.05f; break;
        case Rating::Easy: delta = -0.40f; break;
    }
    return clampf(current + delta, Config::MIN_DIFFICULTY, Config::MAX_DIFFICULTY);
}

float LearningModel::successfulStability(float currentS, float difficulty, float retrievability) const {
    const float s = clampf(currentS, Config::MIN_STABILITY_DAYS, Config::MAX_STABILITY_DAYS);
    const float r = clampf(retrievability, 0.0f, 1.0f);
    const float gain = std::exp(Config::DSR_W1) *
                       (11.0f - difficulty) *
                       std::pow(s, -Config::DSR_W2) *
                       (std::exp(Config::DSR_W3 * (1.0f - r)) - 1.0f);
    return clampf(s * (1.0f + std::max(0.02f, gain)),
                  Config::MIN_STABILITY_DAYS, Config::MAX_STABILITY_DAYS);
}

float LearningModel::failedStability(float currentS, float difficulty, float retrievability) const {
    const float s = clampf(currentS, Config::MIN_STABILITY_DAYS, Config::MAX_STABILITY_DAYS);
    const float d = clampf(difficulty, Config::MIN_DIFFICULTY, Config::MAX_DIFFICULTY);
    const float r = clampf(retrievability, 0.0f, 1.0f);
    const float next = Config::DSR_W4 *
                       std::pow(d, -Config::DSR_W5) *
                       (std::pow(s + 1.0f, Config::DSR_W6) - 1.0f) *
                       std::exp(Config::DSR_W7 * (1.0f - r));
    return clampf(next, Config::MIN_STABILITY_DAYS, std::max(Config::MIN_STABILITY_DAYS, s));
}

uint32_t LearningModel::intervalSeconds(float stabilityDays, float retentionTarget, Rating rating) const {
    if (Config::DEMO_INTERVALS) {
        switch (rating) {
            case Rating::Again: return 30U;
            case Rating::Hard: return 120U;
            case Rating::Good: return 300U;
            case Rating::Easy: return 600U;
        }
    }

    const float target = clampf(retentionTarget, 0.80f, 0.95f);
    const float days = 9.0f * stabilityDays * (1.0f / target - 1.0f);
    const float bounded = clampf(days, 10.0f / 1440.0f, Config::MAX_STABILITY_DAYS);
    return static_cast<uint32_t>(bounded * 86400.0f + 0.5f);
}

uint32_t LearningModel::apply(CardState& state,
                              Rating rating,
                              SessionMode mode,
                              uint32_t reviewedAt,
                              float retentionTarget) const {
    if (mode == SessionMode::Practice) return 0U;

    const bool first = state.lastReviewedAt == 0 || state.stabilityDays <= 0.0f;
    const float r = first ? 0.0f : retrievability(state, reviewedAt);
    float nextS = first ? initialStability(rating) : state.stabilityDays;
    float nextD = first ? initialDifficulty(rating) : updatedDifficulty(state.difficulty, rating);

    if (!first) {
        if (rating == Rating::Again) {
            nextS = failedStability(state.stabilityDays, nextD, r);
        } else {
            const float full = successfulStability(state.stabilityDays, nextD, r);
            if (mode == SessionMode::Cram) {
                nextS = state.stabilityDays + (full - state.stabilityDays) * Config::CRAM_GAIN_FACTOR;
            } else {
                nextS = full;
            }
        }
    }

    state.difficulty = clampf(nextD, Config::MIN_DIFFICULTY, Config::MAX_DIFFICULTY);
    state.stabilityDays = clampf(nextS, Config::MIN_STABILITY_DAYS, Config::MAX_STABILITY_DAYS);
    state.lastReviewedAt = reviewedAt;
    state.lastRating = static_cast<uint8_t>(rating);

    if (rating == Rating::Again) {
        ++state.lapses;
    } else {
        ++state.repetitions;
    }

    uint32_t interval = intervalSeconds(state.stabilityDays, retentionTarget, rating);
    if (mode == SessionMode::Cram) {
        const uint32_t maxSeconds = static_cast<uint32_t>(Config::CRAM_RECONSOLIDATION_MAX_DAYS * 86400.0f);
        interval = std::min(interval, maxSeconds);
    }
    state.dueAt = reviewedAt + interval;
    return interval;
}
