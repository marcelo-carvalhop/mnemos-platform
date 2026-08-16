#include "network_service.h"

#include <ArduinoJson.h>
#include <WiFi.h>
#include <WiFiMulti.h>

void NetworkService::load() {
    enabled_ = preferences_.getBool("enabled", false);
    backendUrl_ = preferences_.getString("backend", "");
    deviceToken_ = preferences_.getString("token", "");
    syncIntervalSeconds_ = preferences_.getULong("sync", 1800U);
    if (syncIntervalSeconds_ < 300U) syncIntervalSeconds_ = 300U;

    profileCount_ = 0;
    const String raw = preferences_.getString("profiles", "");
    if (raw.length() > 0) {
        JsonDocument doc;
        if (!deserializeJson(doc, raw)) {
            for (JsonObjectConst item : doc.as<JsonArrayConst>()) {
                if (profileCount_ >= MAX_PROFILES) break;
                NetworkProfile p;
                p.id = item["id"] | "";
                p.ssid = item["ssid"] | "";
                p.security = item["security"] | "personal";
                p.password = item["password"] | "";
                p.identity = item["identity"] | "";
                p.username = item["username"] | "";
                p.enabled = item["enabled"] | true;
                p.autoConnect = item["autoConnect"] | true;
                p.priority = item["priority"] | 50;
                p.failureCount = item["failureCount"] | 0;
                if (validProfile(p)) profiles_[profileCount_++] = p;
            }
        }
    }

    // Migration from the v0.3 single-network layout.
    if (profileCount_ == 0) {
        const String legacySsid = preferences_.getString("ssid", "");
        const String legacyPassword = preferences_.getString("password", "");
        if (legacySsid.length() > 0) {
            NetworkProfile p;
            p.id = "legacy";
            p.ssid = legacySsid;
            p.security = legacyPassword.length() == 0 ? "open" : "personal";
            p.password = legacyPassword;
            profiles_[profileCount_++] = p;
            save();
        }
    }
}

void NetworkService::save() {
    preferences_.putBool("enabled", enabled_);
    preferences_.putString("backend", backendUrl_);
    preferences_.putString("token", deviceToken_);
    preferences_.putULong("sync", syncIntervalSeconds_);

    JsonDocument doc;
    JsonArray rows = doc.to<JsonArray>();
    for (size_t i = 0; i < profileCount_; ++i) {
        const NetworkProfile& p = profiles_[i];
        JsonObject row = rows.add<JsonObject>();
        row["id"] = p.id;
        row["ssid"] = p.ssid;
        row["security"] = p.security;
        row["password"] = p.password;
        row["identity"] = p.identity;
        row["username"] = p.username;
        row["enabled"] = p.enabled;
        row["autoConnect"] = p.autoConnect;
        row["priority"] = p.priority;
        row["failureCount"] = p.failureCount;
    }
    String raw;
    serializeJson(doc, raw);
    preferences_.putString("profiles", raw);
}

bool NetworkService::validProfile(const NetworkProfile& p) const {
    if (p.id.length() == 0 || p.id.length() > 64) return false;
    if (p.ssid.length() == 0 || p.ssid.length() > 32) return false;
    if (p.security == "open") return p.password.length() == 0;
    if (p.security == "personal") {
        return p.password.length() >= 8 && p.password.length() <= 63;
    }
    if (p.security == "enterprise-password") {
        return p.username.length() > 0 && p.password.length() > 0;
    }
    return false;
}

int NetworkService::findProfile(const String& id) const {
    for (size_t i = 0; i < profileCount_; ++i) {
        if (profiles_[i].id == id) return static_cast<int>(i);
    }
    return -1;
}

void NetworkService::begin() {
    preferences_.begin("mnemos-net", false);
    load();
    connectedSsid_ = "";
    WiFi.setAutoReconnect(false);
    if (enabled_ && hasCredentials()) {
        reconnect(8000U);
    } else if (!enabled_) {
        WiFi.mode(WIFI_OFF);
    }
}

void NetworkService::prepareProvisioning() {
    provisioning_ = true;
    connectedSsid_ = "";
    WiFi.disconnect(false, false);
    delay(80);
    WiFi.mode(WIFI_OFF);
    delay(80);
    WiFi.mode(WIFI_AP);
    lastError_ = "";
}

void NetworkService::finishProvisioning() {
    WiFi.softAPdisconnect(true);
    provisioning_ = false;
    connectedSsid_ = "";
    if (!enabled_) {
        WiFi.mode(WIFI_OFF);
        return;
    }
    if (hasCredentials()) {
        reconnect(10000U);
    } else {
        WiFi.mode(WIFI_OFF);
    }
}

bool NetworkService::storeProfile(const NetworkProfile& profile,
                                  const String& backendUrl,
                                  const String& deviceToken,
                                  uint32_t syncIntervalSeconds) {
    if (!validProfile(profile)) {
        lastError_ = "invalid_network_profile";
        return false;
    }
    const bool hasBackend = backendUrl.length() > 0;
    const bool hasToken = deviceToken.length() > 0;
    if (hasBackend != hasToken ||
        (hasBackend && !backendUrl.startsWith("http://") && !backendUrl.startsWith("https://"))) {
        lastError_ = "invalid_backend";
        return false;
    }

    const int existing = findProfile(profile.id);
    if (existing >= 0) {
        profiles_[existing] = profile;
    } else if (profileCount_ < MAX_PROFILES) {
        profiles_[profileCount_++] = profile;
    } else {
        lastError_ = "network_profile_capacity";
        return false;
    }

    backendUrl_ = backendUrl;
    deviceToken_ = deviceToken;
    syncIntervalSeconds_ = constrain(syncIntervalSeconds, 300U, 86400U);
    enabled_ = true;
    lastError_ = "";
    save();
    return true;
}

