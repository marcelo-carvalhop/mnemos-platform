#include "backend_sync_service.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <WiFiClient.h>
#include <WiFiClientSecure.h>

#include "config.h"
#include "network_service.h"
#include "storage.h"
#include "sync_codec.h"

BackendSyncService::BackendSyncService(NetworkService& network,
                                       Storage& storage,
                                       CardDefinition* cards,
                                       CardState* states,
                                       size_t maxCards,
                                       size_t& cardCount)
    : network_(network),
      storage_(storage),
      cards_(cards),
      states_(states),
      maxCards_(maxCards),
      cardCount_(cardCount) {}

void BackendSyncService::begin() {
    lastSyncMs_ = millis();
}

bool BackendSyncService::consumeLibraryUpdated() {
    const bool value = libraryUpdated_;
    libraryUpdated_ = false;
    return value;
}

void BackendSyncService::loop() {
    if (!network_.enabled() || !network_.connected()) return;
    if (network_.backendUrl().length() == 0 || network_.deviceToken().length() == 0) return;
    const uint32_t intervalMs = network_.syncIntervalSeconds() * 1000U;
    if (millis() - lastSyncMs_ < intervalMs) return;
    syncNow();
}

bool BackendSyncService::request(const String& method,
                                 const String& path,
                                 const String& body,
                                 int& status,
                                 String& response) {
    String base = network_.backendUrl();
    while (base.endsWith("/")) base.remove(base.length() - 1);
    const String url = base + path;

    HTTPClient http;
    bool begun = false;
    WiFiClient plain;
    WiFiClientSecure secure;

    if (url.startsWith("https://")) {
        if (String(Config::BACKEND_ROOT_CA).length() == 0) {
            Serial.println("[backend] HTTPS exige BACKEND_ROOT_CA configurado");
            return false;
        }
        secure.setCACert(Config::BACKEND_ROOT_CA);
        begun = http.begin(secure, url);
    } else if (url.startsWith("http://")) {
        begun = http.begin(plain, url);
    }
    if (!begun) return false;

    http.setTimeout(12000);
    http.addHeader("Authorization", "Bearer " + network_.deviceToken());
    http.addHeader("Content-Type", "application/json");
    if (method == "GET") status = http.GET();
    else status = http.POST(body);
    if (status > 0) response = http.getString();
    http.end();
    return status > 0;
}

bool BackendSyncService::pushReviews() {
    if (storage_.pendingReviewCount() == 0) return true;
    const String body = SyncCodec::buildReviewBatchV2(storage_);
    int status = 0;
    String response;
    if (!request("POST", "/v1/terminal/reviews", body, status, response)) return false;
    if (status < 200 || status >= 300) {
        Serial.printf("[backend] reviews HTTP %d\n", status);
        return false;
    }
    return storage_.clearReviewOutbox();
}

bool BackendSyncService::pullReviews() {

    uint64_t cursor =
        storage_.reviewCursor();

    // Limite defensivo: 32 páginas x 100 eventos por ciclo.
    for (
        uint8_t page = 0;
        page < 32;
        ++page
    ) {
        char cursorText[24];

        snprintf(
            cursorText,
            sizeof(cursorText),
            "%llu",
            static_cast<unsigned long long>(
                cursor));

        const String path =
            String(
                "/v1/terminal/reviews?since=")
            +
            cursorText
            +
            "&limit=100";

        int status = 0;
        String body;

        if (
            !request(
                "GET",
                path,
                "",
                status,
                body)
        ) {
            return false;
        }

        if (status == 410) {
            Serial.println(
                "[backend] review cursor expirado; "
                "resync completo necessario");
            return false;
        }

        if (
            status < 200 ||
            status >= 300
        ) {
            Serial.printf(
                "[backend] review pull HTTP %d\n",
                status);
            return false;
        }

        SyncCodec::
            ReviewDeltaApplyResult result;

        String error;

        if (
            !SyncCodec::applyReviewDeltaV2(
                body,
                storage_,
                result,
                error)
        ) {
            Serial.printf(
                "[backend] delta de reviews rejeitado: %s\n",
                error.c_str());
            return false;
        }

        if (result.appended > 0) {
            // O nome histórico permanece por compatibilidade;
            // o sinal agora significa conteúdo OU estado alterado.
            libraryUpdated_ = true;

            Serial.printf(
                "[backend] reviews remotas=%u cursor=%llu\n",
                static_cast<unsigned>(
                    result.appended),
                static_cast<unsigned long long>(
                    result.cursor));
        }

        if (!result.hasMore) {
            return true;
        }

        if (result.cursor <= cursor) {
            Serial.println(
                "[backend] cursor de reviews nao avancou");
            return false;
        }

        cursor =
            result.cursor;
    }

    Serial.println(
        "[backend] limite de paginas de reviews atingido");

    return false;
}


