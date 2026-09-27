#pragma once

#include <cstddef>
#include "models.h"

size_t loadDefaultCards(CardDefinition* cards, size_t maxCards);

size_t appendMandarinTrainingDeck(CardDefinition* cards,
                                  CardState* states,
                                  size_t maxCards,
                                  size_t count);

bool refreshMandarinTrainingDeck(CardDefinition* cards, size_t count);
