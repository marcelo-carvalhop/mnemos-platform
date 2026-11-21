#pragma once

#include <cstddef>
#include <vector>
#include <ArduinoJson.h>
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

    // Revisões de sessões de prática (affectsSchedule=false) vão só para o
    // histórico local: não alimentam o scheduler de nenhuma plataforma.
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

    // Versão em lote: lê o histórico uma vez, deduplica por id e grava todas
    // as linhas novas numa única abertura de arquivo.
    bool appendRemoteReviewLines(
        const std::vector<String>& lines,
        uint16_t& inserted);

    // Outbox linha a linha, para envio em lotes e remoção seletiva.
    bool loadReviewOutboxLines(std::vector<String>& lines) const;
    bool rewriteReviewOutbox(const std::vector<String>& lines);

    // Revisões que o servidor recusou de forma definitiva saem do outbox e
    // ficam registradas aqui, com o motivo, em vez de travar a fila.
    bool quarantineReviewLines(
        const std::vector<String>& lines,
        const String& reason);
    uint16_t rejectedReviewCount() const;

    uint64_t reviewCursor() const;
    bool saveReviewCursor(uint64_t cursor);

    String progressResetHistoryNdjson() const;

    bool appendRemoteProgressResetJson(
        const String& line,
        bool& inserted);

    bool appendRemoteProgressResetLines(
        const std::vector<String>& lines,
        uint16_t& inserted);

    uint64_t progressResetCursor() const;
    bool saveProgressResetCursor(uint64_t cursor);

    uint64_t settingsCursor() const;
    bool saveSettingsCursor(uint64_t cursor);

    double desiredRetention() const;
    bool saveDesiredRetention(double value);

    // Metadados de sincronização com o backend.
    String syncMetaString(const char* key) const;
    bool saveSyncMetaString(const char* key, const String& value);

    // true quando a biblioteca atual veio de um snapshot do backend.
    bool libraryFromBackend() const;
    bool setLibraryFromBackend(bool value);

    // Zera os cursores incrementais (troca de conta/credencial).
    bool resetSyncCursors();

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
    bool appendUniqueLines(
        const char* path,
        const std::vector<String>& lines,
        uint16_t& inserted);
    bool writeSyncMeta(JsonDocument& doc);
    bool readSyncMeta(JsonDocument& doc) const;
};
