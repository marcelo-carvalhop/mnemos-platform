#include "study_engine.h"

#include <algorithm>
#include <esp_system.h>
#include "config.h"
#include "fsrs_replay_service.h"
#include "fsrs_engine.h"
#include "storage.h"
#include "time_service.h"

namespace {

Rating ratingFor(Outcome outcome, Effort effort) {
    if (outcome != Outcome::Correct) {
        return Rating::Again;
    }

    switch (effort) {
        case Effort::Difficult:
            return Rating::Hard;

        case Effort::Easy:
            return Rating::Easy;

        case Effort::Normal:
        case Effort::None:
        default:
            return Rating::Good;
    }
}


FsrsState fsrsFromCardState(const CardState& state) {
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


void writeFsrsState(
    const FsrsState& fsrs,
    CardState& state,
    Rating rating,
    uint32_t reviewedAt) {

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
        static_cast<uint8_t>(fsrs.phase);

    state.fsrsStep =
        fsrs.step;

    state.fsrsInitialized =
        fsrs.initialized;


    // Espelho transitório para compatibilidade com código/local state
    // anterior à v0.6. Não é mais fonte do scheduler.
    state.difficulty =
        static_cast<float>(
            fsrs.difficulty);

    state.stabilityDays =
        static_cast<float>(
            fsrs.stability);

    state.dueAt =
        static_cast<uint32_t>(
            fsrs.dueAtMs / 1000ULL);

    state.lastReviewedAt =
        reviewedAt;

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

    state.lastRating =
        static_cast<uint8_t>(
            rating);
}


bool fsrsIsDue(
    const CardState& state,
    uint64_t nowMs) {

    if (!state.fsrsInitialized) {
        return true;
    }

    if (state.fsrsDueAtMs == 0) {
        return true;
    }

    return state.fsrsDueAtMs <= nowMs;
}

}  // namespace


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

    // O histórico é a fonte canônica do estado FSRS.
    FsrsReplayService::rebuild(
        storage_,
        states_,
        count_);

    storage_.saveStates(
        states_,
        count_);

    resumableSession_ = storage_.loadSession(
        cards_, count_, queue_, Config::SESSION_MAX_CARDS,
        sessionCount_, currentPosition_, mode_, stats_);
    resetCardInteraction();
}

uint16_t StudyEngine::dueCount() {
    const uint64_t nowMs =
        static_cast<uint64_t>(
            clock_.now()) * 1000ULL;

    uint16_t due = 0;

    for (size_t i = 0; i < count_; ++i) {
        if (fsrsIsDue(states_[i], nowMs)) {
            ++due;
        }
    }

    return due;
}

uint8_t StudyEngine::allowedNewCards(uint64_t nowMs) const {
    uint16_t forecast = 0;

    const uint64_t horizonMs =
        nowMs +
        7ULL * 86400000ULL;

    for (size_t i = 0; i < count_; ++i) {
        const CardState& state =
            states_[i];

        if (
            state.fsrsInitialized &&
            state.fsrsDueAtMs > nowMs &&
            state.fsrsDueAtMs <= horizonMs
        ) {
            ++forecast;
        }
    }

    if (
        forecast >=
        Config::FORECAST_LOAD_THRESHOLD_7D
    ) {
        return 1;
    }

    const uint16_t headroom =
        Config::FORECAST_LOAD_THRESHOLD_7D -
        forecast;

    const uint8_t scaled =
        static_cast<uint8_t>(
            std::max<uint16_t>(
                1U,
                headroom / 4U));

    return std::min<uint8_t>(
        Config::BASE_NEW_CARDS_PER_SESSION,
        scaled);
}

bool StudyEngine::appendCandidateWithInterleaving(const Candidate* candidates,
                                                   size_t candidateCount,
                                                   bool* used,
                                                   uint8_t& consecutiveSameDeck,
                                                   String& lastDeck) {
    int best = -1;
    for (size_t i = 0; i < candidateCount; ++i) {
        if (used[i]) continue;
        const String& deck = cards_[candidates[i].index].deckId;
        if (deck == lastDeck && consecutiveSameDeck >= Config::MAX_CONSECUTIVE_SAME_DECK) continue;
        best = static_cast<int>(i);
        break;
    }
    if (best < 0) {
        for (size_t i = 0; i < candidateCount; ++i) {
            if (!used[i]) { best = static_cast<int>(i); break; }
        }
    }
    if (best < 0) return false;

    used[best] = true;
    const uint8_t cardIndex = candidates[best].index;
    queue_[sessionCount_++] = cardIndex;
    const String deck = cards_[cardIndex].deckId;
    if (deck == lastDeck) {
        ++consecutiveSameDeck;
    } else {
        lastDeck = deck;
        consecutiveSameDeck = 1;
    }
    return true;
}

