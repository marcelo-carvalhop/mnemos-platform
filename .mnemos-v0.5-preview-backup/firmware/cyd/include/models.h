#pragma once

#include <Arduino.h>

struct CardDefinition {
    String id;
    String deckId;
    String deck;
    String type = "basic";
    String format = "plain";
    String question;
    String answer;
    uint64_t revision = 1;
};

struct CardState {
    String id;
    uint32_t dueAt = 0;
    uint32_t intervalSeconds = 0;
    uint16_t repetitions = 0;
    uint16_t lapses = 0;
    uint8_t lastRating = 0;
};

enum class Confidence : uint8_t {
    None = 0,
    DontKnow = 1,
    Maybe = 2,
    Certain = 3,
};

enum class Rating : uint8_t {
    Again = 1,
    Hard = 2,
    Good = 3,
    Easy = 4,
};

struct ReviewEvent {
    String id;
    String cardId;
    uint32_t reviewedAt = 0;
    uint32_t responseTimeMs = 0;
    uint32_t intervalBefore = 0;
    uint32_t intervalAfter = 0;
    uint8_t confidence = 0;
    uint8_t rating = 0;
};

struct SessionStats {
    uint16_t reviewed = 0;
    uint16_t ratingCounts[4] = {0, 0, 0, 0};
    uint32_t startedAtMs = 0;
    uint32_t endedAtMs = 0;

    uint32_t durationSeconds() const {
        if (endedAtMs < startedAtMs) return 0;
        return (endedAtMs - startedAtMs) / 1000U;
    }
};
