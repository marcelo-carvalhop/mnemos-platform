#include "fsrs_replay_service.h"

#include <ArduinoJson.h>
#include <algorithm>
#include <vector>

#include "fsrs_engine.h"
#include "storage.h"

namespace {

struct ReplayEvent {
    uint64_t reviewedAtMs = 0;
    uint8_t rating = 0;
    String id;
};


FsrsState fromCardState(
    const CardState& state) {

    FsrsState fsrs;

    fsrs.stability =
        state.fsrsStabilityDays;

    fsrs.difficulty =
        state.fsrsDifficulty;

    fsrs.dueAtMs =
        state.fsrsDueAtMs;

    fsrs.lastReviewAtMs =
        state.fsrsLastReviewAtMs;

    fsrs.reps =
        state.fsrsRepetitions;

    fsrs.lapses =
        state.fsrsLapses;

    switch (state.fsrsPhase) {
        case 2:
            fsrs.phase =
                FsrsPhase::Review;
            break;

        case 3:
            fsrs.phase =
                FsrsPhase::Relearning;
            break;

        default:
            fsrs.phase =
                FsrsPhase::Learning;
            break;
    }

    fsrs.step =
        state.fsrsStep;

    fsrs.initialized =
        state.fsrsInitialized;

    return fsrs;
}


void toCardState(
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


    // Espelho legado: não participa mais do cálculo.
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


bool eventLess(
    const ReplayEvent& a,
    const ReplayEvent& b) {

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

}  // namespace


bool FsrsReplayService::rebuild(
    Storage& storage,
    CardState* states,
    size_t count) {

    const String history =
        storage.reviewHistoryNdjson();

    uint32_t applied = 0;


    for (
        size_t cardIndex = 0;
        cardIndex < count;
        ++cardIndex
    ) {
        CardState& state =
            states[cardIndex];

        // Estado FSRS é sempre reconstruído da verdade histórica.
        state.fsrsDifficulty = 0.0;
        state.fsrsStabilityDays = 0.0;
        state.fsrsDueAtMs = 0;
        state.fsrsLastReviewAtMs = 0;
        state.fsrsRepetitions = 0;
        state.fsrsLapses = 0;
        state.fsrsPhase = 1;
        state.fsrsStep = 0;
        state.fsrsInitialized = false;


        std::vector<ReplayEvent> events;

        int start = 0;

        while (
            start <
            static_cast<int>(
                history.length())
        ) {
            int end =
                history.indexOf(
                    '\n',
                    start);

            if (end < 0) {
                end =
                    static_cast<int>(
                        history.length());
            }

            const String line =
                history.substring(
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
                !(row["affectsSchedule"] | false)
            ) {
                continue;
            }

            if (
                String(row["cardId"] | "") !=
                state.id
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

            ReplayEvent event;

            event.reviewedAtMs =
                reviewedAtMs;

            event.rating =
                rating;

            event.id =
                row["id"] | "";

            events.push_back(event);
        }


        std::sort(
            events.begin(),
            events.end(),
            eventLess);


        FsrsState fsrs =
            FsrsEngine::fresh();


        for (
            const ReplayEvent& event :
            events
        ) {
            fsrs =
                FsrsEngine::apply(
                    fsrs,
                    event.rating,
                    event.reviewedAtMs);

            ++applied;
        }


        toCardState(
            fsrs,
            state);
    }


    Serial.printf(
        "[fsrs] replay ordenado aplicado=%u\n",
        static_cast<unsigned>(
            applied));

    return true;
}
