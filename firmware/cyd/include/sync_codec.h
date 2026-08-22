#pragma once

#include <Arduino.h>
#include "models.h"

class Storage;

namespace SyncCodec {

bool applySnapshotV2(const String& body,
                     CardDefinition* cards,
                     CardState* states,
                     size_t maxCards,
                     size_t& cardCount,
                     Storage& storage,
                     String& error);

String buildReviewBatchV2(const Storage& storage);

}  // namespace SyncCodec
