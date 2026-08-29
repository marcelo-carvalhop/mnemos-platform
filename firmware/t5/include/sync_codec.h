#pragma once

#include <Arduino.h>
#include "models.h"

class Storage;

namespace SyncCodec {

struct ReviewDeltaApplyResult {
    uint64_t cursor = 0;
    uint16_t appended = 0;
    bool hasMore = false;
};


bool applySnapshotV2(const String& body,
                     CardDefinition* cards,
                     CardState* states,
                     size_t maxCards,
                     size_t& cardCount,
                     Storage& storage,
                     String& error);

struct ProgressResetDeltaApplyResult {
    uint64_t cursor = 0;
    uint16_t appended = 0;
    bool hasMore = false;
};

struct UserSettingDeltaApplyResult {
    uint64_t cursor = 0;
    uint16_t applied = 0;
    bool hasMore = false;
};

bool applyProgressResetDeltaV2(
    const String& body,
    Storage& storage,
    ProgressResetDeltaApplyResult& result,
    String& error);

bool applyUserSettingDeltaV2(
    const String& body,
    Storage& storage,
    UserSettingDeltaApplyResult& result,
    String& error);

String buildReviewBatchV2(const Storage& storage);

bool applyReviewDeltaV2(
    const String& body,
    Storage& storage,
    ReviewDeltaApplyResult& result,
    String& error);

}  // namespace SyncCodec
