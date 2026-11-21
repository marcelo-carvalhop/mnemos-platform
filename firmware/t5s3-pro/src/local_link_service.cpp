#include "local_link_service.h"

#include <ArduinoJson.h>
#include <WiFi.h>
#include <vector>
#include <esp_system.h>

#include "config.h"
#include "metrics_service.h"
#include "network_service.h"
#include "storage.h"
#include "sync_codec.h"
#include "terminal_identity.h"
#include "time_service.h"

LocalLinkService::LocalLinkService(Storage& storage,
                                   TimeService& clock,
                                   NetworkService& network,
                                   MetricsService& metrics,
                                   CardDefinition* cards,
                                   CardState* states,
                                   size_t maxCards,
                                   size_t& cardCount)
    : storage_(storage),
      clock_(clock),
      network_(network),
      metrics_(metrics),
      cards_(cards),
      states_(states),
      maxCards_(maxCards),
      cardCount_(cardCount) {}

String LocalLinkService::makeHex(uint32_t value, uint8_t digits) const {
    String result(value, HEX);
    result.toUpperCase();
    while (result.length() < digits) result = "0" + result;
    if (result.length() > digits) result = result.substring(result.length() - digits);
    return result;
}

bool LocalLinkService::start(LocalLinkMode mode) {
    if (active_) {
        return mode_ == mode;
    }

    mode_ = mode;

    const String suffix =
        TerminalIdentity::macSuffix();

    deviceId_ =
        TerminalIdentity::deviceId();

    token_ =
        makeHex(
            esp_random(),
            8) +
        makeHex(
            esp_random(),
            8);

    // O app sempre entra na rede temporária indicada no QR (ssid/pwd) antes
    // de falar com o terminal. Anunciar a rede da casa com senha vazia fazia
    // o Android tentar uma rede aberta e o pareamento falhava; por isso o
    // QR sempre aponta para o SoftAP. Com o STA conectado o rádio opera em
    // AP+STA e a conexão atual é preservada.
    lanTransport_ = false;

    radioPrepared_ = false;

    String localHost;
    String transport;

    {
        transport = "ap";

        ssid_ =
            "MNEMOS-" + suffix;

        password_ =
            "MN" +
            makeHex(
                esp_random(),
                10);

        Serial.printf(
            "[local-link] AP provisioning fallback: mode=%d status=%d heap=%u\n",
            static_cast<int>(
                WiFi.getMode()),
            static_cast<int>(
                WiFi.status()),
            static_cast<unsigned>(
                ESP.getFreeHeap()));

        network_.prepareProvisioning();

        if (
            network_.lastError().
                length() >
            0
        ) {
            Serial.printf(
                "[local-link] preparacao de radio falhou: %s\n",
                network_.
                    lastError().
                    c_str());

            network_.
                finishProvisioning();

            return false;
        }

        radioPrepared_ = true;

        Serial.printf(
            "[local-link] iniciando SoftAP fallback: %s\n",
            ssid_.c_str());

        if (
            !WiFi.softAP(
                ssid_.c_str(),
                password_.c_str(),
                6,
                0,
                1)
        ) {
            Serial.println(
                "[local-link] falha ao iniciar SoftAP fallback");

            network_.
                finishProvisioning();

            radioPrepared_ = false;
            return false;
        }

        delay(80);

        localHost =
            WiFi.softAPIP().
                toString();

        if (
            localHost.length() ==
                0 ||
            localHost ==
                "0.0.0.0"
        ) {
            Serial.println(
                "[local-link] SoftAP sem endereco IP valido");

            network_.
                finishProvisioning();

            radioPrepared_ = false;
            return false;
        }

        Serial.printf(
            "[local-link] SoftAP fallback ativo IP=%s\n",
            localHost.c_str());
    }

    const String modeText =
        mode_ ==
                LocalLinkMode::Provisioning
            ? "provision"
            : "sync";

    // O QR é desenhado na versão 8 com correção L: cabem no máximo 192
    // bytes. Acima disso a biblioteca gera um código corrompido sem avisar
    // (o payload antigo, com "transport", tinha 195 bytes no modo SoftAP e
    // não era lido pelo app). "transport" sai: o app não usa esse campo.
    constexpr size_t QR_MAX_BYTES = 192U;

    const String head =
        "mnemos://pair?v=" +
        String(Config::DEVICE_PROTOCOL_VERSION) +
        "&mode=" + modeText +
        "&id=" + deviceId_ +
        "&ssid=" + ssid_ +
        "&pwd=" + password_ +
        "&host=" + localHost +
        "&token=" + token_;

    const String model = "&model=" + String(Config::DEVICE_MODEL);
    const String firmware = "&fw=" + String(Config::APP_VERSION);

    qrPayload_ = head + model + firmware;
    if (qrPayload_.length() > QR_MAX_BYTES) qrPayload_ = head + firmware;  // app assume modelo genérico
    if (qrPayload_.length() > QR_MAX_BYTES) qrPayload_ = head;

    Serial.printf(
        "[local-link] QR %u bytes (limite %u)\n",
        static_cast<unsigned>(qrPayload_.length()),
        static_cast<unsigned>(QR_MAX_BYTES));

    if (!routesConfigured_) {
        configureRoutes();
        routesConfigured_ = true;
    }

    server_.begin();

    active_ = true;
    completeRequested_ = false;
    libraryUpdated_ = false;
    provisioned_ = false;
    startedAtMs_ = millis();

    Serial.printf(
        "[local-link] %s iniciado via %s: host=%s heap=%u\n",
        modeText.c_str(),
        transport.c_str(),
        localHost.c_str(),
        static_cast<unsigned>(
            ESP.getFreeHeap()));

    return true;
}




