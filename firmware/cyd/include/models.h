#pragma once

#include <Arduino.h>
#include "config.h"

struct CardDefinition {
    String id;
    String deckId;
    String deck;
    String type = "open_recall";   // open_recall | cloze | multiple_choice | true_false | application
    String format = "plain";
    String question;
    String answer;
    String options[Config::MAX_CARD_OPTIONS];
    uint8_t optionCount = 0;
    int8_t correctOptionIndex = -1;
    uint64_t revision = 1;

    bool isObjective() const {
        return type == "multiple_choice" || type == "true_false";
    }

    bool isSelfAssessed() const {
        return !isObjective();
    }
};

struct CardState {
    String id;
    float difficulty = 5.0f;       // D em [1,10]
    float stabilityDays = 0.0f;    // S em dias; 0 = cartão novo
    uint32_t dueAt = 0;
    uint32_t lastReviewedAt = 0;
    uint16_t repetitions = 0;
    uint16_t lapses = 0;
    uint8_t lastRating = 0;
    bool illusionOfMastery = false;
};

enum class Confidence : uint8_t {
    None = 0,
    Low = 25,
    Medium = 60,
    High = 90,
};

enum class Outcome : uint8_t {
    Unknown = 0,
    Incorrect = 1,
    Correct = 2,
};

enum class Effort : uint8_t {
    None = 0,
    Difficult = 1,
    Normal = 2,
    Easy = 3,
};

enum class Rating : uint8_t {
    Again = 1,
    Hard = 2,
    Good = 3,
    Easy = 4,
};

enum class SessionMode : uint8_t {
    Review = 1,
    Practice = 2,
    Cram = 3,
};

inline const char* sessionModeName(SessionMode mode) {
    switch (mode) {
        case SessionMode::Review: return "review";
        case SessionMode::Practice: return "practice";
        case SessionMode::Cram: return "cram";
    }
    return "review";
}

inline const char* outcomeName(Outcome outcome) {
    switch (outcome) {
        case Outcome::Correct: return "correct";
        case Outcome::Incorrect: return "incorrect";
        default: return "unknown";
    }
}

inline const char* effortName(Effort effort) {
    switch (effort) {
        case Effort::Difficult: return "difficult";
        case Effort::Normal: return "normal";
        case Effort::Easy: return "easy";
        default: return "none";
    }
}

struct ReviewEvent {
    String id;
    String cardId;
    String deckId;
    String cardType;
    uint32_t reviewedAt = 0;
    uint32_t responseTimeMs = 0;
    uint8_t confidence = 0;
    Outcome outcome = Outcome::Unknown;
    Effort effort = Effort::None;
    Rating schedulerRating = Rating::Again;
    SessionMode sessionMode = SessionMode::Review;
    bool affectsSchedule = true;
    bool automaticEvaluation = false;
    int8_t selectedOptionIndex = -1;
    float difficultyBefore = 5.0f;
    float difficultyAfter = 5.0f;
    float stabilityBefore = 0.0f;
    float stabilityAfter = 0.0f;
    float retrievabilityBefore = 0.0f;
    uint32_t dueBefore = 0;
    uint32_t dueAfter = 0;
};

struct SessionStats {
    SessionMode mode = SessionMode::Review;
    uint16_t reviewed = 0;
    uint16_t correct = 0;
    uint16_t incorrect = 0;
    uint32_t startedAtMs = 0;
    uint32_t endedAtMs = 0;

    uint32_t durationSeconds() const {
        if (endedAtMs < startedAtMs) return 0;
        return (endedAtMs - startedAtMs) / 1000U;
    }
};
