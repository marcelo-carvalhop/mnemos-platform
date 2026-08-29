#include "fsrs_replay_service.h"

#include <ArduinoJson.h>

#include "fsrs_engine.h"
#include "storage.h"

namespace {

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
            fsrs.phase = FsrsPhase::Review;
            break;

        case 3:
            fsrs.phase = FsrsPhase::Relearning;
            break;

        case 1:
        default:
            fsrs.phase = FsrsPhase::Learning;
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
}

}  // namespace


int FsrsReplayService::findState(
    CardState* states,
    size_t count,
    const String& cardId) {

    for (size_t i = 0; i < count; ++i) {
        if (states[i].id == cardId) {
            return static_cast<int>(i);
        }
    }

    return -1;
}


bool FsrsReplayService::rebuild(
    Storage& storage,
    CardState* states,
    size_t count) {

    // O estado antigo não é matematicamente convertível para FSRS.
    // Começamos do estado vazio e fazemos replay dos eventos.
    for (size_t i = 0; i < count; ++i) {
        states[i].fsrsDifficulty = 0.0;
        states[i].fsrsStabilityDays = 0.0;
        states[i].fsrsDueAtMs = 0;
        states[i].fsrsLastReviewAtMs = 0;
        states[i].fsrsRepetitions = 0;
        states[i].fsrsLapses = 0;
        states[i].fsrsPhase = 1;
        states[i].fsrsStep = 0;
        states[i].fsrsInitialized = false;
    }

    const String history =
        storage.reviewHistoryNdjson();

    int start = 0;
    uint32_t applied = 0;
    uint32_t ignored = 0;

    while (
        start <
        static_cast<int>(history.length())) {

        int end =
            history.indexOf('\n', start);

        if (end < 0) {
            end =
                static_cast<int>(
                    history.length());
        }

        const String line =
            history.substring(start, end);

        start = end + 1;

        if (line.length() == 0) {
            continue;
        }

        JsonDocument row;

        if (deserializeJson(row, line)) {
            ++ignored;
            continue;
        }

        // Eventos anteriores a v2 podem não possuir informação
        // suficiente para reconstrução determinística.
        if (
            String(row["schema"] | "") !=
            "mnemos.review/v2"
        ) {
            ++ignored;
            continue;
        }

        const bool affectsSchedule =
            row["affectsSchedule"] | false;

        if (!affectsSchedule) {
            continue;
        }

        const String cardId =
            row["cardId"] | "";

        const int index =
            findState(
                states,
                count,
                cardId);

        if (index < 0) {
            ++ignored;
            continue;
        }

        const uint8_t rating =
            row["schedulerRating"] | 0U;

        if (rating < 1 || rating > 4) {
            ++ignored;
            continue;
        }

        uint64_t reviewedAtMs = 0;

        // v2 local armazenava epoch em segundos.
        if (row["reviewedAtMs"].is<uint64_t>()) {
            reviewedAtMs =
                row["reviewedAtMs"]
                    .as<uint64_t>();
        } else if (
            row["reviewedAt"].is<uint64_t>()
        ) {
            reviewedAtMs =
                row["reviewedAt"]
                    .as<uint64_t>()
                * 1000ULL;
        }

        if (reviewedAtMs == 0) {
            ++ignored;
            continue;
        }

        CardState& state =
            states[index];

        FsrsState fsrs =
            fromCardState(state);

        fsrs =
            FsrsEngine::apply(
                fsrs,
                rating,
                reviewedAtMs);

        toCardState(
            fsrs,
            state);

        ++applied;
    }

    Serial.printf(
        "[fsrs] replay aplicado=%u ignorado=%u\n",
        static_cast<unsigned>(applied),
        static_cast<unsigned>(ignored));

    return true;
}
