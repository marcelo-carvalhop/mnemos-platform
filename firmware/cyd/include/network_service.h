#pragma once

#include <Arduino.h>
#include <Preferences.h>

class NetworkService {
public:
    void begin();
    bool configure(const String& ssid,
                   const String& password,
                   const String& backendUrl,
                   const String& deviceToken,
                   uint32_t syncIntervalSeconds);
    void prepareProvisioning();
    void finishProvisioning();
    bool reconnect(uint32_t timeoutMs = 12000U);
    void disable();
    bool enable();
    void loop();

    bool enabled() const { return enabled_; }
    bool connected() const;
    bool hasCredentials() const { return ssid_.length() > 0; }
    const String& ssid() const { return ssid_; }
    const String& backendUrl() const { return backendUrl_; }
    const String& deviceToken() const { return deviceToken_; }
    const String& lastError() const { return lastError_; }
    uint32_t syncIntervalSeconds() const { return syncIntervalSeconds_; }
    String ip() const;

private:
    Preferences preferences_;
    String ssid_;
    String password_;
    String backendUrl_;
    String deviceToken_;
    String lastError_;
    bool enabled_ = true;
    uint32_t syncIntervalSeconds_ = 1800U;
    uint32_t lastReconnectAttemptMs_ = 0;

    void load();
    void save();
};
