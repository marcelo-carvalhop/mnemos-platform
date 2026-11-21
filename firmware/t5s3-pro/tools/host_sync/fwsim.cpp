// CLI de teste: roda o código real de sincronização do firmware contra o backend.
#define private public
#include "network_service.h"
#include "time_service.h"
#include "backend_sync_service.h"
#undef private

#include "storage.h"
#include "sync_codec.h"
#include "terminal_identity.h"
#include "text_sanitizer.h"
#include "HTTPClient.h"
#include "LittleFS.h"
#include <ArduinoJson.h>
#include <cstdlib>
#include <fstream>
#include <iostream>

static bool g_connected = true;
static uint32_t g_now = 0;
extern uint32_t g_millisOffset;

bool NetworkService::connected() const { return g_connected && enabled_; }
String NetworkService::ip() const { return "192.168.4.2"; }
uint32_t TimeService::now() { return g_now; }
void TimeService::setFromEpoch(uint32_t e) { trusted_ = true; g_now = e; }

static const char* env(const char* k, const char* d) { const char* v = getenv(k); return v ? v : d; }

CardDefinition cards[Config::MAX_DEVICE_CARDS];
CardState states[Config::MAX_DEVICE_CARDS];
size_t cardCount = 0;

static void printLibrary(Storage& storage, JsonDocument& out) {
    JsonArray arr = out["cards"].to<JsonArray>();
    for (size_t i = 0; i < cardCount; ++i) {
        JsonObject c = arr.add<JsonObject>();
        c["id"] = cards[i].id; c["deckId"] = cards[i].deckId; c["deck"] = cards[i].deck;
        c["q"] = cards[i].question; c["a"] = cards[i].answer; c["rev"] = cards[i].revision;
    }
    out["cardCount"] = cardCount;
    out["fromBackend"] = storage.libraryFromBackend();
    out["pending"] = storage.pendingReviewCount();
    out["rejected"] = storage.rejectedReviewCount();
    out["retention"] = storage.desiredRetention();
    out["cursorReviews"] = storage.reviewCursor();
    out["cursorResets"] = storage.progressResetCursor();
    out["cursorSettings"] = storage.settingsCursor();
    int hist = 0; String h = storage.reviewHistoryNdjson(); for (size_t i = 0; i < h.length(); ++i) if (h[i] == '\n') ++hist;
    out["history"] = hist;
}

