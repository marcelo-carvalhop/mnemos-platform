#include "network_service.h"

#include <WiFi.h>

void NetworkService::load() {
    enabled_ = preferences_.getBool("enabled", false);
    ssid_ = preferences_.getString("ssid", "");
    password_ = preferences_.getString("password", "");
    backendUrl_ = preferences_.getString("backend", "");
    deviceToken_ = preferences_.getString("token", "");
    syncIntervalSeconds_ = preferences_.getULong("sync", 1800U);
    if (syncIntervalSeconds_ < 300U) syncIntervalSeconds_ = 300U;
}

void NetworkService::save() {
    preferences_.putBool("enabled", enabled_);
    preferences_.putString("ssid", ssid_);
    preferences_.putString("password", password_);
    preferences_.putString("backend", backendUrl_);
    preferences_.putString("token", deviceToken_);
    preferences_.putULong("sync", syncIntervalSeconds_);
}

void NetworkService::begin() {
    preferences_.begin("mnemos-net", false);
    load();
    if (enabled_ && hasCredentials()) {
        reconnect(8000U);
    } else if (!enabled_) {
        WiFi.mode(WIFI_OFF);
    }
}

void NetworkService::prepareProvisioning() {
    WiFi.mode(WIFI_AP_STA);
}

void NetworkService::finishProvisioning() {
    WiFi.softAPdisconnect(true);
    if (!enabled_) {
        WiFi.mode(WIFI_OFF);
    } else {
        WiFi.mode(WIFI_STA);
    }
}

bool NetworkService::configure(const String& ssid,
                               const String& password,
                               const String& backendUrl,
                               const String& deviceToken,
                               uint32_t syncIntervalSeconds) {
    if (ssid.length() == 0 || ssid.length() > 32) {
        lastError_ = "invalid_ssid";
        return false;
    }
    if (password.length() > 63 || (password.length() > 0 && password.length() < 8)) {
        lastError_ = "invalid_password";
        return false;
    }
    const bool hasBackend = backendUrl.length() > 0;
    const bool hasToken = deviceToken.length() > 0;
    if (hasBackend != hasToken ||
        (hasBackend && !backendUrl.startsWith("http://") && !backendUrl.startsWith("https://"))) {
        lastError_ = "invalid_backend";
        return false;
    }
    ssid_ = ssid;
    password_ = password;
    backendUrl_ = backendUrl;
    deviceToken_ = deviceToken;
    syncIntervalSeconds_ = constrain(syncIntervalSeconds, 300U, 86400U);
    enabled_ = true;
    lastError_ = "";
    save();

    WiFi.mode(WIFI_AP_STA);
    WiFi.begin(ssid_.c_str(), password_.c_str());
    lastReconnectAttemptMs_ = millis();
    return true;
}

bool NetworkService::reconnect(uint32_t timeoutMs) {
    if (!enabled_ || !hasCredentials()) return false;
    if (connected()) return true;

    lastError_ = "";
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid_.c_str(), password_.c_str());
    lastReconnectAttemptMs_ = millis();

    const uint32_t started = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - started < timeoutMs) {
        delay(200);
    }
    if (!connected()) {
        lastError_ = "connection_failed";
        return false;
    }
    return true;
}

void NetworkService::disable() {
    enabled_ = false;
    save();
    WiFi.disconnect(false, false);
    WiFi.mode(WIFI_OFF);
    lastError_ = "";
    Serial.println("[wifi] radio desligado pelo usuario");
}

bool NetworkService::enable() {
    enabled_ = true;
    save();
    if (!hasCredentials()) {
        lastError_ = "not_provisioned";
        return false;
    }
    return reconnect();
}

void NetworkService::loop() {
    if (!enabled_ || !hasCredentials() || connected()) return;
    if (millis() - lastReconnectAttemptMs_ < 30000U) return;
    reconnect(1500U);
}

bool NetworkService::connected() const {
    return enabled_ && WiFi.status() == WL_CONNECTED;
}

String NetworkService::ip() const {
    return connected() ? WiFi.localIP().toString() : String();
}