bool BackendSyncService::pullSnapshot() {
    int status = 0;
    String body;
    const String path = "/v1/terminal/snapshot?limit=" + String(maxCards_) + "&schema=mnemos.sync%2Fv2";
    if (!request("GET", path, "", status, body)) return false;
    if (status < 200 || status >= 300) {
        Serial.printf("[backend] snapshot HTTP %d\n", status);
        return false;
    }

    String error;
    if (!SyncCodec::applySnapshotV2(body, cards_, states_, maxCards_, cardCount_, storage_, error)) {
        Serial.printf("[backend] snapshot rejeitado: %s\n", error.c_str());
        return false;
    }
    libraryUpdated_ = true;
    return true;
}

bool BackendSyncService::reportStatus(bool synced) {
    JsonDocument doc;
    JsonArray deckIds = doc["reported_deck_ids"].to<JsonArray>();
    uint64_t revision = 0;
    for (size_t i = 0; i < cardCount_; ++i) {
        if (cards_[i].revision > revision) revision = cards_[i].revision;
        bool exists = false;
        for (JsonVariantConst value : deckIds) {
            if (String(value.as<const char*>()) == cards_[i].deckId) { exists = true; break; }
        }
        if (!exists && cards_[i].deckId.length() > 0) deckIds.add(cards_[i].deckId);
    }
    doc["firmware"] = Config::APP_VERSION;
    doc["protocol"] = Config::DEVICE_PROTOCOL_VERSION;
    doc["card_count"] = cardCount_;
    doc["max_cards"] = maxCards_;
    doc["pending_reviews"] = storage_.pendingReviewCount();
    doc["connectivity"] = network_.connected() ? "wifi" : "offline";
    doc["wifi_ssid"] = network_.ssid();
    doc["library_revision"] = revision;
    doc["synced"] = synced;
    doc["capabilities"]["directWifiSync"] = true;
    doc["capabilities"]["bleSync"] = false;
    doc["capabilities"]["keyboard"] = true;
    doc["capabilities"]["touch"] = Config::TOUCH_ENABLED;
    doc["capabilities"]["typedRecall"] = true;
    doc["capabilities"]["display"] = "epaper-960x540";
    String body;
    serializeJson(doc, body);
    int status = 0;
    String response;
    return request("POST", "/v1/terminal/status", body, status, response) && status >= 200 && status < 300;
}

bool BackendSyncService::syncNow() {
    if (!network_.connected() || network_.backendUrl().length() == 0 || network_.deviceToken().length() == 0) {
        return false;
    }
    lastSyncMs_ = millis();
    const bool reviewsOk =
        pushReviews();

    const bool snapshotOk =
        pullSnapshot();

    const bool pullOk =
        snapshotOk
            ? pullReviews()
            : false;

    const bool synced =
        reviewsOk &&
        snapshotOk &&
        pullOk;

    const bool statusOk =
        reportStatus(synced);

    Serial.printf(
        "[backend] sync push=%d snapshot=%d pull=%d status=%d\n",
        reviewsOk,
        snapshotOk,
        pullOk,
        statusOk);
    return synced;
}
