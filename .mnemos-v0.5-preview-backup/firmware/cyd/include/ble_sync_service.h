#pragma once

#include <Arduino.h>

#include "models.h"

class BLEServer;
class BLECharacteristic;
class Storage;

class BleSyncService {
public:
    BleSyncService(Storage& storage,
                   CardDefinition* cards,
                   CardState* states,
                   size_t maxCards,
                   size_t& cardCount);

    bool start();
    void stop();
    void loop();

    bool active() const { return active_; }
    bool connected() const { return connected_; }
    bool consumeLibraryUpdated();
    const String& deviceId() const { return deviceId_; }

private:
    Storage& storage_;
    CardDefinition* cards_;
    CardState* states_;
    size_t maxCards_;
    size_t& cardCount_;

    BLEServer* server_ = nullptr;
    BLECharacteristic* control_ = nullptr;
    BLECharacteristic* data_ = nullptr;
    BLECharacteristic* status_ = nullptr;

    bool active_ = false;
    bool connected_ = false;
    bool receivingSnapshot_ = false;
    bool libraryUpdated_ = false;
    bool stopRequested_ = false;
    size_t expectedSnapshotBytes_ = 0;
    String snapshotBuffer_;
    String deviceId_;
    uint32_t startedAtMs_ = 0;

    void handleControl(const String& value);
    void handleData(const uint8_t* data, size_t length);
    bool commitSnapshot();
    void sendReviews();
    void notifyStatus(const String& event, int value = -1, const String& message = "");
    String makeDeviceId() const;

    class ServerCallbacks;
    class ControlCallbacks;
    class DataCallbacks;
};
