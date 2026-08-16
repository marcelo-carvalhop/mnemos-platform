#pragma once

#include <cstddef>
#include "models.h"

class Storage {
public:
    bool begin();

    bool loadLibrary(CardDefinition* cards, CardState* states, size_t maxCards, size_t& count);
    bool saveLibrary(const CardDefinition* cards, const CardState* states, size_t count);

    bool loadStates(CardState* states, size_t count);
    bool saveStates(const CardState* states, size_t count);

    bool saveSession(const CardDefinition* cards,
                     const uint8_t* queue,
                     uint8_t sessionCount,
                     uint8_t currentPosition,
                     const SessionStats& stats);
    bool loadSession(const CardDefinition* cards,
                     size_t cardCount,
                     uint8_t* queue,
                     uint8_t maxQueue,
                     uint8_t& sessionCount,
                     uint8_t& currentPosition,
                     SessionStats& stats);
    bool clearSession();

    bool appendReview(const ReviewEvent& event);
    String reviewsNdjson() const;
    bool clearReviews();
    bool resetAll();

private:
    uint32_t reviewSequence_ = 0;
};
