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
    bool appendReview(const ReviewEvent& event);
    String reviewsNdjson() const;
    bool clearReviews();
    bool resetAll();

private:
    uint32_t reviewSequence_ = 0;
};