void StudyEngine::buildReviewQueue() {
    sessionCount_ = 0;
    const uint64_t nowMs =
        static_cast<uint64_t>(
            clock_.now()) * 1000ULL;

    Candidate candidates[Config::MAX_DEVICE_CARDS];
    size_t candidateCount = 0;
    uint8_t newSeen = 0;

    const uint8_t newLimit =
        allowedNewCards(nowMs);

    for (size_t i = 0; i < count_; ++i) {
        const bool isNew =
            !states_[i].fsrsInitialized;

        if (!fsrsIsDue(states_[i], nowMs)) {
            continue;
        }
        if (isNew && newSeen >= newLimit) continue;
        if (isNew) ++newSeen;
        Candidate c;
        c.index = static_cast<uint8_t>(i);
        c.isNew = isNew;
        c.illusion = states_[i].illusionOfMastery;
        c.dueAtMs = states_[i].fsrsDueAtMs;
        candidates[candidateCount++] = c;
    }

    // Prioridade: ilusão de domínio primeiro, depois cartões vencidos há mais tempo;
    // cartões novos entram por último dentro da cota calculada.
    std::sort(candidates, candidates + candidateCount,
              [](const Candidate& a, const Candidate& b) {
                  if (a.illusion != b.illusion) return a.illusion > b.illusion;
                  if (a.isNew != b.isNew) return a.isNew < b.isNew;
                  return a.dueAtMs < b.dueAtMs;
              });

    bool used[Config::MAX_DEVICE_CARDS] = {false};
    uint8_t consecutiveSameDeck = 0;
    String lastDeck;
    while (sessionCount_ < Config::SESSION_MAX_CARDS && sessionCount_ < candidateCount) {
        if (!appendCandidateWithInterleaving(candidates, candidateCount, used,
                                             consecutiveSameDeck, lastDeck)) break;
    }
}

bool StudyEngine::startReviewSession() {
    mode_ = SessionMode::Review;
    currentPosition_ = 0;
    stats_ = SessionStats{};
    stats_.mode = mode_;
    stats_.startedAtMs = millis();
    buildReviewQueue();
    resumableSession_ = sessionCount_ > 0;
    resetCardInteraction();
    if (resumableSession_) persistSession();
    else storage_.clearSession();
    return resumableSession_;
}

bool StudyEngine::startPracticeSession() {
    mode_ = SessionMode::Practice;
    currentPosition_ = 0;
    sessionCount_ = 0;
    stats_ = SessionStats{};
    stats_.mode = mode_;
    stats_.startedAtMs = millis();

    const size_t limit = std::min<size_t>(count_, Config::PRACTICE_CARD_LIMIT);
    for (size_t i = 0; i < limit; ++i) queue_[sessionCount_++] = static_cast<uint8_t>(i);

    resumableSession_ = sessionCount_ > 0;
    resetCardInteraction();
    if (resumableSession_) persistSession();
    else storage_.clearSession();
    return resumableSession_;
}

bool StudyEngine::resumeSession() {
    if (!resumableSession_ || sessionCount_ == 0 || currentPosition_ >= sessionCount_) return false;
    stats_.startedAtMs = millis();
    resetCardInteraction();
    return true;
}

void StudyEngine::resetCardInteraction() {
    confidence_ = Confidence::None;
    outcome_ = Outcome::Unknown;
    selectedOptionIndex_ = -1;
    responseTimeMs_ = 0;
    questionShownAtMs_ = millis();
}

void StudyEngine::persistSession() {
    if (!resumableSession_) return;
    storage_.saveSession(cards_, queue_, sessionCount_, currentPosition_, mode_, stats_);
}

const CardDefinition& StudyEngine::currentCard() const {
    return cards_[queue_[currentPosition_]];
}