void LocalLinkService::stop() {
    if (!active_) {
        return;
    }

    server_.stop();

    if (radioPrepared_) {
        network_.
            finishProvisioning();
    }

    active_ = false;
    completeRequested_ = false;
    radioPrepared_ = false;
    lanTransport_ = false;

    Serial.println(
        "[local-link] encerrado");
}


void LocalLinkService::loop() {
    if (!active_) {
        return;
    }

    static uint32_t lastHeartbeatMs =
        0;

    const uint32_t now =
        millis();

    if (lanTransport_) {
        // Existing STA is already connected. WebServer listens on the
        // current LAN interface and no radio transition is necessary.
        server_.handleClient();
    } else {
        const uint8_t stations =
            WiFi.softAPgetStationNum();

        if (stations > 0) {
            server_.handleClient();
        }
    }

    if (
        now -
            lastHeartbeatMs >=
        2000U
    ) {
        lastHeartbeatMs =
            now;

        Serial.printf(
            "[local-link] heartbeat transport=%s status=%d heap=%u\n",
            lanTransport_
                ? "lan"
                : "ap",
            static_cast<int>(
                WiFi.status()),
            static_cast<unsigned>(
                ESP.getFreeHeap()));
    }

    if (completeRequested_) {
        delay(40);
        stop();
        return;
    }

    if (
        now -
            startedAtMs_ >
        static_cast<uint32_t>(
            Config::
                LOCAL_LINK_TIMEOUT_SECONDS) *
            1000U
    ) {
        stop();
    }
}



bool LocalLinkService::consumeLibraryUpdated() {
    const bool value = libraryUpdated_;
    libraryUpdated_ = false;
    return value;
}

bool LocalLinkService::consumeProvisioned() {
    const bool value = provisioned_;
    provisioned_ = false;
    return value;
}

bool LocalLinkService::authorized() {
    return server_.hasArg("token") && server_.arg("token") == token_;
}

bool LocalLinkService::requireMode(LocalLinkMode mode) {
    if (mode_ == mode) return true;
    server_.send(409, "application/json", "{\"error\":\"operation_not_allowed_in_this_mode\"}");
    return false;
}

void LocalLinkService::configureRoutes() {
    server_.on("/v4/info", HTTP_GET, [this]() { sendInfo(); });
    server_.on("/v4/time", HTTP_POST, [this]() { setClock(); });
    server_.on("/v4/network/status", HTTP_GET, [this]() { networkStatus(); });
    server_.on("/v4/provision", HTTP_POST, [this]() { provision(); });
    server_.on("/v4/sync/library", HTTP_POST, [this]() { importLibrary(); });
    server_.on("/v4/sync/reviews", HTTP_GET, [this]() { exportReviews(); });
    server_.on("/v4/sync/reviews/ack", HTTP_POST, [this]() { acknowledgeReviews(); });
    server_.on("/v4/metrics", HTTP_GET, [this]() { exportMetrics(); });
    server_.on("/v4/complete", HTTP_POST, [this]() { complete(); });
    server_.onNotFound([this]() {
        server_.send(404, "application/json", "{\"error\":\"not_found\"}");
    });
}

