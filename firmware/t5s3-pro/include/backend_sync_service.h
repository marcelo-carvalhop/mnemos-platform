#pragma once

#include <Arduino.h>

#include <memory>

#include "models.h"

class NetworkService;
class Storage;
class TimeService;

// Por que uma sincronização começou. Aparece no serial e no relatório.
enum class SyncTrigger : uint8_t {
    Manual = 0,
    Boot,
    WifiConnected,
    SessionEnd,
    Periodic,
    Provisioned,
    Serial,
};

enum class SyncOutcome : uint8_t {
    NeverRan = 0,
    Ok,
    Partial,            // parte das etapas falhou; nada se perdeu
    Offline,            // sem Wi-Fi
    NotPaired,          // sem URL/credencial do backend
    AuthRejected,       // 401: credencial revogada ou terminal trocou de conta
    Unreachable,        // DNS, conexão recusada, timeout
    TlsFailed,          // HTTPS sem CA válida
    CapacityExceeded,   // 409: baralhos escolhidos passam da capacidade
    ServerError,        // 5xx ou resposta inesperada
    StorageError,       // LittleFS cheio/corrompido
};

struct BackendSyncReport {
    SyncOutcome outcome = SyncOutcome::NeverRan;
    SyncTrigger trigger = SyncTrigger::Manual;
    uint32_t finishedAtMs = 0;
    uint32_t durationMs = 0;
    int httpStatus = 0;
    String failedStep;
    String detail;

    uint16_t reviewsPushed = 0;
    uint16_t reviewsDropped = 0;      // prática livre que não sobe
    uint16_t reviewsQuarantined = 0;  // recusadas pelo servidor
    uint16_t reviewsPending = 0;      // ainda no outbox após a rodada

    size_t cards = 0;
    uint16_t cardsSkipped = 0;
    bool libraryChanged = false;
    bool keptLocalLibrary = false;

    uint16_t remoteReviews = 0;
    uint16_t remoteResets = 0;
    uint16_t settingsApplied = 0;
    bool clockAdjusted = false;
};

class BackendSyncService {
public:
    BackendSyncService(NetworkService& network,
                       Storage& storage,
                       TimeService& clock,
                       CardDefinition* cards,
                       CardState* states,
                       size_t maxCards,
                       size_t& cardCount);
    ~BackendSyncService();

    void begin();

    // Executa uma sincronização pendente ou periódica, se houver rede.
    void loop();

    // Sincroniza agora (bloqueante, alguns segundos).
    bool syncNow(SyncTrigger trigger = SyncTrigger::Manual);

    // Agenda uma sincronização assim que houver rede.
    void requestSync(SyncTrigger trigger, uint32_t delayMs = 0);
    bool hasPendingRequest() const { return pending_; }
    void cancelPendingRequest() { pending_ = false; }

    bool consumeLibraryUpdated();

    bool paired() const;

    // "Conectar pelo site": o terminal pede um código ao servidor, mostra, e
    // pergunta de tempos em tempos se alguém o digitou no site. Quando sim, a
    // resposta traz a credencial do terminal, gravada como a do app.
    enum class WebPairingState : uint8_t { Idle, Pending, Claimed, Expired, Failed };
    bool startWebPairing(const String& baseUrl);
    WebPairingState pollWebPairing();
    void cancelWebPairing();
    bool webPairingActive() const { return webPairingState_ == WebPairingState::Pending; }
    WebPairingState webPairingState() const { return webPairingState_; }
    const String& webPairingCode() const { return webPairingCode_; }
    const String& webPairingUrl() const { return webPairingUrl_; }
    const String& webPairingError() const { return webPairingError_; }
    uint32_t webPairingIntervalMs() const { return webPairingIntervalMs_; }
    bool authRejected() const { return authRejected_; }
    void clearAuthRejected() { authRejected_ = false; }

    const BackendSyncReport& lastReport() const { return report_; }

    static const char* triggerName(SyncTrigger trigger);
    static const char* outcomeName(SyncOutcome outcome);
    static String outcomeTitle(const BackendSyncReport& report);
    static String outcomeMessage(const BackendSyncReport& report);

private:
    struct HttpResult {
        int status = 0;
        String body;
        String error;
        bool transportOk = false;
    };

    // Conexão HTTP(S) mantida viva durante uma rodada de sincronização:
    // evita um handshake TLS por requisição no backend HTTPS.
    struct Session;
    std::unique_ptr<Session> session_;

    NetworkService& network_;
    Storage& storage_;
    TimeService& clock_;
    CardDefinition* cards_;
    CardState* states_;
    size_t maxCards_;
    size_t& cardCount_;

    uint32_t lastSyncMs_ = 0;
    uint32_t lastFailureMs_ = 0;
    bool libraryUpdated_ = false;
    bool authRejected_ = false;
    bool everSynced_ = false;

    bool pending_ = false;
    SyncTrigger pendingTrigger_ = SyncTrigger::Manual;
    uint32_t pendingDueMs_ = 0;
    uint32_t pendingSinceMs_ = 0;

    String mdnsHost_;
    String mdnsIp_;
    uint32_t mdnsResolvedMs_ = 0;

    BackendSyncReport report_;

    WebPairingState webPairingState_ = WebPairingState::Idle;
    String webPairingBase_;
    String webPairingCode_;
    String webPairingUrl_;
    String webPairingPoll_;
    String webPairingError_;
    uint32_t webPairingIntervalMs_ = 3000;
    uint32_t webPairingExpiresMs_ = 0;
    bool postPublic(const String& baseUrl, const String& path, const String& body, HttpResult& out);

    bool pushReviews();
    bool pullSnapshot(bool& capacityExceeded);
    bool pullReviews();
    bool pullProgressResets();
    bool pullSettings();
    bool reportStatus(bool synced);
    void resetCursorsIfCredentialChanged();

    bool request(const char* method,
                 const String& path,
                 const String& body,
                 HttpResult& out);
    String resolveUrl(const String& url);
    String rootCertificates();
    void adjustClockFromDate(const String& dateHeader);
    void noteHttpFailure(const char* step, const HttpResult& result);
};
