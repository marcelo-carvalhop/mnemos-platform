#pragma once

#include <Arduino.h>
#include <WebServer.h>

#include "models.h"

class Storage;
class TimeService;
class NetworkService;

class PairingService {
public:
    PairingService(Storage& storage,
                   TimeService& clock,
                   NetworkService& network,
                   CardDefinition* cards,
                   CardState* states,
                   size_t maxCards,
                   size_t& cardCount);

    bool start();
    void stop();
    void loop();

    bool active() const { return active_; }
    bool consumeLibraryUpdated();

    const String& qrPayload() const { return qrPayload_; }
    const String& ssid() const { return ssid_; }
    const String& password() const { return password_; }
    const String& deviceId() const { return deviceId_; }

private:
    Storage& storage_;
    TimeService& clock_;
    NetworkService& network_;
    CardDefinition* cards_;
    CardState* states_;
    size_t maxCards_;
    size_t& cardCount_;
    WebServer server_{80};

    bool active_ = false;
    bool libraryUpdated_ = false;
    bool routesConfigured_ = false;
    bool completeRequested_ = false;
    uint32_t startedAtMs_ = 0;

    String deviceId_;
    String ssid_;
    String password_;
    String token_;
    String qrPayload_;

    void configureRoutes();
    bool authorized();
    void sendInfo();
    void importLibraryV1();
    void importLibraryV2();
    void exportReviewsV1();
    void exportReviewsV2();
    void acknowledgeReviews();
    void setClock();
    void provision();
    void networkStatus();
    void completePairing();
    String makeHex(uint32_t value, uint8_t digits) const;
};
