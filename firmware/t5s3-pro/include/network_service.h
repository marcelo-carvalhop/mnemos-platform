#pragma once

#include <Arduino.h>
#include <Preferences.h>
#include "config.h"

struct NetworkScanResult {
    String ssid;
    int32_t rssi = -127;
    bool open = false;
    bool enterprise = false;
    bool known = false;
};

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

enum class NetworkAsyncState : uint8_t {
    Idle = 0,
    Scanning,
    Connecting,
};

class NetworkService {
public:
    static constexpr size_t MAX_PROFILES = 8;
    static constexpr size_t MAX_SCAN_RESULTS = 12;

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

    size_t scanVisible(
        NetworkScanResult* results,
        size_t maxResults);

    bool connectSavedSsid(
        const String& ssid,
        uint32_t timeoutMs = 12000U);

    bool connectAndStore(
        const String& ssid,
        const String& password,
        bool openNetwork,
        uint32_t timeoutMs = 12000U);

    // Touch-first non-blocking API.
    bool startScan();
    bool consumeScanResults(
        NetworkScanResult* results,
        size_t maxResults,
        size_t& count);

    bool startConnectSavedSsidAsync(
        const String& ssid,
        uint32_t timeoutMs = Config::WIFI_CONNECT_TIMEOUT_MS);

    bool startConnectAndStoreAsync(
        const String& ssid,
        const String& password,
        bool openNetwork,
        uint32_t timeoutMs = Config::WIFI_CONNECT_TIMEOUT_MS);

    bool consumeConnectionResult(
        bool& success,
        String& ssid,
        String& error);

    bool busy() const {
        return asyncState_ != NetworkAsyncState::Idle;
    }

    void suspendForSleep();
    void forceRadioOff();
    void resumeAfterSleep();

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
    uint32_t reconnectBackoffMs_ = Config::WIFI_RECONNECT_INITIAL_BACKOFF_MS;

    NetworkAsyncState asyncState_ = NetworkAsyncState::Idle;
    uint32_t asyncStartedMs_ = 0;
    uint32_t asyncTimeoutMs_ = 0;
    int asyncProfileIndex_ = -1;
    bool asyncNotify_ = false;

    NetworkScanResult asyncScanResults_[MAX_SCAN_RESULTS];
    size_t asyncScanCount_ = 0;
    bool scanResultReady_ = false;

    bool connectionResultReady_ = false;
    bool connectionResultSuccess_ = false;
    String connectionResultSsid_;
    String connectionResultError_;

    void load();
    void save();
    int findProfile(const String& id) const;
    int findProfileBySsid(const String& ssid) const;
    String profileIdForSsid(const String& ssid) const;
    int chooseVisibleProfile();
    int bestEnabledProfile() const;
    bool connectProfile(NetworkProfile& profile, uint32_t timeoutMs);
    bool beginAsyncConnection(
        int profileIndex,
        bool notify,
        uint32_t timeoutMs);
    void finishAsyncConnection(
        bool success,
        const String& error);
    void finishAsyncScan(int found);
    bool validProfile(const NetworkProfile& profile) const;
};
