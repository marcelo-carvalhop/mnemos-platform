#include "pairing_service.h"

#include <ArduinoJson.h>
#include <WiFi.h>
#include <esp_system.h>

#include "config.h"
#include "network_service.h"
#include "storage.h"
#include "time_service.h"

PairingService::PairingService(Storage& storage,
                               TimeService& clock,
                               NetworkService& network,
                               CardDefinition* cards,
                               CardState* states,
                               size_t maxCards,
                               size_t& cardCount)
    : storage_(storage),
      clock_(clock),
      network_(network),
      cards_(cards),
      states_(states),
      maxCards_(maxCards),
      cardCount_(cardCount) {}

String PairingService::makeHex(uint32_t value, uint8_t digits) const {
    String result(value, HEX);
    result.toUpperCase();
    while (result.length() < digits) result = "0" + result;
    if (result.length() > digits) result = result.substring(result.length() - digits);
    return result;
}

bool PairingService::start() {
    if (active_) return true;

    const uint64_t mac = ESP.getEfuseMac();
    const String suffix = makeHex(static_cast<uint32_t>(mac & 0xFFFFFFU), 6);
    deviceId_ = "CYD-" + suffix;
    ssid_ = "MNEMOS-" + suffix;
    password_ = "M" + makeHex(esp_random(), 7);
    token_ = makeHex(esp_random(), 8) + makeHex(esp_random(), 8);

    network_.prepareProvisioning();
    if (!WiFi.softAP(ssid_.c_str(), password_.c_str())) {
        Serial.println("[pair] falha ao iniciar SoftAP");
        return false;
    }

    qrPayload_ = "mnemos://pair?v=" + String(Config::DEVICE_PROTOCOL_VERSION) +
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
    startedAtMs_ = millis();
    libraryUpdated_ = false;

    Serial.printf("[pair] AP %s iniciado em %s\n",
                  ssid_.c_str(), WiFi.softAPIP().toString().c_str());
    return true;
}

void PairingService::stop() {
    if (!active_) return;
    server_.stop();
    network_.finishProvisioning();
    active_ = false;
    completeRequested_ = false;
    Serial.println("[pair] provisionamento encerrado");
}

void PairingService::loop() {
    if (!active_) return;
    server_.handleClient();
    if (completeRequested_) {
        delay(40);
        stop();
        return;
    }
    if (millis() - startedAtMs_ > static_cast<uint32_t>(Config::PAIRING_TIMEOUT_SECONDS) * 1000U) {
        stop();
    }
}

bool PairingService::consumeLibraryUpdated() {
    const bool value = libraryUpdated_;
    libraryUpdated_ = false;
    return value;
}

bool PairingService::authorized() {
    return server_.hasArg("token") && server_.arg("token") == token_;
}

void PairingService::configureRoutes() {
    // v2 — canonical Mnemos interoperability protocol.
    server_.on("/v2/info", HTTP_GET, [this]() { sendInfo(); });
    server_.on("/v2/library", HTTP_POST, [this]() { importLibraryV2(); });
    server_.on("/v2/reviews", HTTP_GET, [this]() { exportReviewsV2(); });
    server_.on("/v2/reviews/ack", HTTP_POST, [this]() { acknowledgeReviews(); });
    server_.on("/v2/time", HTTP_POST, [this]() { setClock(); });
    server_.on("/v2/provision", HTTP_POST, [this]() { provision(); });
    server_.on("/v2/network/status", HTTP_GET, [this]() { networkStatus(); });
    server_.on("/v2/pairing/complete", HTTP_POST, [this]() { completePairing(); });

    // v1 is kept during the migration window so an older app can still load
    // the terminal while the v0.3 ecosystem is being rolled out.
    server_.on("/v1/info", HTTP_GET, [this]() { sendInfo(); });
    server_.on("/v1/library", HTTP_POST, [this]() { importLibraryV1(); });
    server_.on("/v1/reviews", HTTP_GET, [this]() { exportReviewsV1(); });
    server_.on("/v1/reviews/ack", HTTP_POST, [this]() { acknowledgeReviews(); });
    server_.on("/v1/time", HTTP_POST, [this]() { setClock(); });

    server_.onNotFound([this]() {
        server_.send(404, "application/json", "{\"error\":\"not_found\"}");
    });
}

