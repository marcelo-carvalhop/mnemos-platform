#pragma once

#include <stdint.h>

#include "mnemos_contract_generated.h"

enum class FsrsPhase : uint8_t {
    Learning = 1,
    Review = 2,
    Relearning = 3,
};

struct FsrsState {
    double stability = 0.0;
    double difficulty = 0.0;

    uint64_t dueAtMs = 0;
    uint64_t lastReviewAtMs = 0;

    uint32_t reps = 0;
    uint32_t lapses = 0;

    FsrsPhase phase = FsrsPhase::Learning;

    // -1 equivale a null no estado Review.
    int8_t step = 0;

    // Distingue cartão novo de um cartão Learning já revisado.
    bool initialized = false;
};

class FsrsEngine {
public:
    static FsrsState fresh(uint64_t dueAtMs = 0);

    static double retrievability(
        const FsrsState& state,
        uint64_t nowMs);

    static FsrsState apply(
        const FsrsState& state,
        uint8_t rating,
        uint64_t reviewedAtMs,
        double desiredRetention =
            MnemosContract::DESIRED_RETENTION);

private:
    static double clampDifficulty(double value);
    static double clampStability(double value);

    static double initialStability(uint8_t rating);
    static double initialDifficulty(uint8_t rating);

    static double shortTermStability(
        double stability,
        uint8_t rating);

    static double nextDifficulty(
        double difficulty,
        uint8_t rating);

    static double nextStability(
        double difficulty,
        double stability,
        double retrievability,
        uint8_t rating);

    static double nextForgetStability(
        double difficulty,
        double stability,
        double retrievability);

    static double nextRecallStability(
        double difficulty,
        double stability,
        double retrievability,
        uint8_t rating);

    static uint32_t nextIntervalDays(
        double stability,
        double desiredRetention);
};
