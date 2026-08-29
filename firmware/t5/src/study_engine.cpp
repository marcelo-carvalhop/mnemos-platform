#include "study_engine.h"

#include <algorithm>
#include <esp_system.h>
#include "config.h"
#include "fsrs_replay_service.h"
#include "learning_model.h"
#include "storage.h"
#include "time_service.h"

StudyEngine::StudyEngine(CardDefinition* cards,
                         CardState* states,
                         size_t count,
                         Storage& storage,
                         TimeService& clock,
                         LearningModel& model)
    : cards_(cards),
      states_(states),
      count_(count),
      storage_(storage),
      clock_(clock),
      model_(model) {}

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
    const uint32_t nowEpoch = clock_.now();
    uint16_t due = 0;
    for (size_t i = 0; i < count_; ++i) {
        if (model_.isDue(states_[i], nowEpoch, Config::RETENTION_TARGET)) ++due;
    }
    return due;
}

uint8_t StudyEngine::allowedNewCards(uint32_t nowEpoch) const {
    uint16_t forecast = 0;
    const uint32_t horizon = nowEpoch + 7U * 86400U;
    for (size_t i = 0; i < count_; ++i) {
        if (states_[i].lastReviewedAt > 0 && states_[i].dueAt > nowEpoch && states_[i].dueAt <= horizon) ++forecast;
    }
    if (forecast >= Config::FORECAST_LOAD_THRESHOLD_7D) return 1;
    const uint16_t headroom = Config::FORECAST_LOAD_THRESHOLD_7D - forecast;
    const uint8_t scaled = static_cast<uint8_t>(std::max<uint16_t>(1U, headroom / 4U));
    return std::min<uint8_t>(Config::BASE_NEW_CARDS_PER_SESSION, scaled);
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
    const uint32_t nowEpoch = clock_.now();
    Candidate candidates[Config::MAX_DEVICE_CARDS];
    size_t candidateCount = 0;
    uint8_t newSeen = 0;
    const uint8_t newLimit = allowedNewCards(nowEpoch);

    for (size_t i = 0; i < count_; ++i) {
        const bool isNew = states_[i].lastReviewedAt == 0;
        if (!model_.isDue(states_[i], nowEpoch, Config::RETENTION_TARGET)) continue;
        if (isNew && newSeen >= newLimit) continue;
        if (isNew) ++newSeen;
        Candidate c;
        c.index = static_cast<uint8_t>(i);
        c.isNew = isNew;
        c.illusion = states_[i].illusionOfMastery;
        c.dueAt = states_[i].dueAt;
        candidates[candidateCount++] = c;
    }

    // Prioridade: ilusão de domínio primeiro, depois cartões vencidos há mais tempo;
    // cartões novos entram por último dentro da cota calculada.
    std::sort(candidates, candidates + candidateCount,
              [](const Candidate& a, const Candidate& b) {
                  if (a.illusion != b.illusion) return a.illusion > b.illusion;
                  if (a.isNew != b.isNew) return a.isNew < b.isNew;
                  return a.dueAt < b.dueAt;
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

bool StudyEngine::commitCurrent(Outcome outcome, Effort effort) {
    if (outcome == Outcome::Unknown) return false;
    markResponseReady();

    const uint8_t stateIndex = queue_[currentPosition_];
    CardState& state = states_[stateIndex];
    const CardDefinition& card = cards_[stateIndex];
    const uint32_t reviewedAt = clock_.now();
    const Rating rating = model_.ratingFor(outcome, effort);

    ReviewEvent event;
    event.id = String(reviewedAt) + "-" + String(millis()) + "-" + String(esp_random(), HEX);
    event.cardId = card.id;
    event.deckId = card.deckId;
    event.cardType = card.type;
    event.reviewedAt = reviewedAt;
    event.responseTimeMs = responseTimeMs_;
    event.confidence = static_cast<uint8_t>(confidence_);
    event.outcome = outcome;
    event.effort = outcome == Outcome::Correct ? effort : Effort::None;
    event.schedulerRating = rating;
    event.sessionMode = mode_;
    event.affectsSchedule = mode_ != SessionMode::Practice;
    event.automaticEvaluation = currentIsObjective();
    event.selectedOptionIndex = selectedOptionIndex_;
    event.difficultyBefore = state.difficulty;
    event.stabilityBefore = state.stabilityDays;
    event.retrievabilityBefore = model_.retrievability(state, reviewedAt);
    event.dueBefore = state.dueAt;

    if (event.affectsSchedule) {
        model_.apply(state, rating, mode_, reviewedAt, Config::RETENTION_TARGET);
    }

    // A falsa confiança é evidência de fila, não uma alteração do scheduler D/S/R.
    state.illusionOfMastery = (confidence_ == Confidence::High && outcome == Outcome::Incorrect);

    event.difficultyAfter = state.difficulty;
    event.stabilityAfter = state.stabilityDays;
    event.dueAfter = state.dueAt;


    storage_.appendReview(event);
    storage_.saveStates(states_, count_);
    clock_.checkpoint();

    ++stats_.reviewed;
    if (outcome == Outcome::Correct) ++stats_.correct;
    else ++stats_.incorrect;

    ++currentPosition_;
    if (currentPosition_ >= sessionCount_) {
        stats_.endedAtMs = millis();
        resumableSession_ = false;
        storage_.clearSession();
        return true;
    }

    persistSession();
    resetCardInteraction();
    return false;
}
