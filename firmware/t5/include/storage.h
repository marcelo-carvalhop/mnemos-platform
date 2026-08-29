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
                     SessionMode mode,
                     const SessionStats& stats);
    bool loadSession(const CardDefinition* cards,
                     size_t cardCount,
                     uint8_t* queue,
                     uint8_t maxQueue,
                     uint8_t& sessionCount,
                     uint8_t& currentPosition,
                     SessionMode& mode,
                     SessionStats& stats);
    bool clearSession();

    bool appendReview(const ReviewEvent& event);
    String reviewOutboxNdjson() const;
    String reviewHistoryNdjson() const;
    bool clearReviewOutbox();
    uint16_t pendingReviewCount() const;

    // Reviews recebidas do backend entram apenas no histórico.
    // Nunca devem voltar para o outbox.
    bool appendRemoteReviewJson(
        const String& line,
        bool& inserted);

    uint64_t reviewCursor() const;
    bool saveReviewCursor(uint64_t cursor);

    String progressResetHistoryNdjson() const;

    bool appendRemoteProgressResetJson(
        const String& line,
        bool& inserted);

    uint64_t progressResetCursor() const;
    bool saveProgressResetCursor(uint64_t cursor);

    uint64_t settingsCursor() const;
    bool saveSettingsCursor(uint64_t cursor);

    double desiredRetention() const;
    bool saveDesiredRetention(double value);

    bool resetAll();

private:
    bool appendReviewToPath(const char* path, const ReviewEvent& event);
    bool migrateLegacyReviewLog();
    String readTextFile(const char* path) const;

    uint64_t syncCursor(const char* key) const;
    bool saveSyncCursor(
        const char* key,
        uint64_t cursor);
    bool reviewHistoryContainsId(const String& id) const;
};