int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage\n"); return 2; }
    const std::string cmd = argv[1];
    LittleFS.root = env("FW_LFS", "/tmp/lfs");
    Serial.quiet = std::string(env("FW_QUIET", "0")) == "1";
    g_connected = std::string(env("FW_CONNECTED", "1")) == "1";
    g_now = (uint32_t)strtoul(env("FW_NOW", "0"), nullptr, 10);
    if (g_now == 0) g_now = (uint32_t)time(nullptr);

    if (cmd == "sanitize") { std::cout << TextSanitizer::forDisplay(String(argv[2])).c_str() << std::endl; return 0; }
    if (cmd == "uuid") { std::cout << TerminalIdentity::uuidV7((uint64_t)g_now * 1000ULL).c_str() << std::endl; return 0; }

    Storage storage; storage.begin();
    storage.loadLibrary(cards, states, Config::MAX_DEVICE_CARDS, cardCount);
    storage.loadStates(states, cardCount);

    NetworkService network;
    network.enabled_ = true;
    network.backendUrl_ = env("FW_API", "");
    network.deviceToken_ = env("FW_TOKEN", "");
    network.connectedSsid_ = env("FW_SSID", "Laboratorio-Mnemos");
    network.syncIntervalSeconds_ = 1800;

    TimeService clock;
    clock.trusted_ = std::string(env("FW_TRUSTED", "1")) == "1";
    clock.ntpSynchronized_ = std::string(env("FW_NTP", "0")) == "1";

    const size_t maxCards = (size_t)atoi(env("FW_MAXCARDS", "128"));
    BackendSyncService sync(network, storage, clock, cards, states, maxCards, cardCount);
    sync.begin();

    JsonDocument out;
    if (cmd == "sync") {
        HTTPClient::requests = 0;
        const bool ok = sync.syncNow(SyncTrigger::Manual);
        const BackendSyncReport& r = sync.lastReport();
        out["ok"] = ok;
        out["outcome"] = BackendSyncService::outcomeName(r.outcome);
        out["title"] = BackendSyncService::outcomeTitle(r);
        out["message"] = BackendSyncService::outcomeMessage(r);
        out["http"] = r.httpStatus; out["step"] = r.failedStep; out["detail"] = r.detail;
        out["pushed"] = r.reviewsPushed; out["dropped"] = r.reviewsDropped; out["quarantined"] = r.reviewsQuarantined;
        out["pendingAfter"] = r.reviewsPending; out["changed"] = r.libraryChanged; out["kept"] = r.keptLocalLibrary;
        out["skipped"] = r.cardsSkipped; out["remoteReviews"] = r.remoteReviews; out["remoteResets"] = r.remoteResets;
        out["settings"] = r.settingsApplied; out["clockAdjusted"] = r.clockAdjusted; out["clockNow"] = g_now;
        out["libraryUpdatedFlag"] = sync.consumeLibraryUpdated();
        out["requests"] = HTTPClient::requests;
        out["authRejected"] = sync.authRejected();
        printLibrary(storage, out);
    } else if (cmd == "study") {
        const int n = atoi(argv[2]);
        const bool practice = argc > 3 && std::string(argv[3]) == "practice";
        JsonArray ids = out["ids"].to<JsonArray>();
        for (int i = 0; i < n && (size_t)i < cardCount; ++i) {
            ReviewEvent ev;
            ev.reviewedAt = g_now - (n - i) * 30;
            ev.reviewedAtMs = (uint64_t)ev.reviewedAt * 1000ULL;
            ev.id = TerminalIdentity::uuidV7(ev.reviewedAtMs);
            ev.cardId = cards[i].id; ev.deckId = cards[i].deckId; ev.cardType = cards[i].type;
            ev.schedulerRating = Rating::Good; ev.outcome = Outcome::Correct; ev.effort = Effort::Normal;
            ev.sessionMode = practice ? SessionMode::Practice : SessionMode::Review;
            ev.affectsSchedule = !practice; ev.responseTimeMs = 3200;
            ev.stabilityAfter = 2.5f; ev.difficultyAfter = 4.9f; ev.dueAfter = ev.reviewedAt + 86400;
            storage.appendReview(ev);
            ids.add(ev.id);
        }
        printLibrary(storage, out);
    } else if (cmd == "addline") {
        File f = LittleFS.open("/review_outbox.ndjson", "a"); f.print(argv[2]); f.println(); f.close();
        File h = LittleFS.open("/review_history.ndjson", "a"); h.print(argv[2]); h.println(); h.close();
        printLibrary(storage, out);
    } else if (cmd == "seedlocal") {
        cardCount = 2;
        cards[0] = CardDefinition{}; cards[0].id = "local-1"; cards[0].deckId = "mandarim-local"; cards[0].deck = "Mandarim (SD)"; cards[0].question = "你好"; cards[0].answer = "olá";
        cards[1] = CardDefinition{}; cards[1].id = "local-2"; cards[1].deckId = "mandarim-local"; cards[1].deck = "Mandarim (SD)"; cards[1].question = "谢谢"; cards[1].answer = "obrigado";
        states[0] = CardState{}; states[0].id = "local-1"; states[1] = CardState{}; states[1].id = "local-2";
        storage.saveLibrary(cards, states, cardCount); storage.saveStates(states, cardCount); storage.setLibraryFromBackend(false);
        printLibrary(storage, out);
    } else if (cmd == "show") {
        printLibrary(storage, out);
    } else if (cmd == "loop") {
        // Avança o relógio monotônico e chama loop() para ver se sincroniza.
        if (argc > 3 && std::string(argv[3]) == "authrejected") sync.authRejected_ = true;
        HTTPClient::requests = 0;
        g_millisOffset += (uint32_t)atoi(argv[2]) * 1000U;
        sync.loop();
        out["requests"] = HTTPClient::requests;
        out["outcome"] = BackendSyncService::outcomeName(sync.lastReport().outcome);
        out["trigger"] = BackendSyncService::triggerName(sync.lastReport().trigger);
    } else if (cmd == "pending") {
        // requestSync com e sem rede
        sync.requestSync(SyncTrigger::SessionEnd, 0);
        HTTPClient::requests = 0;
        sync.loop();
        out["requestsAfterLoop"] = HTTPClient::requests;
        out["stillPending"] = sync.hasPendingRequest();
        out["outcome"] = BackendSyncService::outcomeName(sync.lastReport().outcome);
    } else {
        fprintf(stderr, "unknown\n"); return 2;
    }
    std::string s; serializeJson(out, s);
    std::cout << "@result " << s << std::endl;
    return 0;
}
