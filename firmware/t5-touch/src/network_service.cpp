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


int NetworkService::findProfileBySsid(
    const String& ssid) const {

    for (
        size_t i = 0;
        i < profileCount_;
        ++i
    ) {
        if (profiles_[i].ssid == ssid) {
            return static_cast<int>(i);
        }
    }

    return -1;
}


String NetworkService::profileIdForSsid(
    const String& ssid) const {

    uint32_t hash = 2166136261UL;

    for (
        size_t i = 0;
        i < ssid.length();
        ++i
    ) {
        hash ^=
            static_cast<uint8_t>(
                ssid[i]);

        hash *= 16777619UL;
    }

    return
        "touch-" +
        String(hash, HEX);
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
    lastError_ = "";

    WiFi.setAutoReconnect(false);

    const bool staConnected =
        WiFi.status() == WL_CONNECTED;

    const int32_t staChannel =
        WiFi.channel();

    Serial.printf(
        "[wifi] provisioning entry: mode=%d status=%d channel=%ld connected=%d\n",
        static_cast<int>(WiFi.getMode()),
        static_cast<int>(WiFi.status()),
        static_cast<long>(staChannel),
        staConnected ? 1 : 0);

    if (staConnected) {
        // Keep the existing association alive. AP and STA share the same
        // 2.4 GHz radio, so provisioning is opened as AP+STA.
        connectedSsid_ =
            WiFi.SSID();

        if (!WiFi.mode(WIFI_AP_STA)) {
            lastError_ =
                "apsta_mode_failed";

            Serial.println(
                "[wifi] falha ao entrar em WIFI_AP_STA");
            return;
        }
    } else {
        connectedSsid_ = "";

        // No active association needs to be preserved.
        if (!WiFi.mode(WIFI_AP)) {
            lastError_ =
                "ap_mode_failed";

            Serial.println(
                "[wifi] falha ao entrar em WIFI_AP");
            return;
        }
    }

    delay(40);

    Serial.printf(
        "[wifi] provisioning mode ready: mode=%d status=%d channel=%ld\n",
        static_cast<int>(WiFi.getMode()),
        static_cast<int>(WiFi.status()),
        static_cast<long>(WiFi.channel()));
}



void NetworkService::finishProvisioning() {
    Serial.printf(
        "[wifi] provisioning finish: mode=%d status=%d\n",
        static_cast<int>(WiFi.getMode()),
        static_cast<int>(WiFi.status()));

    WiFi.softAPdisconnect(false);
    delay(20);

    provisioning_ = false;

    if (!enabled_) {
        connectedSsid_ = "";
        WiFi.disconnect(
            false,
            false);
        WiFi.mode(WIFI_OFF);
        return;
    }

    // If STA survived provisioning, simply remove the AP side and keep
    // the current connection. This avoids another radio transition.
    if (WiFi.status() == WL_CONNECTED) {
        WiFi.mode(WIFI_STA);
        connectedSsid_ =
            WiFi.SSID();

        Serial.printf(
            "[wifi] STA preservado apos provisioning: %s\n",
            connectedSsid_.c_str());
        return;
    }

    connectedSsid_ = "";

    if (hasCredentials()) {
        WiFi.mode(WIFI_STA);
        lastReconnectAttemptMs_ = 0;
        reconnectBackoffMs_ = 0;
        return;
    }

    WiFi.mode(WIFI_OFF);
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


size_t NetworkService::scanVisible(
    NetworkScanResult* results,
    size_t maxResults) {

    if (!results || maxResults == 0) {
        return 0;
    }

    if (provisioning_) {
        lastError_ =
            "scan_unavailable_during_provisioning";
        return 0;
    }

    enabled_ = true;
    save();

    WiFi.mode(WIFI_STA);

    const int found =
        WiFi.scanNetworks(
            false,
            true,
            false,
            160,
            0);

    if (found <= 0) {
        WiFi.scanDelete();
        lastError_ =
            "no_networks_found";
        return 0;
    }

    size_t count = 0;

    for (
        int i = 0;
        i < found;
        ++i
    ) {
        const String ssid =
            WiFi.SSID(i);

        if (ssid.length() == 0) {
            continue;
        }

        const int32_t rssi =
            WiFi.RSSI(i);

        const wifi_auth_mode_t auth =
            WiFi.encryptionType(i);

        bool duplicate = false;

        for (
            size_t j = 0;
            j < count;
            ++j
        ) {
            if (results[j].ssid != ssid) {
                continue;
            }

            duplicate = true;

            if (rssi > results[j].rssi) {
                results[j].rssi = rssi;
            }

            break;
        }

        if (duplicate) {
            continue;
        }

        if (count >= maxResults) {
            continue;
        }

        NetworkScanResult result;
        result.ssid = ssid;
        result.rssi = rssi;
        result.open =
            auth == WIFI_AUTH_OPEN;
        result.enterprise =
            auth == WIFI_AUTH_WPA2_ENTERPRISE;
        result.known =
            findProfileBySsid(ssid) >= 0;

        results[count++] =
            result;
    }

    WiFi.scanDelete();

    // Strongest networks first. A saved network wins ties.
    for (
        size_t i = 0;
        i < count;
        ++i
    ) {
        for (
            size_t j = i + 1;
            j < count;
            ++j
        ) {
            const bool swap =
                results[j].rssi >
                    results[i].rssi ||
                (
                    results[j].rssi ==
                        results[i].rssi &&
                    results[j].known &&
                    !results[i].known
                );

            if (swap) {
                const NetworkScanResult tmp =
                    results[i];

                results[i] =
                    results[j];

                results[j] =
                    tmp;
            }
        }
    }

    lastError_ = "";

    Serial.printf(
        "[wifi] scan: %u redes visiveis\n",
        static_cast<unsigned>(count));

    return count;
}


bool NetworkService::connectSavedSsid(
    const String& ssid,
    uint32_t timeoutMs) {

    const int index =
        findProfileBySsid(ssid);

    if (index < 0) {
        lastError_ =
            "unknown_network";
        return false;
    }

    enabled_ = true;
    save();

    return connectProfile(
        profiles_[index],
        timeoutMs);
}


bool NetworkService::connectAndStore(
    const String& ssid,
    const String& password,
    bool openNetwork,
    uint32_t timeoutMs) {

    if (
        ssid.length() == 0 ||
        ssid.length() > 32
    ) {
        lastError_ =
            "invalid_ssid";
        return false;
    }

    NetworkProfile profile;

    const int existing =
        findProfileBySsid(ssid);

    if (existing >= 0) {
        profile =
            profiles_[existing];
    } else {
        profile.id =
            profileIdForSsid(ssid);
        profile.ssid =
            ssid;
        profile.priority = 80;
        profile.enabled = true;
        profile.autoConnect = true;
    }

    profile.security =
        openNetwork
            ? "open"
            : "personal";

    profile.password =
        openNetwork
            ? String()
            : password;

    profile.identity = "";
    profile.username = "";

    if (!validProfile(profile)) {
        lastError_ =
            "invalid_network_profile";
        return false;
    }

    if (existing >= 0) {
        profiles_[existing] =
            profile;
    } else {
        if (
            profileCount_ >=
            MAX_PROFILES
        ) {
            lastError_ =
                "network_profile_capacity";
            return false;
        }

        profiles_[profileCount_++] =
            profile;
    }

    enabled_ = true;
    save();

    const int index =
        findProfileBySsid(ssid);

    if (index < 0) {
        lastError_ =
            "profile_persist_failed";
        return false;
    }

    return connectProfile(
        profiles_[index],
        timeoutMs);
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
