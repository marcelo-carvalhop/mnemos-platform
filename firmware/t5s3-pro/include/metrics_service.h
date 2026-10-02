#pragma once

#include <Arduino.h>
#include "models.h"

class Storage;
class TimeService;

class MetricsService {
public:
    MetricsService(Storage& storage,
                   TimeService& clock,
                   CardDefinition* cards,
                   CardState* states,
                   size_t& cardCount);

    String buildJson() const;

private:
    Storage& storage_;
    TimeService& clock_;
    CardDefinition* cards_;
    CardState* states_;
    size_t& cardCount_;

    int findCardIndex(const String& cardId) const;
};
