#include "ble_sync_service.h"

#include <ArduinoJson.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <cstring>
#include <esp_system.h>
#include <new>

#include "config.h"
#include "storage.h"

namespace {
constexpr char SERVICE_UUID[] = "6d6e656d-6f73-4001-8000-000000000001";
constexpr char CONTROL_UUID[] = "6d6e656d-6f73-4001-8000-000000000002";
constexpr char DATA_UUID[] = "6d6e656d-6f73-4001-8000-000000000003";
constexpr char STATUS_UUID[] = "6d6e656d-6f73-4001-8000-000000000004";
constexpr size_t MAX_BLE_SNAPSHOT = 90000U;
constexpr size_t NOTIFY_CHUNK = 20U;  // safe even before a larger ATT MTU is negotiated
constexpr uint32_t BLE_WINDOW_MS = 5U * 60U * 1000U;
}

class BleSyncService::ServerCallbacks : public BLEServerCallbacks {
public:
    explicit ServerCallbacks(BleSyncService& owner) : owner_(owner) {}
    void onConnect(BLEServer*) override { owner_.connected_ = true; }
    void onDisconnect(BLEServer*) override {
        owner_.connected_ = false;
        if (owner_.active_ && !owner_.stopRequested_) BLEDevice::startAdvertising();
    }
private:
    BleSyncService& owner_;
};

class BleSyncService::ControlCallbacks : public BLECharacteristicCallbacks {
public:
    explicit ControlCallbacks(BleSyncService& owner) : owner_(owner) {}
    void onWrite(BLECharacteristic* characteristic) override {
        const std::string raw = characteristic->getValue();
        owner_.handleControl(String(raw.c_str()));
    }
private:
    BleSyncService& owner_;
};

class BleSyncService::DataCallbacks : public BLECharacteristicCallbacks {
public:
    explicit DataCallbacks(BleSyncService& owner) : owner_(owner) {}
    void onWrite(BLECharacteristic* characteristic) override {
        const std::string raw = characteristic->getValue();
        owner_.handleData(reinterpret_cast<const uint8_t*>(raw.data()), raw.size());
    }
private:
    BleSyncService& owner_;
};

BleSyncService::BleSyncService(Storage& storage,
                               CardDefinition* cards,
                               CardState* states,
                               size_t maxCards,
                               size_t& cardCount)
    : storage_(storage), cards_(cards), states_(states), maxCards_(maxCards), cardCount_(cardCount) {}

String BleSyncService::makeDeviceId() const {
    const uint64_t mac = ESP.getEfuseMac();
    String suffix(static_cast<uint32_t>(mac & 0xFFFFFFU), HEX);
    suffix.toUpperCase();
    while (suffix.length() < 6) suffix = "0" + suffix;
    if (suffix.length() > 6) suffix = suffix.substring(suffix.length() - 6);
    return "CYD-" + suffix;
}