void LocalLinkService::sendInfo() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    JsonDocument doc;
    doc["protocol"] = Config::DEVICE_PROTOCOL_VERSION;
    doc["deviceId"] = deviceId_;
    doc["firmware"] = Config::APP_VERSION;
    doc["model"] = Config::DEVICE_MODEL;
    doc["localMode"] = mode_ == LocalLinkMode::Provisioning ? "provision" : "sync";
    doc["cardCount"] = cardCount_;
    doc["maxCards"] = maxCards_;
    doc["pendingReviews"] = storage_.pendingReviewCount();
    doc["clockTrusted"] = clock_.trusted();
    doc["wifiEnabled"] = network_.enabled();
    doc["wifiConnected"] = network_.connected();
    doc["backendPaired"] =
        network_.backendUrl().length() > 0 && network_.deviceToken().length() > 0;
    if (network_.ssid().length() > 0) doc["infrastructureSsid"] = network_.ssid();
    // O app usa deckIds como "estado observado" logo depois do pareamento.
    JsonArray deckIds = doc["deckIds"].to<JsonArray>();
    if (storage_.libraryFromBackend()) {
        for (size_t i = 0; i < cardCount_; ++i) {
            const String& deckId = cards_[i].deckId;
            if (deckId.length() == 0) continue;
            bool exists = false;
            for (JsonVariantConst value : deckIds) {
                if (deckId == value.as<const char*>()) {
                    exists = true;
                    break;
                }
            }
            if (!exists && deckIds.size() < 32) deckIds.add(deckId);
        }
    }
    doc["features"]["wifiProvisioning"] = true;
    doc["features"]["knownNetworks"] = true;
    doc["features"]["directWifiSync"] = true;
    doc["features"]["backendSync"] = true;
    doc["features"]["metrics"] = true;
    doc["features"]["bleSync"] = false;
    doc["features"]["keyboard"] = false;
    doc["features"]["touch"] = Config::TOUCH_ENABLED;
    doc["features"]["rtc"] = true;
    doc["features"]["sdStorage"] = true;
        doc["features"]["sdFirstLibrary"] = true;
        doc["features"]["lazyCardContent"] = true;
        doc["features"]["lightSleep"] = true;
        doc["features"]["deepSleep"] = true;
        doc["features"]["deepSleepTouchWake"] = false;

#ifdef CONFIG_ESP_WIFI_ENTERPRISE_SUPPORT
    doc["features"]["enterprisePassword"] = true;
#else
    doc["features"]["enterprisePassword"] = false;
#endif
    JsonArray types = doc["capabilities"]["cardTypes"].to<JsonArray>();
    types.add("open_recall");
    types.add("cloze");
    types.add("multiple_choice");
    types.add("true_false");
    types.add("application");
    JsonArray formats = doc["capabilities"]["contentFormats"].to<JsonArray>();
    formats.add("plain");
    doc["capabilities"]["maxOptions"] = Config::MAX_CARD_OPTIONS;
    doc["capabilities"]["maxPayloadBytes"] = 120000;
    doc["capabilities"]["display"]["technology"] = "epaper";
    doc["capabilities"]["display"]["width"] = 960;
    doc["capabilities"]["display"]["height"] = 540;
    doc["capabilities"]["input"]["primary"] = "touch";
    doc["capabilities"]["input"]["typedRecall"] = false;
    doc["capabilities"]["input"]["touch"] = Config::TOUCH_ENABLED;
    doc["capabilities"]["storage"]["microSD"] = true;
    String body;
    serializeJson(doc, body);
    server_.send(200, "application/json", body);
}

void LocalLinkService::setClock() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    JsonDocument doc;
    if (deserializeJson(doc, server_.arg("plain"))) {
        server_.send(400, "application/json", "{\"error\":\"invalid_json\"}");
        return;
    }
    const uint32_t epoch = doc["epochSeconds"] | 0U;
    if (epoch < 1700000000U) {
        server_.send(422, "application/json", "{\"error\":\"invalid_epoch\"}");
        return;
    }
    clock_.setFromEpoch(epoch);
    server_.send(200, "application/json", "{\"ok\":true}");
}

