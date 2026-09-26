#pragma once

#include <Arduino.h>
#include <WebServer.h>
#include "models.h"

class MetricsService;
class NetworkService;
class Storage;
class TimeService;

enum class LocalLinkMode : uint8_t {
    Provisioning = 1,
    DirectSync = 2,
};

class LocalLinkService {
public:
    LocalLinkService(Storage& storage,
                     TimeService& clock,
                     NetworkService& network,
                     MetricsService& metrics,
                     CardDefinition* cards,
                     CardState* states,
                     size_t maxCards,
                     size_t& cardCount);

    bool start(LocalLinkMode mode);
    void stop();
    void loop();

    bool active() const { return active_; }
    LocalLinkMode mode() const { return mode_; }
    bool consumeLibraryUpdated();

    const String& qrPayload() const { return qrPayload_; }
    const String& ssid() const { return ssid_; }
    const String& password() const { return password_; }
    const String& deviceId() const { return deviceId_; }

private:
    Storage& storage_;
    TimeService& clock_;
    NetworkService& network_;
    MetricsService& metrics_;
    CardDefinition* cards_;
    CardState* states_;
    size_t maxCards_;
    size_t& cardCount_;
    WebServer server_{80};

    LocalLinkMode mode_ = LocalLinkMode::Provisioning;
    bool active_ = false;
    bool routesConfigured_ = false;
    bool completeRequested_ = false;
    bool libraryUpdated_ = false;
    uint32_t startedAtMs_ = 0;

    String deviceId_;
    String ssid_;
    String password_;
    String token_;
    String qrPayload_;

    String makeHex(uint32_t value, uint8_t digits) const;
    bool authorized();
    bool requireMode(LocalLinkMode mode);
    void configureRoutes();
    void sendInfo();
    void setClock();
    void provision();
    void networkStatus();
    void importLibrary();
    void exportReviews();
    void acknowledgeReviews();
    void exportMetrics();
    void complete();
};
