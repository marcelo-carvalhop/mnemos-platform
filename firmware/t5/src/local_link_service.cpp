#include "local_link_service.h"

#include <ArduinoJson.h>
#include <WiFi.h>
#include <esp_system.h>

#include "config.h"
#include "metrics_service.h"
#include "network_service.h"
#include "storage.h"
#include "sync_codec.h"
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
    if (active_) return mode_ == mode;

    mode_ = mode;
    const uint64_t mac = ESP.getEfuseMac();
    const String suffix = makeHex(static_cast<uint32_t>(mac & 0xFFFFFFU), 6);
    deviceId_ = "T5S3-" + suffix;
    ssid_ = "MNEMOS-" + suffix;
    password_ = "MN" + makeHex(esp_random(), 10);
    token_ = makeHex(esp_random(), 8) + makeHex(esp_random(), 8);

    network_.prepareProvisioning();
    const IPAddress localIp(192, 168, 4, 1);
    const IPAddress gateway(192, 168, 4, 1);
    const IPAddress subnet(255, 255, 255, 0);
    if (!WiFi.softAPConfig(localIp, gateway, subnet) ||
        !WiFi.softAP(ssid_.c_str(), password_.c_str(), 6, 0, 1)) {
        Serial.println("[local-link] falha ao iniciar SoftAP");
        network_.finishProvisioning();
        return false;
    }

    const String modeText = mode_ == LocalLinkMode::Provisioning ? "provision" : "sync";
    qrPayload_ = "mnemos://local?v=" + String(Config::DEVICE_PROTOCOL_VERSION) +
                 "&mode=" + modeText +
                 "&id=" + deviceId_ +
                 "&ssid=" + ssid_ +
                 "&pwd=" + password_ +
                 "&host=192.168.4.1" +
                 "&token=" + token_ +
                 "&model=" + String(Config::DEVICE_MODEL) +
                 "&fw=" + String(Config::APP_VERSION);

    if (!routesConfigured_) {
        configureRoutes();
        routesConfigured_ = true;
    }
    server_.begin();
    active_ = true;
    completeRequested_ = false;
    libraryUpdated_ = false;
    startedAtMs_ = millis();

    Serial.printf("[local-link] %s iniciado: %s em %s\n",
                  modeText.c_str(), ssid_.c_str(), WiFi.softAPIP().toString().c_str());
    return true;
}

void LocalLinkService::stop() {
    if (!active_) return;
    server_.stop();
    network_.finishProvisioning();
    active_ = false;
    completeRequested_ = false;
    Serial.println("[local-link] encerrado");
}

void LocalLinkService::loop() {
    if (!active_) return;
    server_.handleClient();
    if (completeRequested_) {
        delay(40);
        stop();
        return;
    }
    if (millis() - startedAtMs_ > static_cast<uint32_t>(Config::LOCAL_LINK_TIMEOUT_SECONDS) * 1000U) {
        stop();
    }
}

bool LocalLinkService::consumeLibraryUpdated() {
    const bool value = libraryUpdated_;
    libraryUpdated_ = false;
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
    doc["features"]["wifiProvisioning"] = true;
    doc["features"]["knownNetworks"] = true;
    doc["features"]["directWifiSync"] = true;
    doc["features"]["backendSync"] = true;
    doc["features"]["metrics"] = true;
    doc["features"]["bleSync"] = false;
    doc["features"]["keyboard"] = true;
    doc["features"]["touch"] = Config::TOUCH_ENABLED;
    doc["features"]["rtc"] = true;
    doc["features"]["sdStorage"] = false;
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
    doc["capabilities"]["input"]["primary"] = "cardkb";
    doc["capabilities"]["input"]["typedRecall"] = true;
    doc["capabilities"]["input"]["touch"] = Config::TOUCH_ENABLED;
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