const CardState& StudyEngine::currentState() const {
    return states_[queue_[currentPosition_]];
}

bool StudyEngine::selectOption(uint8_t index) {
    if (!currentIsObjective() || index >= currentCard().optionCount) return false;
    selectedOptionIndex_ = static_cast<int8_t>(index);
    markResponseReady();
    return true;
}

void StudyEngine::markResponseReady() {
    if (responseTimeMs_ == 0) responseTimeMs_ = millis() - questionShownAtMs_;
}

Outcome StudyEngine::evaluateAutomatic() {
    if (!currentIsObjective() || selectedOptionIndex_ < 0) return Outcome::Unknown;
    outcome_ = selectedOptionIndex_ == currentCard().correctOptionIndex
        ? Outcome::Correct : Outcome::Incorrect;
    return outcome_;
}

bool StudyEngine::commitCurrent(
    Outcome outcome,
    Effort effort) {

    if (outcome == Outcome::Unknown) {
        return false;
    }

    markResponseReady();

    const uint8_t stateIndex =
        queue_[currentPosition_];

    CardState& state =
        states_[stateIndex];

    const CardDefinition& card =
        cards_[stateIndex];

    const uint32_t reviewedAt =
        clock_.now();

    const uint64_t reviewedAtMs =
        static_cast<uint64_t>(
            reviewedAt) * 1000ULL;

    const Rating rating =
        ratingFor(
            outcome,
            effort);


    const FsrsState before =
        fsrsFromCardState(state);


    ReviewEvent event;

    event.id =
        String(reviewedAt)
        + "-"
        + String(millis())
        + "-"
        + String(
            esp_random(),
            HEX);

    event.cardId =
        card.id;

    event.deckId =
        card.deckId;

    event.cardType =
        card.type;

    event.reviewedAt =
        reviewedAt;

    event.reviewedAtMs =
        reviewedAtMs;

    event.responseTimeMs =
        responseTimeMs_;

    event.confidence =
        static_cast<uint8_t>(
            confidence_);

    event.outcome =
        outcome;

    event.effort =
        outcome == Outcome::Correct
            ? effort
            : Effort::None;

    event.schedulerRating =
        rating;

    event.sessionMode =
        mode_;

    event.affectsSchedule =
        mode_ != SessionMode::Practice;

    event.automaticEvaluation =
        currentIsObjective();

    event.selectedOptionIndex =
        selectedOptionIndex_;


    event.difficultyBefore =
        static_cast<float>(
            before.difficulty);

    event.stabilityBefore =
        static_cast<float>(
            before.stability);

    event.retrievabilityBefore =
        static_cast<float>(
            FsrsEngine::retrievability(
                before,
                reviewedAtMs));

    event.dueBeforeMs =
        before.dueAtMs;

    event.dueBefore =
        static_cast<uint32_t>(
            before.dueAtMs /
            1000ULL);


    if (event.affectsSchedule) {

        const FsrsState after =
            FsrsEngine::apply(
                before,
                static_cast<uint8_t>(
                    rating),
                reviewedAtMs,
                storage_.desiredRetention());

        writeFsrsState(
            after,
            state,
            rating,
            reviewedAt);
    }


    // Falsa confiança influencia a priorização da fila,
    // nunca a matemática do scheduler.
    state.illusionOfMastery =
        confidence_ ==
            Confidence::High
        &&
        outcome ==
            Outcome::Incorrect;


    const FsrsState after =
        fsrsFromCardState(state);

    event.difficultyAfter =
        static_cast<float>(
            after.difficulty);

    event.stabilityAfter =
        static_cast<float>(
            after.stability);

    event.dueAfterMs =
        after.dueAtMs;

    event.dueAfter =
        static_cast<uint32_t>(
            after.dueAtMs /
            1000ULL);


    storage_.appendReview(event);

    storage_.saveStates(
        states_,
        count_);

    clock_.checkpoint();


    ++stats_.reviewed;

    if (outcome == Outcome::Correct) {
        ++stats_.correct;
    } else {
        ++stats_.incorrect;
    }


    ++currentPosition_;

    if (
        currentPosition_ >=
        sessionCount_
    ) {

        stats_.endedAtMs =
            millis();

        resumableSession_ =
            false;

        storage_.clearSession();

        return true;
    }


    persistSession();

    resetCardInteraction();

    return false;
}

