#include "backend_sync_service.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <WiFiClient.h>
#include <WiFiClientSecure.h>
#include <new>

#include "config.h"
#include "network_service.h"
#include "storage.h"

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
    if (method == "GET") {
        status = http.GET();
    } else {
        status = http.POST(body);
    }
    if (status > 0) response = http.getString();
    http.end();
    return status > 0;
}

bool BackendSyncService::pushReviews() {
    const String ndjson = storage_.reviewsNdjson();
    if (ndjson.length() == 0) return true;

    JsonDocument batch;
    batch["schema"] = "mnemos.review-batch/v1";
    JsonArray reviews = batch["reviews"].to<JsonArray>();

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
    if (reviews.size() == 0) return true;

    String body;
    serializeJson(batch, body);
    int status = 0;
    String response;
    if (!request("POST", "/v1/terminal/reviews", body, status, response)) return false;
    if (status < 200 || status >= 300) {
        Serial.printf("[backend] reviews HTTP %d\n", status);
        return false;
    }
    return storage_.clearReviews();
}

bool BackendSyncService::pullSnapshot() {
    int status = 0;
    String body;
    const String path = "/v1/terminal/snapshot?limit=" + String(maxCards_);
    if (!request("GET", path, "", status, body)) return false;
    if (status < 200 || status >= 300) {
        Serial.printf("[backend] snapshot HTTP %d\n", status);
        return false;
    }

    JsonDocument doc;
    if (deserializeJson(doc, body)) return false;
    if (String(doc["schema"] | "") != "mnemos.sync/v1") return false;
    JsonArrayConst items = doc["cards"].as<JsonArrayConst>();
    if (items.size() > maxCards_) return false;

    auto deckName = [&](const String& deckId) -> String {
        for (JsonObjectConst deck : doc["decks"].as<JsonArrayConst>()) {
            if (String(deck["id"] | "") == deckId) return String(deck["name"] | "");
        }
        return String();
    };

    // Validate the complete snapshot before mutating the active library.
    for (JsonObjectConst item : items) {
        const String id = item["id"] | "";
        const String deckId = item["deckId"] | "";
        const String type = item["type"] | "";
        const String promptFormat = item["content"]["prompt"]["format"] | "";
        const String answerFormat = item["content"]["answer"]["format"] | "";
        const String prompt = item["content"]["prompt"]["text"] | "";
        const String answer = item["content"]["answer"]["text"] | "";
        if (String(item["schema"] | "") != "mnemos.card/v1" ||
            id.length() == 0 || id.length() > 36 || deckId.length() == 0 ||
            prompt.length() == 0 || answer.length() == 0 || deckName(deckId).length() == 0) {
            return false;
        }
        if (type != "basic" || promptFormat != "plain" || answerFormat != "plain") return false;
    }

    // Build the replacement in temporary arrays first. The live library is
    // changed only after the complete snapshot has validated and persisted.
    CardDefinition* nextCards = new (std::nothrow) CardDefinition[maxCards_];
    CardState* nextStates = new (std::nothrow) CardState[maxCards_];
    if (nextCards == nullptr || nextStates == nullptr) {
        delete[] nextCards;
        delete[] nextStates;
        return false;
    }
    const size_t oldCount = cardCount_;

    size_t next = 0;
    for (JsonObjectConst item : items) {
        const String id = item["id"] | "";
        nextCards[next].id = id;
        nextCards[next].deckId = item["deckId"] | "";
        nextCards[next].deck = deckName(nextCards[next].deckId);
        nextCards[next].type = "basic";
        nextCards[next].format = "plain";
        nextCards[next].question = item["content"]["prompt"]["text"] | "";
        nextCards[next].answer = item["content"]["answer"]["text"] | "";
        nextCards[next].revision = item["metadata"]["revision"] | 1ULL;

        CardState state{};
        state.id = id;
        for (size_t old = 0; old < oldCount; ++old) {
            if (states_[old].id == id) {
                state = states_[old];
                break;
            }
        }
        nextStates[next] = state;
        ++next;
    }

    // State is written first. If library persistence then fails, old library
    // loading ignores state rows for unknown cards. This avoids exposing a
    // half-applied snapshot in RAM while keeping crash recovery conservative.
    if (!storage_.saveStates(nextStates, next) ||
        !storage_.saveLibrary(nextCards, nextStates, next)) {
        delete[] nextCards;
        delete[] nextStates;
        return false;
    }

    for (size_t i = 0; i < next; ++i) {
        cards_[i] = nextCards[i];
        states_[i] = nextStates[i];
    }
    cardCount_ = next;
    delete[] nextCards;
    delete[] nextStates;
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
    doc["card_count"] = cardCount_;
    doc["max_cards"] = maxCards_;
    doc["connectivity"] = network_.connected() ? "wifi" : "offline";
    doc["wifi_ssid"] = network_.ssid();
    doc["library_revision"] = revision;
    doc["synced"] = synced;
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
    const bool reviewsOk = pushReviews();
    const bool snapshotOk = pullSnapshot();
    const bool synced = reviewsOk && snapshotOk;
    const bool statusOk = reportStatus(synced);
    Serial.printf("[backend] sync reviews=%d snapshot=%d status=%d\n", reviewsOk, snapshotOk, statusOk);
    return synced;
}
