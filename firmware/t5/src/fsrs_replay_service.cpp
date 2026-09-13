#include "fsrs_replay_service.h"

#include <ArduinoJson.h>
#include <algorithm>
#include <vector>

#include "fsrs_engine.h"
#include "storage.h"

namespace {

struct ReplayReview {
    uint64_t reviewedAtMs = 0;
    String id;
    uint8_t rating = 0;
};


void writeState(
    const FsrsState& fsrs,
    CardState& state) {

    state.fsrsStabilityDays =
        fsrs.stability;

    state.fsrsDifficulty =
        fsrs.difficulty;

    state.fsrsDueAtMs =
        fsrs.dueAtMs;

    state.fsrsLastReviewAtMs =
        fsrs.lastReviewAtMs;

    state.fsrsRepetitions =
        fsrs.reps;

    state.fsrsLapses =
        fsrs.lapses;

    state.fsrsPhase =
        static_cast<uint8_t>(
            fsrs.phase);

    state.fsrsStep =
        fsrs.step;

    state.fsrsInitialized =
        fsrs.initialized;


    // Espelho legado: compatibilidade apenas.
    state.difficulty =
        static_cast<float>(
            fsrs.difficulty);

    state.stabilityDays =
        static_cast<float>(
            fsrs.stability);

    state.dueAt =
        static_cast<uint32_t>(
            fsrs.dueAtMs /
            1000ULL);

    state.lastReviewedAt =
        static_cast<uint32_t>(
            fsrs.lastReviewAtMs /
            1000ULL);

    state.repetitions =
        static_cast<uint16_t>(
            std::min<uint32_t>(
                fsrs.reps,
                65535U));

    state.lapses =
        static_cast<uint16_t>(
            std::min<uint32_t>(
                fsrs.lapses,
                65535U));
}


bool reviewLess(
    const ReplayReview& a,
    const ReplayReview& b) {

    if (
        a.reviewedAtMs !=
        b.reviewedAtMs
    ) {
        return
            a.reviewedAtMs <
            b.reviewedAtMs;
    }

    return
        a.id.compareTo(b.id) < 0;
}


uint64_t latestResetForCard(
    const String& resetHistory,
    const String& cardId) {

    uint64_t cutoffMs = 0;

    int start = 0;

    while (
        start <
        static_cast<int>(
            resetHistory.length())
    ) {
        int end =
            resetHistory.indexOf(
                '\n',
                start);

        if (end < 0) {
            end =
                static_cast<int>(
                    resetHistory.length());
        }

        const String line =
            resetHistory.substring(
                start,
                end);

        start = end + 1;

        if (line.length() == 0) {
            continue;
        }

        JsonDocument row;

        if (deserializeJson(row, line)) {
            continue;
        }

        if (
            String(row["schema"] | "") !=
            "mnemos.progress-reset/v2"
        ) {
            continue;
        }

        if (
            String(row["cardId"] | "") !=
            cardId
        ) {
            continue;
        }

        if (
            !row["resetAtMs"]
                .is<uint64_t>()
        ) {
            continue;
        }

        const uint64_t resetAtMs =
            row["resetAtMs"]
                .as<uint64_t>();

        if (resetAtMs > cutoffMs) {
            cutoffMs =
                resetAtMs;
        }
    }

    return cutoffMs;
}


void collectReviews(
    const String& reviewHistory,
    const String& cardId,
    uint64_t cutoffMs,
    std::vector<ReplayReview>& reviews) {

    int start = 0;

    while (
        start <
        static_cast<int>(
            reviewHistory.length())
    ) {
        int end =
            reviewHistory.indexOf(
                '\n',
                start);

        if (end < 0) {
            end =
                static_cast<int>(
                    reviewHistory.length());
        }

        const String line =
            reviewHistory.substring(
                start,
                end);

        start = end + 1;

        if (line.length() == 0) {
            continue;
        }

        JsonDocument row;

        if (deserializeJson(row, line)) {
            continue;
        }

        if (
            String(row["schema"] | "") !=
            "mnemos.review/v2"
        ) {
            continue;
        }

        if (
            String(row["cardId"] | "") !=
            cardId
        ) {
            continue;
        }

        if (
            !(row["affectsSchedule"] | true)
        ) {
            continue;
        }

        const uint8_t rating =
            row["schedulerRating"] | 0U;

        if (
            rating < 1 ||
            rating > 4
        ) {
            continue;
        }

        uint64_t reviewedAtMs = 0;

        if (
            row["reviewedAtMs"]
                .is<uint64_t>()
        ) {
            reviewedAtMs =
                row["reviewedAtMs"]
                    .as<uint64_t>();

        } else if (
            row["reviewedAt"]
                .is<uint32_t>()
        ) {
            reviewedAtMs =
                static_cast<uint64_t>(
                    row["reviewedAt"]
                        .as<uint32_t>())
                *
                1000ULL;
        }

        if (reviewedAtMs == 0) {
            continue;
        }

        // Mesma regra do Web:
        // revisões no mesmo instante do reset também
        // pertencem ao estado anterior ao reset.
        if (
            cutoffMs > 0 &&
            reviewedAtMs <= cutoffMs
        ) {
            continue;
        }

        ReplayReview review;

        review.reviewedAtMs =
            reviewedAtMs;

        review.id =
            row["id"] | "";

        review.rating =
            rating;

        reviews.push_back(review);
    }
}

}  // namespace


bool FsrsReplayService::rebuild(
    Storage& storage,
    CardState* states,
    size_t count) {

    const String reviewHistory =
        storage.reviewHistoryNdjson();

    const String resetHistory =
        storage.progressResetHistoryNdjson();

    uint32_t appliedReviews = 0;
    uint32_t appliedResets = 0;

    const double desiredRetention =
        storage.desiredRetention();


    for (
        size_t cardIndex = 0;
        cardIndex < count;
        ++cardIndex
    ) {
        CardState& state =
            states[cardIndex];

        const uint64_t cutoffMs =
            latestResetForCard(
                resetHistory,
                state.id);

        if (cutoffMs > 0) {
            ++appliedResets;
        }

        std::vector<ReplayReview> reviews;

        collectReviews(
            reviewHistory,
            state.id,
            cutoffMs,
            reviews);

        std::sort(
            reviews.begin(),
            reviews.end(),
            reviewLess);


        FsrsState fsrs =
            FsrsEngine::fresh();


        for (
            const ReplayReview& review :
            reviews
        ) {
            fsrs =
                FsrsEngine::apply(
                    fsrs,
                    review.rating,
                    review.reviewedAtMs,
                    desiredRetention);

            ++appliedReviews;
        }


        writeState(
            fsrs,
            state);
    }


    Serial.printf(
        "[fsrs] replay reviews=%u reset_cards=%u retention=%.4f\n",
        static_cast<unsigned>(
            appliedReviews),
        static_cast<unsigned>(
            appliedResets),
        desiredRetention);

    return true;
}