bool NetworkService::configure(const String& ssid,
                               const String& password,
                               const String& backendUrl,
                               const String& deviceToken,
                               uint32_t syncIntervalSeconds) {
    NetworkProfile p;
    p.id = "legacy-" + ssid;
    p.ssid = ssid;
    p.security = password.length() == 0 ? "open" : "personal";
    p.password = password;
    p.priority = 50;
    return storeProfile(p, backendUrl, deviceToken, syncIntervalSeconds);
}

bool NetworkService::forgetProfile(const String& profileId) {
    const int index = findProfile(profileId);
    if (index < 0) return false;
    for (size_t i = static_cast<size_t>(index); i + 1 < profileCount_; ++i) {
        profiles_[i] = profiles_[i + 1];
    }
    --profileCount_;
    save();
    return true;
}

int NetworkService::chooseVisibleProfile() {
    if (profileCount_ == 0) return -1;
    const int count = WiFi.scanNetworks(false, true, false, 120, 0);
    int best = -1;
    int bestPriority = -32768;
    int bestRssi = -1000;

    if (count > 0) {
        for (size_t p = 0; p < profileCount_; ++p) {
            if (!profiles_[p].enabled || !profiles_[p].autoConnect) continue;
            int strongest = -1000;
            for (int i = 0; i < count; ++i) {
                if (WiFi.SSID(i) == profiles_[p].ssid) strongest = max(strongest, WiFi.RSSI(i));
            }
            if (strongest == -1000) continue;
            if (best < 0 || profiles_[p].priority > bestPriority ||
                (profiles_[p].priority == bestPriority && strongest > bestRssi)) {
                best = static_cast<int>(p);
                bestPriority = profiles_[p].priority;
                bestRssi = strongest;
            }
        }
    }
    WiFi.scanDelete();

    // Hidden networks do not appear in the scan. If no visible candidate is
    // found, fall back to the highest-priority enabled profile.
    if (best < 0) {
        for (size_t p = 0; p < profileCount_; ++p) {
            if (!profiles_[p].enabled || !profiles_[p].autoConnect) continue;
            if (best < 0 || profiles_[p].priority > bestPriority) {
                best = static_cast<int>(p);
                bestPriority = profiles_[p].priority;
            }
        }
    }
    return best;
}

bool NetworkService::connectProfile(NetworkProfile& profile, uint32_t timeoutMs) {
    WiFi.disconnect(false, false);
    delay(40);
    WiFi.mode(WIFI_STA);

    if (profile.security == "open") {
        WiFi.begin(profile.ssid.c_str(), nullptr);
    } else if (profile.security == "personal") {
        WiFi.begin(profile.ssid.c_str(), profile.password.c_str());
    } else if (profile.security == "enterprise-password") {
#ifdef CONFIG_ESP_WIFI_ENTERPRISE_SUPPORT
        WiFiMulti multi;
        if (!multi.addAP(profile.ssid.c_str(), profile.password.c_str(),
                         profile.username.c_str(), profile.identity.c_str())) {
            lastError_ = "enterprise_configuration_failed";
            return false;
        }
        if (multi.run(timeoutMs) != WL_CONNECTED) {
            ++profile.failureCount;
            lastError_ = "enterprise_connection_failed";
            save();
            return false;
        }
#else
        lastError_ = "enterprise_not_supported_by_firmware";
        return false;
#endif
    }

    if (profile.security != "enterprise-password") {
        const uint32_t started = millis();
        while (WiFi.status() != WL_CONNECTED && millis() - started < timeoutMs) {
            delay(180);
        }
        if (WiFi.status() != WL_CONNECTED) {
            ++profile.failureCount;
            lastError_ = "connection_failed";
            save();
            return false;
        }
    }

    profile.failureCount = 0;
    connectedSsid_ = profile.ssid;
    lastError_ = "";
    reconnectBackoffMs_ = 30000U;
    save();
    Serial.printf("[wifi] conectado a %s, IP=%s\n",
                  connectedSsid_.c_str(), WiFi.localIP().toString().c_str());
    return true;
}

bool NetworkService::reconnect(uint32_t timeoutMs) {
    if (!enabled_ || provisioning_ || !hasCredentials()) return false;
    if (connected()) return true;

    lastReconnectAttemptMs_ = millis();
    connectedSsid_ = "";
    lastError_ = "";
    WiFi.mode(WIFI_STA);

    const int index = chooseVisibleProfile();
    if (index < 0) {
        lastError_ = "no_known_network";
        return false;
    }
    const bool ok = connectProfile(profiles_[index], timeoutMs);
    if (!ok) {
        const uint32_t doubled = reconnectBackoffMs_ > 150000U ? 300000U : reconnectBackoffMs_ * 2U;
        reconnectBackoffMs_ = doubled;
    }
    return ok;
}

void NetworkService::disable() {
    enabled_ = false;
    provisioning_ = false;
    save();
    WiFi.disconnect(false, false);
    WiFi.mode(WIFI_OFF);
    connectedSsid_ = "";
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
    if (!enabled_ || provisioning_ || !hasCredentials()) return;
    if (connected()) {
        if (connectedSsid_.length() == 0) connectedSsid_ = WiFi.SSID();
        return;
    }
    connectedSsid_ = "";
    if (millis() - lastReconnectAttemptMs_ < reconnectBackoffMs_) return;
    reconnect(1800U);
}

bool NetworkService::connected() const {
    return enabled_ && !provisioning_ && WiFi.status() == WL_CONNECTED;
}

String NetworkService::ip() const {
    return connected() ? WiFi.localIP().toString() : String();
}
