#include "fsrs_engine.h"

#include <algorithm>
#include <cmath>

namespace {

constexpr double STABILITY_MIN = 0.001;
constexpr double MIN_DIFFICULTY = 1.0;
constexpr double MAX_DIFFICULTY = 10.0;

constexpr uint64_t DAY_MS = 86400000ULL;
constexpr uint64_t SECOND_MS = 1000ULL;

const double* weights() {
    return MnemosContract::FSRS_WEIGHTS;
}

static_assert(
    MnemosContract::FSRS_WEIGHT_COUNT == 21U,
    "Mnemos requires the 21-weight FSRS contract");

static_assert(
    !MnemosContract::ENABLE_FSRS_FUZZ,
    "Mnemos replay must remain deterministic");

}  // namespace


FsrsState FsrsEngine::fresh(uint64_t dueAtMs) {
    FsrsState state;
    state.dueAtMs = dueAtMs;
    return state;
}


double FsrsEngine::clampDifficulty(double value) {
    return std::max(
        MIN_DIFFICULTY,
        std::min(MAX_DIFFICULTY, value));
}


double FsrsEngine::clampStability(double value) {
    return std::max(STABILITY_MIN, value);
}


double FsrsEngine::initialStability(uint8_t rating) {
    return clampStability(
        weights()[rating - 1]);
}


double FsrsEngine::initialDifficulty(uint8_t rating) {
    const double value =
        weights()[4]
        - std::exp(
            weights()[5] *
            (static_cast<double>(rating) - 1.0))
        + 1.0;

    return clampDifficulty(value);
}


double FsrsEngine::shortTermStability(
    double stability,
    uint8_t rating) {

    double increase =
        std::exp(
            weights()[17] *
            (
                static_cast<double>(rating)
                - 3.0
                + weights()[18]
            )
        )
        *
        std::pow(
            stability,
            -weights()[19]);

    if (rating == 3 || rating == 4) {
        increase =
            std::max(increase, 1.0);
    }

    return clampStability(
        stability * increase);
}


double FsrsEngine::nextDifficulty(
    double difficulty,
    uint8_t rating) {

    const double initialEasy =
        initialDifficulty(4);

    const double delta =
        -(
            weights()[6] *
            (
                static_cast<double>(rating)
                - 3.0
            )
        );

    const double damped =
        difficulty
        +
        (
            (10.0 - difficulty)
            * delta
            / 9.0
        );

    const double value =
        weights()[7] * initialEasy
        +
        (1.0 - weights()[7]) * damped;

    return clampDifficulty(value);
}


double FsrsEngine::retrievability(
    const FsrsState& state,
    uint64_t nowMs) {

    if (
        !state.initialized ||
        state.lastReviewAtMs == 0 ||
        state.stability <= 0.0
    ) {
        return 0.0;
    }

    const uint64_t elapsedMs =
        nowMs > state.lastReviewAtMs
            ? nowMs - state.lastReviewAtMs
            : 0ULL;

    // O scheduler de referência usa dias inteiros.
    const double elapsedDays =
        static_cast<double>(
            elapsedMs / DAY_MS);

    const double decay =
        -weights()[20];

    const double factor =
        std::pow(
            0.9,
            1.0 / decay)
        - 1.0;

    return std::pow(
        1.0
        +
        factor
        *
        elapsedDays
        /
        state.stability,
        decay);
}


double FsrsEngine::nextForgetStability(
    double difficulty,
    double stability,
    double retrievabilityValue) {

    const double longTerm =
        weights()[11]
        *
        std::pow(
            difficulty,
            -weights()[12])
        *
        (
            std::pow(
                stability + 1.0,
                weights()[13])
            - 1.0
        )
        *
        std::exp(
            (1.0 - retrievabilityValue)
            * weights()[14]);

    const double shortTerm =
        stability
        /
        std::exp(
            weights()[17]
            * weights()[18]);

    return std::min(
        longTerm,
        shortTerm);
}


double FsrsEngine::nextRecallStability(
    double difficulty,
    double stability,
    double retrievabilityValue,
    uint8_t rating) {

    const double hardPenalty =
        rating == 2
            ? weights()[15]
            : 1.0;

    const double easyBonus =
        rating == 4
            ? weights()[16]
            : 1.0;

    return stability
        *
        (
            1.0
            +
            std::exp(weights()[8])
            *
            (11.0 - difficulty)
            *
            std::pow(
                stability,
                -weights()[9])
            *
            (
                std::exp(
                    (1.0 - retrievabilityValue)
                    * weights()[10])
                - 1.0
            )
            *
            hardPenalty
            *
            easyBonus
        );
}


double FsrsEngine::nextStability(
    double difficulty,
    double stability,
    double retrievabilityValue,
    uint8_t rating) {

    const double value =
        rating == 1
            ? nextForgetStability(
                difficulty,
                stability,
                retrievabilityValue)
            : nextRecallStability(
                difficulty,
                stability,
                retrievabilityValue,
                rating);

    return clampStability(value);
}


