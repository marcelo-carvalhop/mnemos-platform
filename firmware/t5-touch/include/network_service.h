#pragma once

#include <Arduino.h>
#include <Preferences.h>

struct NetworkProfile {
    String id;
    String ssid;
    String security = "personal";  // open | personal | enterprise-password
    String password;
    String identity;
    String username;
    bool enabled = true;
    bool autoConnect = true;
    int16_t priority = 50;
    uint16_t failureCount = 0;
};

class NetworkService {
public:
    static constexpr size_t MAX_PROFILES = 8;

    void begin();

    // Legacy v1/v2 provisioning entry point. It becomes a personal/open
    // profile and is retained only for migration.
    bool configure(const String& ssid,
                   const String& password,
                   const String& backendUrl,
                   const String& deviceToken,
                   uint32_t syncIntervalSeconds);

    bool storeProfile(const NetworkProfile& profile,
                      const String& backendUrl,
                      const String& deviceToken,
                      uint32_t syncIntervalSeconds);
    bool forgetProfile(const String& profileId);

    void prepareProvisioning();
    void finishProvisioning();
    bool reconnect(uint32_t timeoutMs = 12000U);
    void disable();
    bool enable();
    void loop();

    bool enabled() const { return enabled_; }
    bool provisioning() const { return provisioning_; }
    bool connected() const;
    bool hasCredentials() const { return profileCount_ > 0; }
    const String& ssid() const { return connectedSsid_; }
    const String& backendUrl() const { return backendUrl_; }
    const String& deviceToken() const { return deviceToken_; }
    const String& lastError() const { return lastError_; }
    uint32_t syncIntervalSeconds() const { return syncIntervalSeconds_; }
    String ip() const;

    size_t profileCount() const { return profileCount_; }
    const NetworkProfile* profileAt(size_t index) const {
        return index < profileCount_ ? &profiles_[index] : nullptr;
    }

private:
    Preferences preferences_;
    NetworkProfile profiles_[MAX_PROFILES];
    size_t profileCount_ = 0;
    String backendUrl_;
    String deviceToken_;
    String connectedSsid_;
    String lastError_;
    bool enabled_ = true;
    bool provisioning_ = false;
    uint32_t syncIntervalSeconds_ = 1800U;
    uint32_t lastReconnectAttemptMs_ = 0;
    uint32_t reconnectBackoffMs_ = 30000U;

    void load();
    void save();
    int findProfile(const String& id) const;
    int chooseVisibleProfile();
    bool connectProfile(NetworkProfile& profile, uint32_t timeoutMs);
    bool validProfile(const NetworkProfile& profile) const;
};