void PairingService::sendInfo() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    JsonDocument doc;
    doc["protocol"] = Config::DEVICE_PROTOCOL_VERSION;
    doc["deviceId"] = deviceId_;
    doc["firmware"] = Config::APP_VERSION;
    doc["model"] = Config::DEVICE_MODEL;
    doc["cardCount"] = cardCount_;
    doc["maxCards"] = maxCards_;
    doc["clockTrusted"] = clock_.trusted();
    doc["wifiEnabled"] = network_.enabled();
    doc["wifiConnected"] = network_.connected();
    doc["infrastructureSsid"] = network_.ssid();
    doc["features"]["canonicalSchemas"] = true;
    doc["features"]["wifiProvisioning"] = true;
    doc["features"]["backendSync"] = true;
    doc["features"]["legacyV1"] = true;
    JsonArray cardTypes = doc["capabilities"]["cardTypes"].to<JsonArray>();
    cardTypes.add("basic");
    JsonArray contentFormats = doc["capabilities"]["contentFormats"].to<JsonArray>();
    contentFormats.add("plain");
    doc["capabilities"]["maxPayloadBytes"] = 90000;
    String body;
    serializeJson(doc, body);
    server_.send(200, "application/json", body);
}

void PairingService::importLibraryV1() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    JsonDocument doc;
    if (deserializeJson(doc, server_.arg("plain")) || (doc["schema"] | 0) != 1) {
        server_.send(400, "application/json", "{\"error\":\"unsupported_schema\"}");
        return;
    }
    JsonArrayConst items = doc["cards"].as<JsonArrayConst>();
    if (items.size() == 0 || items.size() > maxCards_) {
        server_.send(422, "application/json", "{\"error\":\"invalid_card_count\"}");
        return;
    }
    size_t next = 0;
    for (JsonObjectConst item : items) {
        const String id = item["id"] | "";
        const String question = item["question"] | "";
        const String answer = item["answer"] | "";
        if (id.length() == 0 || question.length() == 0 || answer.length() == 0) {
            server_.send(422, "application/json", "{\"error\":\"invalid_card\"}");
            return;
        }
        cards_[next].id = id;
        cards_[next].deckId = item["deckId"] | "";
        cards_[next].deck = item["deck"] | "Sem baralho";
        cards_[next].type = "basic";
        cards_[next].format = "plain";
        cards_[next].question = question;
        cards_[next].answer = answer;
        cards_[next].revision = 1;
        states_[next] = CardState{};
        states_[next].id = id;
        states_[next].dueAt = item["dueAt"] | 0U;
        states_[next].intervalSeconds = item["intervalSeconds"] | 0U;
        states_[next].repetitions = item["repetitions"] | 0U;
        states_[next].lapses = item["lapses"] | 0U;
        states_[next].lastRating = item["lastRating"] | 0U;
        ++next;
    }
    cardCount_ = next;
    if (!storage_.saveLibrary(cards_, states_, cardCount_) || !storage_.saveStates(states_, cardCount_)) {
        server_.send(500, "application/json", "{\"error\":\"storage_failed\"}");
        return;
    }
    libraryUpdated_ = true;
    server_.send(200, "application/json", "{\"ok\":true,\"cardCount\":" + String(cardCount_) + "}");
}