uint32_t FsrsEngine::nextIntervalDays(
    double stability,
    double desiredRetention) {

    const double decay =
        -weights()[20];

    const double factor =
        std::pow(
            0.9,
            1.0 / decay)
        - 1.0;

    const double raw =
        (stability / factor)
        *
        (
            std::pow(
                desiredRetention,
                1.0 / decay)
            - 1.0
        );

    long long interval =
        std::llround(raw);

    interval =
        std::max<long long>(
            1,
            interval);

    interval =
        std::min<long long>(
            MnemosContract::MAXIMUM_INTERVAL_DAYS,
            interval);

    return static_cast<uint32_t>(
        interval);
}


FsrsState FsrsEngine::apply(
    const FsrsState& input,
    uint8_t rating,
    uint64_t reviewedAtMs,
    double desiredRetention) {

    FsrsState state = input;

    if (rating < 1 || rating > 4) {
        rating = 3;
    }

    const FsrsPhase originalPhase =
        state.phase;

    const bool hadLastReview =
        state.initialized &&
        state.lastReviewAtMs != 0;

    const uint64_t elapsedMs =
        hadLastReview &&
        reviewedAtMs > state.lastReviewAtMs
            ? reviewedAtMs - state.lastReviewAtMs
            : 0ULL;

    const uint64_t elapsedDays =
        elapsedMs / DAY_MS;

    uint64_t intervalMs = 0;


    // ============================================================
    // LEARNING
    // ============================================================
    if (state.phase == FsrsPhase::Learning) {

        if (!state.initialized) {

            state.stability =
                initialStability(rating);

            state.difficulty =
                initialDifficulty(rating);

        } else if (
            hadLastReview &&
            elapsedDays < 1
        ) {

            state.stability =
                shortTermStability(
                    state.stability,
                    rating);

            state.difficulty =
                nextDifficulty(
                    state.difficulty,
                    rating);

        } else {

            const double r =
                retrievability(
                    state,
                    reviewedAtMs);

            state.stability =
                nextStability(
                    state.difficulty,
                    state.stability,
                    r,
                    rating);

            state.difficulty =
                nextDifficulty(
                    state.difficulty,
                    rating);
        }


        if (
            MnemosContract::LEARNING_STEP_COUNT == 0
            ||
            (
                state.step >=
                    static_cast<int8_t>(
                        MnemosContract::
                            LEARNING_STEP_COUNT)
                &&
                rating >= 2
            )
        ) {

            state.phase =
                FsrsPhase::Review;

            state.step = -1;

            intervalMs =
                static_cast<uint64_t>(
                    nextIntervalDays(
                        state.stability,
                        desiredRetention))
                *
                DAY_MS;

        } else if (rating == 1) {

            state.step = 0;

            intervalMs =
                static_cast<uint64_t>(
                    MnemosContract::
                        LEARNING_STEPS_SECONDS[0])
                *
                SECOND_MS;

        } else if (rating == 2) {

            if (
                state.step == 0 &&
                MnemosContract::
                    LEARNING_STEP_COUNT == 1
            ) {

                intervalMs =
                    static_cast<uint64_t>(
                        MnemosContract::
                            LEARNING_STEPS_SECONDS[0])
                    *
                    1500ULL;

            } else if (
                state.step == 0 &&
                MnemosContract::
                    LEARNING_STEP_COUNT >= 2
            ) {

                intervalMs =
                    static_cast<uint64_t>(
                        MnemosContract::
                            LEARNING_STEPS_SECONDS[0]
                        +
                        MnemosContract::
                            LEARNING_STEPS_SECONDS[1])
                    *
                    SECOND_MS
                    /
                    2ULL;

            } else {

                intervalMs =
                    static_cast<uint64_t>(
                        MnemosContract::
                            LEARNING_STEPS_SECONDS[
                                state.step])
                    *
                    SECOND_MS;
            }

        } else if (rating == 3) {

            if (
                state.step + 1 ==
                static_cast<int8_t>(
                    MnemosContract::
                        LEARNING_STEP_COUNT)
            ) {

                state.phase =
                    FsrsPhase::Review;

                state.step = -1;

                intervalMs =
                    static_cast<uint64_t>(
                        nextIntervalDays(
                            state.stability,
                            desiredRetention))
                    *
                    DAY_MS;

            } else {

                ++state.step;

                intervalMs =
                    static_cast<uint64_t>(
                        MnemosContract::
                            LEARNING_STEPS_SECONDS[
                                state.step])
                    *
                    SECOND_MS;
            }

        } else {

            state.phase =
                FsrsPhase::Review;

            state.step = -1;

            intervalMs =
                static_cast<uint64_t>(
                    nextIntervalDays(
                        state.stability,
                        desiredRetention))
                *
                DAY_MS;
        }


    // ============================================================
    // REVIEW
    // ============================================================
    } else if (
        state.phase == FsrsPhase::Review
    ) {

        const double r =
            retrievability(
                state,
                reviewedAtMs);

        if (
            hadLastReview &&
            elapsedDays < 1
        ) {

            state.stability =
                shortTermStability(
                    state.stability,
                    rating);

        } else {

            state.stability =
                nextStability(
                    state.difficulty,
                    state.stability,
                    r,
                    rating);
        }

        state.difficulty =
            nextDifficulty(
                state.difficulty,
                rating);


        if (
            rating == 1 &&
            MnemosContract::
                RELEARNING_STEP_COUNT > 0
        ) {

            state.phase =
                FsrsPhase::Relearning;

            state.step = 0;

            intervalMs =
                static_cast<uint64_t>(
                    MnemosContract::
                        RELEARNING_STEPS_SECONDS[0])
                *
                SECOND_MS;

        } else {

            intervalMs =
                static_cast<uint64_t>(
                    nextIntervalDays(
                        state.stability,
                        desiredRetention))
                *
                DAY_MS;
        }


    // ============================================================
    // RELEARNING
    // ============================================================
    } else {

        if (
            hadLastReview &&
            elapsedDays < 1
        ) {

            state.stability =
                shortTermStability(
                    state.stability,
                    rating);

            state.difficulty =
                nextDifficulty(
                    state.difficulty,
                    rating);

        } else {

            const double r =
                retrievability(
                    state,
                    reviewedAtMs);

            state.stability =
                nextStability(
                    state.difficulty,
                    state.stability,
                    r,
                    rating);

            state.difficulty =
                nextDifficulty(
                    state.difficulty,
                    rating);
        }


        if (
            MnemosContract::
                RELEARNING_STEP_COUNT == 0
            ||
            (
                state.step >=
                    static_cast<int8_t>(
                        MnemosContract::
                            RELEARNING_STEP_COUNT)
                &&
                rating >= 2
            )
        ) {

            state.phase =
                FsrsPhase::Review;

            state.step = -1;

            intervalMs =
                static_cast<uint64_t>(
                    nextIntervalDays(
                        state.stability,
                        desiredRetention))
                *
                DAY_MS;

        } else if (rating == 1) {

            state.step = 0;

            intervalMs =
                static_cast<uint64_t>(
                    MnemosContract::
                        RELEARNING_STEPS_SECONDS[0])
                *
                SECOND_MS;

        } else if (rating == 2) {

            if (
                state.step == 0 &&
                MnemosContract::
                    RELEARNING_STEP_COUNT == 1
            ) {

                intervalMs =
                    static_cast<uint64_t>(
                        MnemosContract::
                            RELEARNING_STEPS_SECONDS[0])
                    *
                    1500ULL;

            } else if (
                state.step == 0 &&
                MnemosContract::
                    RELEARNING_STEP_COUNT >= 2
            ) {

                intervalMs =
                    static_cast<uint64_t>(
                        MnemosContract::
                            RELEARNING_STEPS_SECONDS[0]
                        +
                        MnemosContract::
                            RELEARNING_STEPS_SECONDS[1])
                    *
                    SECOND_MS
                    /
                    2ULL;

            } else {

                intervalMs =
                    static_cast<uint64_t>(
                        MnemosContract::
                            RELEARNING_STEPS_SECONDS[
                                state.step])
                    *
                    SECOND_MS;
            }

        } else if (rating == 3) {

            if (
                state.step + 1 ==
                static_cast<int8_t>(
                    MnemosContract::
                        RELEARNING_STEP_COUNT)
            ) {

                state.phase =
                    FsrsPhase::Review;

                state.step = -1;

                intervalMs =
                    static_cast<uint64_t>(
                        nextIntervalDays(
                            state.stability,
                            desiredRetention))
                    *
                    DAY_MS;

            } else {

                ++state.step;

                intervalMs =
                    static_cast<uint64_t>(
                        MnemosContract::
                            RELEARNING_STEPS_SECONDS[
                                state.step])
                    *
                    SECOND_MS;
            }

        } else {

            state.phase =
                FsrsPhase::Review;

            state.step = -1;

            intervalMs =
                static_cast<uint64_t>(
                    nextIntervalDays(
                        state.stability,
                        desiredRetention))
                *
                DAY_MS;
        }
    }


    ++state.reps;

    if (
        rating == 1 &&
        originalPhase == FsrsPhase::Review
    ) {
        ++state.lapses;
    }

    state.initialized = true;

    state.lastReviewAtMs =
        reviewedAtMs;

    state.dueAtMs =
        reviewedAtMs +
        intervalMs;

    return state;
}