bool BleSyncService::start() {
    if (active_) return true;
    deviceId_ = makeDeviceId();
    const String name = "MNEMOS-" + deviceId_;

    BLEDevice::init(name.c_str());
    server_ = BLEDevice::createServer();
    server_->setCallbacks(new ServerCallbacks(*this));
    BLEService* service = server_->createService(SERVICE_UUID);

    control_ = service->createCharacteristic(
        CONTROL_UUID,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_READ);
    data_ = service->createCharacteristic(
        DATA_UUID,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
    status_ = service->createCharacteristic(
        STATUS_UUID,
        BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);

    control_->setCallbacks(new ControlCallbacks(*this));
    data_->setCallbacks(new DataCallbacks(*this));
    data_->addDescriptor(new BLE2902());
    status_->addDescriptor(new BLE2902());

    service->start();
    BLEAdvertising* advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(SERVICE_UUID);
    advertising->setScanResponse(true);
    advertising->start();

    active_ = true;
    connected_ = false;
    receivingSnapshot_ = false;
    stopRequested_ = false;
    startedAtMs_ = millis();
    snapshotBuffer_ = "";
    Serial.printf("[ble] sync ativo como %s\n", name.c_str());
    return true;
}

void BleSyncService::stop() {
    if (!active_) return;
    stopRequested_ = true;
    BLEDevice::getAdvertising()->stop();
    BLEDevice::deinit(true);
    server_ = nullptr;
    control_ = nullptr;
    data_ = nullptr;
    status_ = nullptr;
    connected_ = false;
    active_ = false;
    receivingSnapshot_ = false;
    snapshotBuffer_ = "";
    expectedSnapshotBytes_ = 0;
    Serial.println("[ble] sync encerrado");
}

void BleSyncService::loop() {
    if (!active_) return;
    if (stopRequested_ || (!connected_ && millis() - startedAtMs_ > BLE_WINDOW_MS)) stop();
}

bool BleSyncService::consumeLibraryUpdated() {
    const bool value = libraryUpdated_;
    libraryUpdated_ = false;
    return value;
}

void BleSyncService::notifyStatus(const String& event, int value, const String& message) {
    if (status_ == nullptr) return;
    JsonDocument doc;
    doc["event"] = event;
    if (value >= 0) {
        if (event == "snapshot_committed") doc["cards"] = value;
        else if (event == "reviews_end") doc["count"] = value;
        else doc["value"] = value;
    }
    if (message.length() > 0) doc["message"] = message;
    String body;
    serializeJson(doc, body);
    status_->setValue(body.c_str());
    status_->notify();
}

void BleSyncService::handleControl(const String& value) {
    JsonDocument doc;
    if (deserializeJson(doc, value)) {
        notifyStatus("error", -1, "invalid_control_json");
        return;
    }
    const String op = doc["op"] | "";
    if (op == "begin") {
        const size_t size = doc["size"] | 0U;
        if (size == 0 || size > MAX_BLE_SNAPSHOT) {
            notifyStatus("error", -1, "invalid_snapshot_size");
            return;
        }
        expectedSnapshotBytes_ = size;
        snapshotBuffer_ = "";
        if (!snapshotBuffer_.reserve(size + 1)) {
            notifyStatus("error", -1, "out_of_memory");
            return;
        }
        receivingSnapshot_ = true;
        notifyStatus("ready");
        return;
    }
    if (op == "commit") {
        if (!receivingSnapshot_ || snapshotBuffer_.length() != expectedSnapshotBytes_) {
            notifyStatus("error", -1, "incomplete_snapshot");
            return;
        }
        receivingSnapshot_ = false;
        if (!commitSnapshot()) {
            notifyStatus("error", -1, "snapshot_rejected");
            return;
        }
        notifyStatus("snapshot_committed", static_cast<int>(cardCount_));
        return;
    }
    if (op == "reviews") {
        sendReviews();
        return;
    }
    if (op == "reviews_ack") {
        if (!storage_.clearReviews()) {
            notifyStatus("error", -1, "review_ack_failed");
            return;
        }
        notifyStatus("done");
        stopRequested_ = true;
        return;
    }
    if (op == "cancel") {
        stopRequested_ = true;
        return;
    }
    notifyStatus("error", -1, "unsupported_operation");
}

void BleSyncService::handleData(const uint8_t* data, size_t length) {
    if (!receivingSnapshot_ || data == nullptr || length == 0) return;
    if (snapshotBuffer_.length() + length > expectedSnapshotBytes_ ||
        snapshotBuffer_.length() + length > MAX_BLE_SNAPSHOT) {
        receivingSnapshot_ = false;
        snapshotBuffer_ = "";
        notifyStatus("error", -1, "snapshot_overflow");
        return;
    }
    for (size_t i = 0; i < length; ++i) snapshotBuffer_ += static_cast<char>(data[i]);
}

bool BleSyncService::commitSnapshot() {
    JsonDocument doc;
    if (deserializeJson(doc, snapshotBuffer_)) return false;
    if (String(doc["schema"] | "") != "mnemos.sync/v1") return false;
    JsonArrayConst items = doc["cards"].as<JsonArrayConst>();
    if (items.size() > maxCards_) return false;

    auto deckName = [&](const String& deckId) -> String {
        for (JsonObjectConst deck : doc["decks"].as<JsonArrayConst>()) {
            if (String(deck["id"] | "") == deckId) return String(deck["name"] | "");
        }
        return String();
    };

    for (JsonObjectConst item : items) {
        const String id = item["id"] | "";
        const String deckId = item["deckId"] | "";
        const String type = item["type"] | "";
        const String promptFormat = item["content"]["prompt"]["format"] | "";
        const String answerFormat = item["content"]["answer"]["format"] | "";
        const String prompt = item["content"]["prompt"]["text"] | "";
        const String answer = item["content"]["answer"]["text"] | "";
        if (String(item["schema"] | "") != "mnemos.card/v1" ||
            id.length() == 0 || id.length() > 64 || deckId.length() == 0 ||
            prompt.length() == 0 || answer.length() == 0 || deckName(deckId).length() == 0) return false;
        if (type != "basic" || promptFormat != "plain" || answerFormat != "plain") return false;
    }

    CardDefinition* nextCards = new (std::nothrow) CardDefinition[maxCards_];
    CardState* nextStates = new (std::nothrow) CardState[maxCards_];
    if (nextCards == nullptr || nextStates == nullptr) {
        delete[] nextCards;
        delete[] nextStates;
        return false;
    }

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
        for (JsonObjectConst row : doc["states"].as<JsonArrayConst>()) {
            if (String(row["cardId"] | "") != id) continue;
            state.dueAt = row["dueAt"] | 0U;
            state.intervalSeconds = row["intervalSeconds"] | 0U;
            state.repetitions = row["repetitions"] | 0U;
            state.lapses = row["lapses"] | 0U;
            state.lastRating = row["lastRating"] | 0U;
            break;
        }
        nextStates[next] = state;
        ++next;
    }

    const bool stored = storage_.saveStates(nextStates, next) &&
                        storage_.saveLibrary(nextCards, nextStates, next);
    if (!stored) {
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
    snapshotBuffer_ = "";
    expectedSnapshotBytes_ = 0;
    return true;
}

void BleSyncService::sendReviews() {
    if (data_ == nullptr || status_ == nullptr) return;
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
    notifyStatus("reviews_begin", static_cast<int>(body.length()));
    for (size_t offset = 0; offset < body.length(); offset += NOTIFY_CHUNK) {
        const size_t length = min(NOTIFY_CHUNK, body.length() - offset);
        uint8_t chunk[NOTIFY_CHUNK];
        std::memcpy(chunk, body.c_str() + offset, length);
        data_->setValue(chunk, length);
        data_->notify();
        delay(12);
    }
    notifyStatus("reviews_end", static_cast<int>(reviews.size()));
}