void PairingService::importLibraryV2() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    const String body = server_.arg("plain");
    if (body.length() == 0 || body.length() > 90000U) {
        server_.send(413, "application/json", "{\"error\":\"payload_too_large\"}");
        return;
    }
    JsonDocument doc;
    if (deserializeJson(doc, body)) {
        server_.send(400, "application/json", "{\"error\":\"invalid_json\"}");
        return;
    }
    if (String(doc["schema"] | "") != "mnemos.sync/v1") {
        server_.send(400, "application/json", "{\"error\":\"unsupported_schema\"}");
        return;
    }
    JsonArrayConst items = doc["cards"].as<JsonArrayConst>();
    if (items.size() > maxCards_) {
        server_.send(409, "application/json", "{\"error\":\"terminal_capacity_exceeded\"}");
        return;
    }

    auto deckName = [&](const String& deckId) -> String {
        for (JsonObjectConst deck : doc["decks"].as<JsonArrayConst>()) {
            if (String(deck["id"] | "") == deckId) return String(deck["name"] | "");
        }
        return String();
    };

    // Validate the entire snapshot before changing the live in-memory library.
    for (JsonObjectConst item : items) {
        if (String(item["schema"] | "") != "mnemos.card/v1") {
            server_.send(422, "application/json", "{\"error\":\"invalid_card_schema\"}");
            return;
        }
        const String id = item["id"] | "";
        const String deckId = item["deckId"] | "";
        const String type = item["type"] | "";
        const String promptFormat = item["content"]["prompt"]["format"] | "";
        const String answerFormat = item["content"]["answer"]["format"] | "";
        const String prompt = item["content"]["prompt"]["text"] | "";
        const String answer = item["content"]["answer"]["text"] | "";
        if (id.length() == 0 || id.length() > 36 || deckId.length() == 0 ||
            prompt.length() == 0 || answer.length() == 0 || deckName(deckId).length() == 0) {
            server_.send(422, "application/json", "{\"error\":\"invalid_card\"}");
            return;
        }
        if (type != "basic" || promptFormat != "plain" || answerFormat != "plain") {
            server_.send(422, "application/json", "{\"error\":\"unsupported_card_capability\"}");
            return;
        }
    }

    auto incomingState = [&](const String& cardId, CardState& state) {
        for (JsonObjectConst item : doc["states"].as<JsonArrayConst>()) {
            if (String(item["cardId"] | "") != cardId) continue;
            state.id = cardId;
            state.dueAt = item["dueAt"] | 0U;
            state.intervalSeconds = item["intervalSeconds"] | 0U;
            state.repetitions = item["repetitions"] | 0U;
            state.lapses = item["lapses"] | 0U;
            state.lastRating = item["lastRating"] | 0U;
            return;
        }
        state.id = cardId;
    };

    size_t next = 0;
    for (JsonObjectConst item : items) {
        const String id = item["id"] | "";
        cards_[next].id = id;
        cards_[next].deckId = item["deckId"] | "";
        cards_[next].deck = deckName(cards_[next].deckId);
        cards_[next].type = "basic";
        cards_[next].format = "plain";
        cards_[next].question = item["content"]["prompt"]["text"] | "";
        cards_[next].answer = item["content"]["answer"]["text"] | "";
        cards_[next].revision = item["metadata"]["revision"] | 1ULL;
        states_[next] = CardState{};
        incomingState(id, states_[next]);
        ++next;
    }
    cardCount_ = next;
    if (!storage_.saveLibrary(cards_, states_, cardCount_) || !storage_.saveStates(states_, cardCount_)) {
        server_.send(500, "application/json", "{\"error\":\"storage_failed\"}");
        return;
    }
    libraryUpdated_ = true;
    server_.send(200, "application/json", "{\"ok\":true,\"cardCount\":" + String(cardCount_) + "}");
}

void PairingService::exportReviewsV1() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    server_.send(200, "application/x-ndjson; charset=utf-8", storage_.reviewsNdjson());
}

void PairingService::exportReviewsV2() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    JsonDocument batch;
    batch["schema"] = "mnemos.review-batch/v1";
    JsonArray reviews = batch["reviews"].to<JsonArray>();
    const String ndjson = storage_.reviewsNdjson();
    int start = 0;
    while (start < static_cast<int>(ndjson.length())) {
        int end = ndjson.indexOf('\n', start);
        if (end < 0) end = ndjson.length();
        const String line = ndjson.substring(start, end);
        if (line.length() > 0) {
            JsonDocument row;
            if (!deserializeJson(row, line)) reviews.add(row.as<JsonObject>());
        }
        start = end + 1;
    }
    String body;
    serializeJson(batch, body);
    server_.send(200, "application/json", body);
}

void PairingService::acknowledgeReviews() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    if (!storage_.clearReviews()) {
        server_.send(500, "application/json", "{\"error\":\"storage_failed\"}");
        return;
    }
    server_.send(200, "application/json", "{\"ok\":true}");
}

void PairingService::setClock() {
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

void PairingService::provision() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    JsonDocument doc;
    if (deserializeJson(doc, server_.arg("plain")) || String(doc["schema"] | "") != "mnemos.provision/v1") {
        server_.send(400, "application/json", "{\"error\":\"invalid_provision_schema\"}");
        return;
    }
    const String ssid = doc["wifi"]["ssid"] | "";
    const String password = doc["wifi"]["password"] | "";
    const String backend = doc["backend"]["baseUrl"] | "";
    const String deviceToken = doc["backend"]["deviceToken"] | "";
    const uint32_t interval = doc["syncIntervalSeconds"] | 1800U;
    const uint32_t epoch = doc["clockEpochSeconds"] | 0U;
    if (epoch >= 1700000000U) clock_.setFromEpoch(epoch);
    if (!network_.configure(ssid, password, backend, deviceToken, interval)) {
        server_.send(422, "application/json", "{\"error\":\"invalid_network_configuration\"}");
        return;
    }
    networkStatus();
}

void PairingService::networkStatus() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    JsonDocument doc;
    doc["enabled"] = network_.enabled();
    doc["connected"] = network_.connected();
    doc["ssid"] = network_.ssid();
    doc["ip"] = network_.ip();
    doc["lastError"] = network_.lastError();
    String body;
    serializeJson(doc, body);
    server_.send(200, "application/json", body);
}

void PairingService::completePairing() {
    if (!authorized()) {
        server_.send(401, "application/json", "{\"error\":\"unauthorized\"}");
        return;
    }
    server_.send(200, "application/json", "{\"ok\":true}");
    completeRequested_ = true;
}
