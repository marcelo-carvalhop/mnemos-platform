#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>
#include "models.h"

class Storage;

namespace SyncCodec {

struct ReviewDeltaApplyResult {
    uint64_t cursor = 0;
    uint16_t appended = 0;
    uint16_t received = 0;
    bool hasMore = false;
};

struct SnapshotApplyResult {
    size_t cards = 0;           // cartões na biblioteca depois da aplicação
    uint16_t received = 0;      // cartões no payload
    uint16_t skipped = 0;       // cartões inválidos/incompatíveis ignorados
    uint16_t duplicates = 0;
    bool changed = false;       // biblioteca ou origem mudou e foi gravada
    bool keptLocalLibrary = false;  // snapshot vazio preservou biblioteca local
    String firstSkipReason;
};

// Filtro ArduinoJson com só os campos que o terminal usa.
void buildSnapshotFilter(JsonDocument& filter);

// Aplica um snapshot mnemos.sync/v2 já desserializado.
//
// - cartões inválidos são ignorados um a um (um cartão ruim não bloqueia a
//   biblioteca inteira);
// - texto é normalizado para as fontes do e-paper;
// - se ids, revisões e baralhos não mudaram, nada é gravado e changed=false;
// - fromBackend=true marca a biblioteca como espelho da conta. Um snapshot
//   vazio do backend não apaga uma biblioteca que nunca veio dele (cartões
//   importados do microSD continuam até a pessoa escolher baralhos).
bool applySnapshotDocument(JsonDocument& doc,
                           CardDefinition* cards,
                           CardState* states,
                           size_t maxCards,
                           size_t& cardCount,
                           Storage& storage,
                           bool fromBackend,
                           SnapshotApplyResult& result,
                           String& error);

// Compatibilidade: corpo JSON vindo do app por Wi-Fi local.
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

enum class OutboxLineKind : uint8_t {
    Push = 0,          // revisão válida, convertida em remote
    DropNotScheduled,  // prática livre: fica só no histórico local
    Reject,            // inválida para o contrato; vai para quarentena
};

// Converte uma linha do outbox local em mnemos.review/v2.
OutboxLineKind convertOutboxLine(const String& line,
                                 JsonObject remote,
                                 String& id,
                                 String& cardId,
                                 String& reason);

// Lote completo do outbox (protocolo local com o app).
String buildReviewBatchV2(const Storage& storage);

bool applyReviewDeltaV2(
    const String& body,
    Storage& storage,
    ReviewDeltaApplyResult& result,
    String& error);

}  // namespace SyncCodec