void LocalLinkService::provision() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    if (!requireMode(LocalLinkMode::Provisioning)) return;

    JsonDocument doc;
    if (deserializeJson(doc, server_.arg("plain")) ||
        String(doc["schema"] | "") != "mnemos.provision/v2") {
        server_.send(400, "application/json", "{\"error\":\"invalid_provision_schema\"}");
        return;
    }

    JsonObjectConst source = doc["networkProfile"].as<JsonObjectConst>();
    NetworkProfile profile;
    profile.id = source["id"] | "";
    profile.ssid = source["ssid"] | "";
    profile.enabled = source["settings"]["enabled"] | true;
    profile.autoConnect = source["settings"]["autoConnect"] | true;
    profile.priority = source["settings"]["priority"] | 50;
    profile.security = source["security"]["type"] | "";
    if (profile.security == "personal") {
        profile.password = source["security"]["password"] | "";
    } else if (profile.security == "enterprise-password") {
        profile.identity = source["security"]["eap"]["identity"] | "";
        profile.username = source["security"]["eap"]["username"] | "";
        profile.password = source["security"]["eap"]["password"] | "";
    }

    const String backend = doc["backend"]["baseUrl"] | "";
    const String deviceToken = doc["backend"]["deviceToken"] | "";
    const uint32_t interval = doc["syncIntervalSeconds"] | 1800U;
    const uint32_t epoch = doc["clockEpochSeconds"] | 0U;
    if (epoch >= 1700000000U) clock_.setFromEpoch(epoch);

    if (!network_.storeProfile(profile, backend, deviceToken, interval)) {
        server_.send(422, "application/json", "{\"error\":\"" + network_.lastError() + "\"}");
        return;
    }
    provisioned_ = true;
    Serial.printf("[local-link] perfil %s gravado; backend=%s\n",
                  profile.ssid.c_str(),
                  backend.length() > 0 ? backend.c_str() : "(mantido)");
    server_.send(200, "application/json", "{\"ok\":true,\"stored\":true}");
}

void LocalLinkService::networkStatus() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    JsonDocument doc;
    doc["enabled"] = network_.enabled();
    doc["connected"] = network_.connected();
    doc["ssid"] = network_.ssid();
    doc["ip"] = network_.ip();
    doc["knownNetworks"] = network_.profileCount();
    doc["lastError"] = network_.lastError();
    String body;
    serializeJson(doc, body);
    server_.send(200, "application/json", body);
}

void LocalLinkService::importLibrary() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    if (!requireMode(LocalLinkMode::DirectSync)) return;
    String error;
    if (!SyncCodec::applySnapshotV2(server_.arg("plain"), cards_, states_, maxCards_,
                                    cardCount_, storage_, error)) {
        server_.send(422, "application/json", "{\"error\":\"" + error + "\"}");
        return;
    }
    libraryUpdated_ = true;
    server_.send(200, "application/json", "{\"ok\":true,\"cardCount\":" + String(cardCount_) + "}");
}

void LocalLinkService::exportReviews() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    if (!requireMode(LocalLinkMode::DirectSync)) return;
    server_.send(200, "application/json", SyncCodec::buildReviewBatchV2(storage_));
}

void LocalLinkService::acknowledgeReviews() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    if (!requireMode(LocalLinkMode::DirectSync)) return;

    // Confirmação seletiva: {"ids":[...]} remove só o que o app gravou.
    // Sem corpo, mantém o comportamento antigo (apaga o outbox inteiro).
    JsonDocument body;
    const String raw = server_.arg("plain");
    if (raw.length() > 0 && !deserializeJson(body, raw) && body["ids"].is<JsonArrayConst>()) {
        std::vector<String> lines;
        storage_.loadReviewOutboxLines(lines);
        std::vector<String> keep;
        uint16_t removed = 0;
        for (const String& line : lines) {
            JsonDocument row;
            String id;
            if (!deserializeJson(row, line)) id = row["id"] | "";
            bool acknowledged = false;
            for (JsonVariantConst value : body["ids"].as<JsonArrayConst>()) {
                if (id.length() > 0 && id == value.as<const char*>()) {
                    acknowledged = true;
                    break;
                }
            }
            if (acknowledged) ++removed;
            else keep.push_back(line);
        }
        if (!storage_.rewriteReviewOutbox(keep)) {
            server_.send(500, "application/json", "{\"error\":\"storage_failed\"}");
            return;
        }
        server_.send(200, "application/json",
                     "{\"ok\":true,\"removed\":" + String(removed) + ",\"pending\":" + String(keep.size()) + "}");
        return;
    }

    if (!storage_.clearReviewOutbox()) {
        server_.send(500, "application/json", "{\"error\":\"storage_failed\"}");
        return;
    }
    server_.send(200, "application/json", "{\"ok\":true}");
}

void LocalLinkService::exportMetrics() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    if (!requireMode(LocalLinkMode::DirectSync)) return;
    server_.send(200, "application/json", metrics_.buildJson());
}

void LocalLinkService::complete() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    server_.send(200, "application/json", "{\"ok\":true}");
    completeRequested_ = true;
}
