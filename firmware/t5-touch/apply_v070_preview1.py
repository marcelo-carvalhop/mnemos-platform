
from pathlib import Path
import re

ROOT = Path.cwd()

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")

def write(rel, text):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")

def replace_once(text, old, new, label):
    if old not in text:
        raise RuntimeError(f"{label}: trecho esperado nao encontrado")
    return text.replace(old, new, 1)

def replace_function(text, marker, replacement):
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f"funcao nao encontrada: {marker}")
    brace = text.find("{", start)
    if brace < 0:
        raise RuntimeError(f"abertura nao encontrada: {marker}")

    depth = 0
    in_string = False
    escape = False
    line_comment = False
    block_comment = False
    i = brace

    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""

        if line_comment:
            if c == "\n":
                line_comment = False
        elif block_comment:
            if c == "*" and n == "/":
                block_comment = False
                i += 1
        elif in_string:
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == '"':
                in_string = False
        else:
            if c == "/" and n == "/":
                line_comment = True
                i += 1
            elif c == "/" and n == "*":
                block_comment = True
                i += 1
            elif c == '"':
                in_string = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return text[:start] + replacement.rstrip() + "\n" + text[i + 1:]
        i += 1

    raise RuntimeError(f"fechamento nao encontrado: {marker}")

def function_slice(text, marker):
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f"funcao nao encontrada: {marker}")
    brace = text.find("{", start)
    depth = 0
    i = brace
    in_string = False
    escape = False
    line_comment = False
    block_comment = False

    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if line_comment:
            if c == "\n":
                line_comment = False
        elif block_comment:
            if c == "*" and n == "/":
                block_comment = False
                i += 1
        elif in_string:
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == '"':
                in_string = False
        else:
            if c == "/" and n == "/":
                line_comment = True
                i += 1
            elif c == "/" and n == "*":
                block_comment = True
                i += 1
            elif c == '"':
                in_string = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return start, i + 1
        i += 1
    raise RuntimeError(marker)

def replace_case_in_function(text, fn_marker, case_marker, next_case_marker, replacement):
    fs, fe = function_slice(text, fn_marker)
    fn = text[fs:fe]
    a = fn.find(case_marker)
    if a < 0:
        raise RuntimeError(f"case ausente em {fn_marker}: {case_marker}")
    b = fn.find(next_case_marker, a)
    if b < 0:
        raise RuntimeError(f"proximo case ausente: {next_case_marker}")
    fn2 = fn[:a] + replacement.rstrip() + "\n\n" + fn[b:]
    return text[:fs] + fn2 + text[fe:]

# ------------------------------------------------------------------
# config.h
# ------------------------------------------------------------------
p = "include/config.h"
s = read(p)
s = re.sub(r'constexpr bool DEMO_INTERVALS\s*=\s*true\s*;',
           'constexpr bool DEMO_INTERVALS = false;', s, count=1)
s = re.sub(r'constexpr bool SEED_MANDARIN_TRAINING_DECK\s*=\s*true\s*;',
           'constexpr bool SEED_MANDARIN_TRAINING_DECK = false;', s, count=1)
s = re.sub(r'constexpr char APP_VERSION\[\]\s*=\s*"[^"]+"\s*;',
           'constexpr char APP_VERSION[] = "0.7.0-preview.1-touch";', s, count=1)

anchor = 'constexpr uint16_t TOUCH_RETRY_MS = 3000;\n'
if anchor not in s:
    raise RuntimeError("config: TOUCH_RETRY_MS nao encontrado")

s = s.replace(anchor, '''constexpr uint16_t TOUCH_RETRY_MS = 3000;

// Rede cooperativa: descoberta/conexão não bloqueiam a HMI.
constexpr uint32_t WIFI_CONNECT_TIMEOUT_MS = 12000U;
constexpr uint32_t WIFI_RECONNECT_TIMEOUT_MS = 8000U;
constexpr uint32_t WIFI_RECONNECT_INITIAL_BACKOFF_MS = 30000U;
constexpr uint32_t WIFI_RECONNECT_MAX_BACKOFF_MS = 300000U;

// SNTP é observado sem espera bloqueante.
constexpr uint32_t NTP_SYNC_TIMEOUT_MS = 10000U;

// CA HTTPS opcional no LittleFS.
constexpr char BACKEND_CA_FILE[] = "/backend_ca.pem";
''', 1)
write(p, s)

# ------------------------------------------------------------------
# models.h: every type is self-assessed on T5 Touch
# ------------------------------------------------------------------
p = "include/models.h"
s = read(p)
s = replace_once(
    s,
    '''    bool isSelfAssessed() const {
        return !isObjective();
    }''',
    '''    bool isSelfAssessed() const {
        // T5 Touch is a retrieval-practice terminal. Even objective cards
        // are answered mentally, then revealed and self-assessed.
        return true;
    }''',
    "models self assessment")
write(p, s)

# ------------------------------------------------------------------
# NetworkService async API
# ------------------------------------------------------------------
p = "include/network_service.h"
s = read(p)

profile_anchor = '''struct NetworkProfile {
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
'''
if profile_anchor not in s:
    raise RuntimeError("network header: NetworkProfile anchor ausente")

s = s.replace(profile_anchor, profile_anchor + '''
enum class NetworkAsyncState : uint8_t {
    Idle = 0,
    Scanning,
    Connecting,
};
''', 1)

pub_anchor = '''    bool connectAndStore(
        const String& ssid,
        const String& password,
        bool openNetwork,
        uint32_t timeoutMs = 12000U);

    void disable();
'''
if pub_anchor not in s:
    raise RuntimeError("network header: public anchor ausente")

s = s.replace(pub_anchor, '''    bool connectAndStore(
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

    void disable();
''', 1)

priv_anchor = '''    uint32_t lastReconnectAttemptMs_ = 0;
    uint32_t reconnectBackoffMs_ = 30000U;

    void load();
'''
if priv_anchor not in s:
    raise RuntimeError("network header: private anchor ausente")

s = s.replace(priv_anchor, '''    uint32_t lastReconnectAttemptMs_ = 0;
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
''', 1)

methods_anchor = '''    int chooseVisibleProfile();
    bool connectProfile(NetworkProfile& profile, uint32_t timeoutMs);
    bool validProfile(const NetworkProfile& profile) const;
'''
if methods_anchor not in s:
    raise RuntimeError("network header: methods anchor ausente")

s = s.replace(methods_anchor, '''    int chooseVisibleProfile();
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
''', 1)
write(p, s)

p = "src/network_service.cpp"
s = read(p)

s = replace_function(s, "void NetworkService::begin()", r'''void NetworkService::begin() {
    preferences_.begin(
        "mnemos-net",
        false);

    load();

    connectedSsid_ = "";
    WiFi.setAutoReconnect(false);

    asyncState_ =
        NetworkAsyncState::Idle;

    scanResultReady_ = false;
    connectionResultReady_ = false;

    reconnectBackoffMs_ =
        Config::
            WIFI_RECONNECT_INITIAL_BACKOFF_MS;

    lastReconnectAttemptMs_ = 0;

    if (!enabled_) {
        WiFi.mode(WIFI_OFF);
        return;
    }

    if (hasCredentials()) {
        // loop() performs connection attempts cooperatively.
        WiFi.mode(WIFI_STA);
    }
}''')

marker = "void NetworkService::disable()"
pos = s.find(marker)
if pos < 0:
    raise RuntimeError("network source: disable marker ausente")

async_impl = r'''
int NetworkService::bestEnabledProfile() const {
    int best = -1;
    int16_t priority = -32768;

    for (
        size_t i = 0;
        i < profileCount_;
        ++i
    ) {
        if (
            !profiles_[i].enabled ||
            !profiles_[i].autoConnect
        ) {
            continue;
        }

        if (
            best < 0 ||
            profiles_[i].priority >
                priority
        ) {
            best =
                static_cast<int>(i);

            priority =
                profiles_[i].priority;
        }
    }

    return best;
}


bool NetworkService::startScan() {
    if (
        provisioning_ ||
        asyncState_ !=
            NetworkAsyncState::Idle
    ) {
        lastError_ =
            "network_busy";
        return false;
    }

    enabled_ = true;
    save();

    if (
        WiFi.getMode() ==
        WIFI_OFF
    ) {
        WiFi.mode(WIFI_STA);
    }

    WiFi.scanDelete();

    const int started =
        WiFi.scanNetworks(
            true,
            true,
            false,
            160,
            0);

    if (
        started ==
        WIFI_SCAN_FAILED
    ) {
        lastError_ =
            "scan_start_failed";
        return false;
    }

    asyncState_ =
        NetworkAsyncState::Scanning;

    asyncStartedMs_ =
        millis();

    asyncScanCount_ = 0;
    scanResultReady_ = false;
    lastError_ = "";

    Serial.println(
        "[wifi] scan assincrono iniciado");

    return true;
}


void NetworkService::finishAsyncScan(
    int found) {

    asyncScanCount_ = 0;

    if (found > 0) {
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
                j < asyncScanCount_;
                ++j
            ) {
                if (
                    asyncScanResults_[j].
                        ssid !=
                    ssid
                ) {
                    continue;
                }

                duplicate = true;

                if (
                    rssi >
                    asyncScanResults_[j].
                        rssi
                ) {
                    asyncScanResults_[j].
                        rssi =
                        rssi;
                }

                break;
            }

            if (
                duplicate ||
                asyncScanCount_ >=
                    MAX_SCAN_RESULTS
            ) {
                continue;
            }

            NetworkScanResult result;
            result.ssid = ssid;
            result.rssi = rssi;
            result.open =
                auth ==
                WIFI_AUTH_OPEN;
            result.enterprise =
                auth ==
                WIFI_AUTH_WPA2_ENTERPRISE;
            result.known =
                findProfileBySsid(
                    ssid) >= 0;

            asyncScanResults_[
                asyncScanCount_++] =
                result;
        }
    }

    WiFi.scanDelete();

    for (
        size_t i = 0;
        i < asyncScanCount_;
        ++i
    ) {
        for (
            size_t j = i + 1;
            j < asyncScanCount_;
            ++j
        ) {
            const bool swap =
                asyncScanResults_[j].
                    rssi >
                    asyncScanResults_[i].
                        rssi ||
                (
                    asyncScanResults_[j].
                        rssi ==
                        asyncScanResults_[i].
                            rssi &&
                    asyncScanResults_[j].
                        known &&
                    !asyncScanResults_[i].
                        known
                );

            if (swap) {
                const NetworkScanResult tmp =
                    asyncScanResults_[i];

                asyncScanResults_[i] =
                    asyncScanResults_[j];

                asyncScanResults_[j] =
                    tmp;
            }
        }
    }

    asyncState_ =
        NetworkAsyncState::Idle;

    scanResultReady_ = true;

    lastError_ =
        asyncScanCount_ == 0
            ? "no_networks_found"
            : "";

    Serial.printf(
        "[wifi] scan assincrono concluido: %u redes\n",
        static_cast<unsigned>(
            asyncScanCount_));
}


bool NetworkService::consumeScanResults(
    NetworkScanResult* results,
    size_t maxResults,
    size_t& count) {

    if (!scanResultReady_) {
        return false;
    }

    scanResultReady_ = false;

    count =
        std::min<size_t>(
            asyncScanCount_,
            maxResults);

    for (
        size_t i = 0;
        i < count;
        ++i
    ) {
        results[i] =
            asyncScanResults_[i];
    }

    return true;
}


bool NetworkService::beginAsyncConnection(
    int profileIndex,
    bool notify,
    uint32_t timeoutMs) {

    if (
        provisioning_ ||
        asyncState_ !=
            NetworkAsyncState::Idle ||
        profileIndex < 0 ||
        static_cast<size_t>(
            profileIndex) >=
            profileCount_
    ) {
        lastError_ =
            "network_busy";
        return false;
    }

    NetworkProfile& profile =
        profiles_[profileIndex];

    if (
        profile.security ==
        "enterprise-password"
    ) {
        lastError_ =
            "enterprise_requires_external_provisioning";

        if (notify) {
            connectionResultReady_ = true;
            connectionResultSuccess_ = false;
            connectionResultSsid_ =
                profile.ssid;
            connectionResultError_ =
                lastError_;
        }

        return false;
    }

    WiFi.disconnect(
        false,
        false);

    if (
        WiFi.getMode() ==
        WIFI_OFF
    ) {
        WiFi.mode(WIFI_STA);
    }

    if (
        profile.security ==
        "open"
    ) {
        WiFi.begin(
            profile.ssid.c_str(),
            nullptr);
    } else {
        WiFi.begin(
            profile.ssid.c_str(),
            profile.password.c_str());
    }

    asyncProfileIndex_ =
        profileIndex;

    asyncNotify_ =
        notify;

    asyncStartedMs_ =
        millis();

    asyncTimeoutMs_ =
        timeoutMs;

    asyncState_ =
        NetworkAsyncState::Connecting;

    lastReconnectAttemptMs_ =
        asyncStartedMs_;

    connectedSsid_ = "";
    lastError_ = "";

    Serial.printf(
        "[wifi] conexao assincrona iniciada: %s\n",
        profile.ssid.c_str());

    return true;
}


bool NetworkService::startConnectSavedSsidAsync(
    const String& ssid,
    uint32_t timeoutMs) {

    const int index =
        findProfileBySsid(
            ssid);

    if (index < 0) {
        lastError_ =
            "unknown_network";
        return false;
    }

    enabled_ = true;
    save();

    return
        beginAsyncConnection(
            index,
            true,
            timeoutMs);
}


bool NetworkService::startConnectAndStoreAsync(
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
        findProfileBySsid(
            ssid);

    if (existing >= 0) {
        profile =
            profiles_[existing];
    } else {
        profile.id =
            profileIdForSsid(
                ssid);

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
        findProfileBySsid(
            ssid);

    if (index < 0) {
        lastError_ =
            "profile_persist_failed";
        return false;
    }

    return
        beginAsyncConnection(
            index,
            true,
            timeoutMs);
}


void NetworkService::finishAsyncConnection(
    bool success,
    const String& error) {

    const int index =
        asyncProfileIndex_;

    String ssid;

    if (
        index >= 0 &&
        static_cast<size_t>(index) <
            profileCount_
    ) {
        NetworkProfile& profile =
            profiles_[index];

        ssid =
            profile.ssid;

        if (success) {
            profile.failureCount = 0;
        } else {
            ++profile.failureCount;
        }

        save();
    }

    if (success) {
        connectedSsid_ =
            WiFi.SSID().length() > 0
                ? WiFi.SSID()
                : ssid;

        lastError_ = "";

        reconnectBackoffMs_ =
            Config::
                WIFI_RECONNECT_INITIAL_BACKOFF_MS;

        Serial.printf(
            "[wifi] conectado a %s, IP=%s\n",
            connectedSsid_.c_str(),
            WiFi.localIP().
                toString().
                c_str());
    } else {
        connectedSsid_ = "";
        lastError_ = error;

        const uint32_t doubled =
            reconnectBackoffMs_ >
                Config::
                    WIFI_RECONNECT_MAX_BACKOFF_MS /
                    2U
                ? Config::
                      WIFI_RECONNECT_MAX_BACKOFF_MS
                : reconnectBackoffMs_ *
                      2U;

        reconnectBackoffMs_ =
            std::min<uint32_t>(
                doubled,
                Config::
                    WIFI_RECONNECT_MAX_BACKOFF_MS);

        Serial.printf(
            "[wifi] conexao falhou: %s\n",
            error.c_str());
    }

    if (asyncNotify_) {
        connectionResultReady_ = true;
        connectionResultSuccess_ =
            success;
        connectionResultSsid_ =
            ssid;
        connectionResultError_ =
            error;
    }

    asyncState_ =
        NetworkAsyncState::Idle;

    asyncProfileIndex_ = -1;
    asyncNotify_ = false;
}


bool NetworkService::consumeConnectionResult(
    bool& success,
    String& ssid,
    String& error) {

    if (!connectionResultReady_) {
        return false;
    }

    connectionResultReady_ = false;

    success =
        connectionResultSuccess_;

    ssid =
        connectionResultSsid_;

    error =
        connectionResultError_;

    return true;
}


'''

s = s[:pos] + async_impl + "\n" + s[pos:]

s = replace_function(s, "bool NetworkService::enable()", r'''bool NetworkService::enable() {
    enabled_ = true;
    save();

    if (!hasCredentials()) {
        lastError_ =
            "not_provisioned";
        return false;
    }

    lastError_ = "";

    if (
        WiFi.getMode() ==
        WIFI_OFF
    ) {
        WiFi.mode(WIFI_STA);
    }

    lastReconnectAttemptMs_ = 0;
    reconnectBackoffMs_ = 0;

    return true;
}''')

s = replace_function(s, "void NetworkService::loop()", r'''void NetworkService::loop() {
    if (provisioning_) {
        return;
    }

    const uint32_t now =
        millis();

    if (
        asyncState_ ==
        NetworkAsyncState::Scanning
    ) {
        const int found =
            WiFi.scanComplete();

        if (
            found !=
            WIFI_SCAN_RUNNING
        ) {
            finishAsyncScan(
                found < 0
                    ? 0
                    : found);
        }

        return;
    }

    if (
        asyncState_ ==
        NetworkAsyncState::Connecting
    ) {
        if (
            WiFi.status() ==
            WL_CONNECTED
        ) {
            finishAsyncConnection(
                true,
                "");
            return;
        }

        if (
            now -
                asyncStartedMs_ >=
            asyncTimeoutMs_
        ) {
            finishAsyncConnection(
                false,
                "connection_failed");
        }

        return;
    }

    if (
        !enabled_ ||
        !hasCredentials()
    ) {
        return;
    }

    if (connected()) {
        if (
            connectedSsid_.
                length() == 0
        ) {
            connectedSsid_ =
                WiFi.SSID();
        }

        return;
    }

    connectedSsid_ = "";

    if (
        now -
            lastReconnectAttemptMs_ <
        reconnectBackoffMs_
    ) {
        return;
    }

    const int index =
        bestEnabledProfile();

    if (index < 0) {
        lastError_ =
            "no_known_network";
        lastReconnectAttemptMs_ =
            now;
        return;
    }

    beginAsyncConnection(
        index,
        false,
        Config::
            WIFI_RECONNECT_TIMEOUT_MS);
}''')

write(p, s)

# ------------------------------------------------------------------
# TimeService: non-blocking SNTP
# ------------------------------------------------------------------
p = "include/time_service.h"
s = read(p)
anchor = '''    uint32_t lastCheckpointMillis_ = 0;
    uint32_t lastNtpAttemptMillis_ = 0;

    bool tryNtp(uint32_t waitMs);
'''
if anchor not in s:
    raise RuntimeError("time header anchor ausente")
s = s.replace(anchor, '''    uint32_t lastCheckpointMillis_ = 0;
    uint32_t lastNtpAttemptMillis_ = 0;
    uint32_t ntpAttemptStartedMillis_ = 0;
    bool ntpPending_ = false;

    bool tryNtp(uint32_t waitMs);  // legado; fora do fluxo normal
''', 1)
write(p, s)

p = "src/time_service.cpp"
s = read(p)
if '#include <esp_sntp.h>' not in s:
    s = s.replace('#include <sys/time.h>\n',
                  '#include <sys/time.h>\n#include <esp_sntp.h>\n', 1)

s = replace_function(s, "void TimeService::begin()", r'''void TimeService::begin() {
    preferences_.begin(
        "mnemos-clock",
        false);

    Wire.begin(
        Config::SYSTEM_I2C_SDA,
        Config::SYSTEM_I2C_SCL);

    rtc_.begin(Wire);

    Wire.beginTransmission(
        PCF8563_ADDRESS);

    rtcOnline_ =
        Wire.endTransmission() ==
        0;

    Serial.printf(
        "[clock] RTC PCF8563 %s em SDA=%d SCL=%d\n",
        rtcOnline_
            ? "online"
            : "indisponivel",
        Config::SYSTEM_I2C_SDA,
        Config::SYSTEM_I2C_SCL);

    const uint32_t build =
        compileEpoch();

    const uint32_t saved =
        preferences_.getULong(
            "lastEpoch",
            0U);

    const bool rtcIntegrity =
        rtcClockIntegrityOk();

    const uint32_t fromRtc =
        rtcIntegrity
            ? rtcEpoch()
            : 0U;

    if (
        rtcCandidatePlausible(
            fromRtc,
            build,
            saved)
    ) {
        seedSystemClock(
            fromRtc);

        trusted_ = true;
        ntpSynchronized_ = false;

        preferences_.putULong(
            "lastEpoch",
            fromRtc);

        lastCheckpointMillis_ =
            millis();

        logLocalTime(
            "RTC",
            fromRtc);
    } else {
        if (fromRtc > 0) {
            Serial.printf(
                "[clock] RTC rejeitado: rtc=%lu build=%lu saved=%lu\n",
                static_cast<unsigned long>(fromRtc),
                static_cast<unsigned long>(build),
                static_cast<unsigned long>(saved));
        }

        fallbackBaseEpoch_ =
            std::max(
                build,
                saved > 0
                    ? saved + 60U
                    : 0U);

        fallbackBaseMillis_ =
            millis();

        lastCheckpointMillis_ =
            millis();

        trusted_ = false;
        ntpSynchronized_ = false;

        seedSystemClock(
            fallbackBaseEpoch_);

        logLocalTime(
            "BUILD/FALLBACK",
            fallbackBaseEpoch_);
    }

    ntpPending_ = false;
    lastNtpAttemptMillis_ = 0;

    Serial.println(
        "[clock] boot sem espera por NTP");
}''')

s = replace_function(s, "bool TimeService::maintain()", r'''bool TimeService::maintain() {
    if (ntpSynchronized_) {
        return false;
    }

    const uint32_t nowMs =
        millis();

    if (ntpPending_) {
        if (
            sntp_get_sync_status() ==
            SNTP_SYNC_STATUS_COMPLETED
        ) {
            const uint32_t current =
                static_cast<uint32_t>(
                    time(nullptr));

            if (
                current >=
                MIN_VALID_EPOCH
            ) {
                ntpPending_ = false;
                ntpSynchronized_ = true;
                trusted_ = true;

                fallbackBaseEpoch_ =
                    current;
                fallbackBaseMillis_ =
                    nowMs;

                writeRtc(current);

                preferences_.putULong(
                    "lastEpoch",
                    current);

                lastCheckpointMillis_ =
                    nowMs;

                logLocalTime(
                    "NTP",
                    current);

                return true;
            }
        }

        if (
            nowMs -
                ntpAttemptStartedMillis_ >=
            Config::NTP_SYNC_TIMEOUT_MS
        ) {
            ntpPending_ = false;

            Serial.println(
                "[clock] NTP timeout; relogio atual preservado");
        }

        return false;
    }

    if (
        WiFi.status() !=
        WL_CONNECTED
    ) {
        return false;
    }

    if (
        lastNtpAttemptMillis_ != 0 &&
        nowMs -
            lastNtpAttemptMillis_ <
            NTP_RETRY_INTERVAL_MS
    ) {
        return false;
    }

    lastNtpAttemptMillis_ =
        nowMs;

    ntpAttemptStartedMillis_ =
        nowMs;

    configTime(
        0,
        0,
        "pool.ntp.org",
        "time.google.com",
        "time.cloudflare.com");

    ntpPending_ = true;

    Serial.println(
        "[clock] NTP assincrono iniciado");

    return false;
}''')
write(p, s)

# ------------------------------------------------------------------
# Display: objective cards show options but do not accept them
# ------------------------------------------------------------------
p = "src/t5_display.cpp"
s = read(p)
s = replace_function(s, "void T5Display::showQuestion(", r'''void T5Display::showQuestion(
    const CardDefinition& card,
    uint8_t position,
    uint8_t total) {

    clearBuffer();

    drawSystemBar(
        "Estudo",
        false,
        true,
        String(position + 1) +
            " de " +
            String(total),
        true);

    const bool mandarin =
        card.deckId ==
        "training-mandarin-100";

    const int32_t barH =
        systemBarHeight();

    const int32_t deckY =
        portrait()
            ? barH + 68
            : barH + 62;

    drawText(
        shortText(
            card.deck,
            portrait()
                ? 36
                : 30),
        MARGIN,
        deckY,
        MnemosFontRole::Meta14,
        DARK_GRAY);

    if (mandarin) {
        if (portrait()) {
            drawText(
                "Qual é a leitura e o significado?",
                MARGIN,
                245,
                MnemosFontRole::Body18,
                BLACK);

            drawCenteredHanzi(
                card.question,
                logicalWidth() / 2,
                510,
                4);
        } else {
            drawLine(
                468,
                150,
                468,
                438,
                LIGHT_GRAY);

            drawWrapped(
                "Qual é a leitura e o significado?",
                MARGIN,
                190,
                360,
                34,
                3,
                MnemosFontRole::Body18,
                BLACK);

            drawText(
                "Recupere primeiro; depois revele.",
                MARGIN,
                292,
                MnemosFontRole::Meta14,
                DARK_GRAY);

            drawCenteredHanzi(
                card.question,
                714,
                338,
                4);
        }

        drawPrimaryButton(
            "Ver resposta");

        refreshFull();
        return;
    }

    if (card.isObjective()) {
        if (portrait()) {
            drawWrapped(
                card.question,
                MARGIN,
                205,
                logicalWidth() -
                    2 * MARGIN,
                31,
                5,
                MnemosFontRole::Body18,
                BLACK);

            const uint8_t count =
                std::min<uint8_t>(
                    card.optionCount,
                    4);

            for (
                uint8_t i = 0;
                i < count;
                ++i
            ) {
                drawChoiceCard(
                    i + 1,
                    card.options[i],
                    MARGIN,
                    375 +
                        i * 96,
                    logicalWidth() -
                        2 * MARGIN,
                    86);
            }
        } else {
            drawWrapped(
                card.question,
                MARGIN,
                180,
                390,
                31,
                6,
                MnemosFontRole::Body18,
                BLACK);

            const uint8_t count =
                std::min<uint8_t>(
                    card.optionCount,
                    4);

            for (
                uint8_t i = 0;
                i < count;
                ++i
            ) {
                drawChoiceCard(
                    i + 1,
                    card.options[i],
                    504,
                    126 +
                        i * 80,
                    408,
                    72);
            }
        }
    } else {
        drawWrapped(
            card.question,
            MARGIN,
            portrait()
                ? 240
                : 190,
            portrait()
                ? logicalWidth() -
                      2 * MARGIN
                : 650,
            portrait()
                ? 34
                : 32,
            portrait()
                ? 8
                : 6,
            MnemosFontRole::Body18,
            BLACK);
    }

    drawPrimaryButton(
        "Ver resposta");

    refreshFull();
}''')
write(p, s)

# ------------------------------------------------------------------
# main.cpp: async Wi-Fi and reveal/self-assessment for all cards
# ------------------------------------------------------------------
p = "src/main.cpp"
s = read(p)

anchor = 'String wifiMessagePrimary = "Voltar à conexão";\n'
if anchor not in s:
    raise RuntimeError("main wifi global anchor ausente")
s = s.replace(anchor, anchor + '''bool wifiConnectRetryPassword = false;
bool wifiUserConnectionPending = false;
''', 1)

s = replace_function(s, "void scanWifiNetworks()", r'''void scanWifiNetworks() {
    screen =
        AppScreen::WifiNetworks;

    wifiScanCount = 0;
    wifiSelectedIndex = -1;
    wifiPassword = "";
    wifiHint = "";

    display.showWifiScanning();

    if (!networkService.startScan()) {
        wifiMessageTitle =
            "Wi-Fi ocupado";

        wifiMessageText =
            friendlyWifiError();

        wifiMessagePrimary =
            "Voltar à conexão";

        renderWifiMessage();
    }
}''')

s = replace_function(s, "void selectWifiNetwork(", r'''void selectWifiNetwork(
    int8_t index) {

    if (
        index < 0 ||
        static_cast<size_t>(
            index) >=
            wifiScanCount
    ) {
        return;
    }

    wifiSelectedIndex =
        index;

    NetworkScanResult& selected =
        wifiScan[index];

    if (selected.enterprise) {
        wifiMessageTitle =
            "Rede corporativa";

        wifiMessageText =
            "Esta rede exige identidade/usuário. "
            "Use Configurar pelo celular para informar "
            "as credenciais corporativas.";

        wifiMessagePrimary =
            "Voltar à conexão";

        renderWifiMessage();
        return;
    }

    if (selected.known) {
        wifiConnectRetryPassword =
            !selected.open;

        wifiUserConnectionPending =
            networkService.
                startConnectSavedSsidAsync(
                    selected.ssid);

        if (!wifiUserConnectionPending) {
            wifiHint =
                friendlyWifiError();

            if (
                wifiConnectRetryPassword
            ) {
                selected.known = false;
                wifiPassword = "";
                wifiKeyboardPage =
                    WifiKeyboardPage::Lower;
                renderWifiPassword();
            } else {
                wifiMessageTitle =
                    "Falha ao conectar";
                wifiMessageText =
                    friendlyWifiError();
                wifiMessagePrimary =
                    "Voltar à conexão";
                renderWifiMessage();
            }

            return;
        }

        showWifiConnecting(
            selected.ssid);
        return;
    }

    if (selected.open) {
        wifiConnectRetryPassword =
            false;

        wifiUserConnectionPending =
            networkService.
                startConnectAndStoreAsync(
                    selected.ssid,
                    "",
                    true);

        if (!wifiUserConnectionPending) {
            wifiMessageTitle =
                "Falha ao conectar";
            wifiMessageText =
                friendlyWifiError();
            wifiMessagePrimary =
                "Voltar à conexão";
            renderWifiMessage();
            return;
        }

        showWifiConnecting(
            selected.ssid);
        return;
    }

    wifiPassword = "";
    wifiKeyboardPage =
        WifiKeyboardPage::Lower;
    wifiHint = "";

    renderWifiPassword();
}''')

marker = "void refreshSdView(bool remount)"
pos = s.find(marker)
if pos < 0:
    raise RuntimeError("main refreshSdView marker ausente")

handler = r'''
void handleNetworkEvents() {
    size_t count = 0;

    if (
        networkService.
            consumeScanResults(
                wifiScan,
                NetworkService::
                    MAX_SCAN_RESULTS,
                count)
    ) {
        wifiScanCount =
            count;

        wifiSelectedIndex =
            -1;

        if (
            screen ==
            AppScreen::WifiNetworks
        ) {
            renderWifiNetworks();
        }
    }

    bool success = false;
    String ssid;
    String error;

    if (
        networkService.
            consumeConnectionResult(
                success,
                ssid,
                error)
    ) {
        wifiUserConnectionPending =
            false;

        if (success) {
            wifiPassword = "";
            wifiHint = "";

            if (
                screen ==
                    AppScreen::WifiMessage ||
                screen ==
                    AppScreen::WifiPassword
            ) {
                renderConnection();
            }

            return;
        }

        if (
            wifiConnectRetryPassword &&
            wifiSelectedIndex >= 0 &&
            static_cast<size_t>(
                wifiSelectedIndex) <
                wifiScanCount
        ) {
            wifiScan[
                wifiSelectedIndex].
                known = false;

            wifiPassword = "";

            wifiKeyboardPage =
                WifiKeyboardPage::Lower;

            wifiHint =
                "A credencial salva falhou. Digite a senha novamente.";

            renderWifiPassword();
            return;
        }

        wifiMessageTitle =
            "Falha ao conectar";

        wifiMessageText =
            friendlyWifiError();

        wifiMessagePrimary =
            "Voltar à conexão";

        renderWifiMessage();
    }
}


'''
s = s[:pos] + handler + s[pos:]

wifi_case = r'''        case AppScreen::WifiPassword:
            if (
                action ==
                UiAction::WifiKey
            ) {
                if (
                    wifiPassword.length() <
                    63
                ) {
                    wifiPassword +=
                        static_cast<char>(
                            static_cast<uint8_t>(
                                argument));

                    wifiHint = "";
                    renderWifiPassword();
                }
            } else if (
                action ==
                UiAction::WifiSpace
            ) {
                if (
                    wifiPassword.length() <
                    63
                ) {
                    wifiPassword += ' ';
                    wifiHint = "";
                    renderWifiPassword();
                }
            } else if (
                action ==
                UiAction::WifiBackspace
            ) {
                if (
                    wifiPassword.length() >
                    0
                ) {
                    wifiPassword.remove(
                        wifiPassword.length() -
                        1);
                }

                wifiHint = "";
                renderWifiPassword();
            } else if (
                action ==
                UiAction::WifiShift
            ) {
                wifiKeyboardPage =
                    wifiKeyboardPage ==
                            WifiKeyboardPage::Upper
                        ? WifiKeyboardPage::Lower
                        : WifiKeyboardPage::Upper;

                renderWifiPassword();
            } else if (
                action ==
                UiAction::WifiSymbols
            ) {
                wifiKeyboardPage =
                    wifiKeyboardPage ==
                            WifiKeyboardPage::Symbols
                        ? WifiKeyboardPage::Lower
                        : WifiKeyboardPage::Symbols;

                renderWifiPassword();
            } else if (
                action ==
                UiAction::WifiCancel
            ) {
                renderWifiNetworks();
            } else if (
                action ==
                UiAction::WifiConnect
            ) {
                if (
                    wifiPassword.length() <
                        8 ||
                    wifiPassword.length() >
                        63
                ) {
                    wifiHint =
                        "A senha deve ter entre 8 e 63 caracteres.";

                    renderWifiPassword();
                    break;
                }

                if (
                    wifiSelectedIndex < 0 ||
                    static_cast<size_t>(
                        wifiSelectedIndex) >=
                        wifiScanCount
                ) {
                    renderConnection();
                    break;
                }

                const String ssid =
                    wifiScan[
                        wifiSelectedIndex].
                        ssid;

                wifiConnectRetryPassword =
                    true;

                wifiUserConnectionPending =
                    networkService.
                        startConnectAndStoreAsync(
                            ssid,
                            wifiPassword,
                            false);

                if (!wifiUserConnectionPending) {
                    wifiHint =
                        friendlyWifiError();

                    renderWifiPassword();
                    break;
                }

                showWifiConnecting(
                    ssid);
            }

            break;'''

s = replace_case_in_function(
    s,
    "void processAction(",
    "        case AppScreen::WifiPassword:",
    "        case AppScreen::WifiMessage:",
    wifi_case)

question_case = r'''        case AppScreen::Question:
            if (!engine) {
                break;
            }

            if (
                action ==
                UiAction::AnswerReady
            ) {
                engine->
                    markResponseReady();

                renderSelfAssessment();
            }

            break;'''

s = replace_case_in_function(
    s,
    "void processAction(",
    "        case AppScreen::Question:",
    "        case AppScreen::SelfAssessment:",
    question_case)

touch_question_case = r'''        case AppScreen::Question:
            if (!engine) {
                break;
            }

            addZone(
                zones,
                count,
                "question_reveal",
                48,
                actionTop,
                width - 96,
                portrait
                    ? 136
                    : 72,
                UiAction::AnswerReady);

            break;'''

s = replace_case_in_function(
    s,
    "size_t buildTouchZones(",
    "        case AppScreen::Question:",
    "        case AppScreen::SelfAssessment:",
    touch_question_case)

s = replace_once(
    s,
    '''    localLink.loop();
    networkService.loop();

    if (clockService.maintain()) {''',
    '''    localLink.loop();
    networkService.loop();
    handleNetworkEvents();

    if (clockService.maintain()) {''',
    "main loop network events")

write(p, s)

# ------------------------------------------------------------------
# Capabilities
# ------------------------------------------------------------------
p = "src/local_link_service.cpp"
s = read(p)
s = s.replace('doc["features"]["keyboard"] = true;',
              'doc["features"]["keyboard"] = false;')
s = s.replace('doc["features"]["sdStorage"] = false;',
              'doc["features"]["sdStorage"] = true;')
write(p, s)

# ------------------------------------------------------------------
# Backend HTTPS + capability contract + cursor recovery
# ------------------------------------------------------------------
p = "src/backend_sync_service.cpp"
s = read(p)

if '#include <LittleFS.h>' not in s:
    s = s.replace('#include <HTTPClient.h>\n',
                  '#include <HTTPClient.h>\n#include <LittleFS.h>\n', 1)

s = s.replace('doc["capabilities"]["keyboard"] = true;',
              'doc["capabilities"]["keyboard"] = false;')
s = s.replace('doc["capabilities"]["typedRecall"] = true;',
              'doc["capabilities"]["typedRecall"] = false;')

anchor = 'doc["capabilities"]["display"] = "epaper-960x540";'
if anchor in s and 'doc["capabilities"]["microSD"]' not in s:
    s = s.replace(anchor, anchor + '\n    doc["capabilities"]["microSD"] = true;', 1)

old_https = '''    if (url.startsWith("https://")) {
        if (String(Config::BACKEND_ROOT_CA).length() == 0) {
            Serial.println("[backend] HTTPS exige BACKEND_ROOT_CA configurado");
            return false;
        }
        secure.setCACert(Config::BACKEND_ROOT_CA);
        begun = http.begin(secure, url);
    } else if (url.startsWith("http://")) {'''

new_https = '''    if (url.startsWith("https://")) {
        String rootCa =
            Config::BACKEND_ROOT_CA;

        if (
            rootCa.length() == 0 &&
            LittleFS.exists(
                Config::BACKEND_CA_FILE)
        ) {
            File caFile =
                LittleFS.open(
                    Config::BACKEND_CA_FILE,
                    "r");

            if (caFile) {
                rootCa =
                    caFile.readString();
                caFile.close();
            }
        }

        if (rootCa.length() == 0) {
            Serial.println(
                "[backend] HTTPS bloqueado: CA ausente "
                "(compile BACKEND_ROOT_CA ou grave /backend_ca.pem)");
            return false;
        }

        secure.setCACert(
            rootCa.c_str());

        begun =
            http.begin(
                secure,
                url);
    } else if (url.startsWith("http://")) {'''

s = replace_once(
    s,
    old_https,
    new_https,
    "backend https CA")

s = s.replace(
    'http.setTimeout(12000);',
    'http.setTimeout(6000);',
    1)

s = s.replace(
'''        if (status == 410) {
            Serial.println(
                "[backend] review cursor expirado; "
                "resync completo necessario");
            return false;
        }''',
'''        if (status == 410) {
            if (cursor == 0) {
                Serial.println(
                    "[backend] review cursor 0 rejeitado pelo servidor");
                return false;
            }

            Serial.println(
                "[backend] review cursor expirado; reiniciando em 0");

            if (!storage_.saveReviewCursor(0)) {
                return false;
            }

            cursor = 0;
            continue;
        }''', 1)

s = s.replace(
'''        if (status == 410) {
            Serial.println(
                "[backend] cursor de resets expirado");
            return false;
        }''',
'''        if (status == 410) {
            if (cursor == 0) {
                Serial.println(
                    "[backend] cursor de resets 0 rejeitado pelo servidor");
                return false;
            }

            Serial.println(
                "[backend] cursor de resets expirado; reiniciando em 0");

            if (!storage_.saveProgressResetCursor(0)) {
                return false;
            }

            cursor = 0;
            continue;
        }''', 1)

s = s.replace(
'''        if (status == 410) {
            Serial.println(
                "[backend] cursor de settings expirado");
            return false;
        }''',
'''        if (status == 410) {
            if (cursor == 0) {
                Serial.println(
                    "[backend] cursor de settings 0 rejeitado pelo servidor");
                return false;
            }

            Serial.println(
                "[backend] cursor de settings expirado; reiniciando em 0");

            if (!storage_.saveSettingsCursor(0)) {
                return false;
            }

            cursor = 0;
            continue;
        }''', 1)

write(p, s)

# ------------------------------------------------------------------
# Documentation
# ------------------------------------------------------------------
readme = '''# Mnemos T5 Touch — firmware 0.7

Firmware do terminal físico Mnemos para o LILYGO T5-4.7-S3 com
touchscreen capacitivo. O T5 Touch é a plataforma intermediária antes da
migração prevista para o LILYGO T5S3 Pro 4,7".

O firmware do T5 sem touch permanece independente em `firmware/t5`.

## HMI

A arquitetura HMI touch-first está congelada funcionalmente na série 0.7.
Pequenas correções visuais continuam permitidas quando forem observadas no
hardware.

## Contrato pedagógico

O T5 Touch é orientado a recuperação ativa e memorização. Nenhum tipo de
cartão exige digitação.

Todos os tipos (`open_recall`, `cloze`, `application`, `multiple_choice` e
`true_false`) seguem:

```text
enunciado
  -> tentativa mental
  -> Revelar resposta
  -> Não recuperei / Recuperei
  -> se recuperou: Difícil / Normal / Fácil
  -> FSRS
```

Cartões objetivos podem exibir alternativas, mas tocar numa alternativa não
é usado para avaliar automaticamente o usuário.

## Capabilities normativas

```text
primary=touch
touch=true
keyboard=false
typedRecall=false
microSD=true
bleSync=false
display=epaper-960x540
```

## Configuração normal e bancada

`DEMO_INTERVALS=false` é o padrão. Ensaios comprimidos precisam ser ativados
deliberadamente.

O deck de mandarim não é mais semeado automaticamente em instalações novas;
continua disponível como conteúdo importável.

## Rede

Scan e conexão iniciados pela HMI são assíncronos. Reconexão automática
também não espera em loop bloqueante.

Quando já existe Wi-Fi, LocalLink usa a LAN corrente e não tenta STA->APSTA.
SoftAP fica como fallback offline.

## Tempo

RTC PCF8563 e GT911 compartilham SDA18/SCL17. NTP é iniciado e observado de
forma assíncrona; boot/HMI não aguardam resposta de servidor.

## HTTPS

O firmware nunca usa TLS inseguro. A CA pode ser compilada em
`Config::BACKEND_ROOT_CA` ou armazenada em LittleFS como `/backend_ca.pem`.

Sem CA, HTTPS é rejeitado. HTTP permanece útil somente para laboratório/LAN.

## microSD

Pinos onboard:

- MISO GPIO16
- MOSI GPIO15
- SCK GPIO11
- CS GPIO42

A migração para biblioteca SD-first será o próximo incremento funcional,
separada da estabilização da rede.

## Build

```bash
cd firmware/t5-touch
pio run
pio run --target upload
pio device monitor -b 115200
```

## Integração externa

Requisitos para App/Web/Backend ficam em
`docs/integration/T5_TOUCH_EXTERNAL_TODO.md`. O firmware não modifica código
dessas áreas.
'''
write("README.md", readme)

changelog = read("CHANGELOG.md")
entry = '''## 0.7.0-preview.1-touch

- congela a arquitetura atual da HMI touch-first;
- desativa `DEMO_INTERVALS` no padrão normal;
- desativa seed automático de mandarim em instalações novas;
- corrige capabilities do T5 Touch;
- torna scan/conexão/reconexão Wi-Fi cooperativos;
- torna NTP não bloqueante;
- unifica todos os cartões em revelar + autoavaliação;
- aceita CA HTTPS compilada ou em `/backend_ca.pem`;
- tenta recuperar cursores HTTP 410 a partir de zero;
- atualiza documentação e TODO de integração externa.

'''
first_line, rest = changelog.split("\n", 1)
changelog = first_line.replace(
    "firmware/t5",
    "firmware/t5-touch") + "\n\n" + entry + rest.lstrip("\n")
write("CHANGELOG.md", changelog)

check = read("docs/TEST_CHECKLIST.md")
check += '''

## Série 0.7 — estabilidade funcional

- [ ] boot não espera conexão Wi-Fi;
- [ ] boot não espera NTP;
- [ ] scan Wi-Fi não congela touch;
- [ ] tentativa de conexão Wi-Fi não congela touch;
- [ ] senha incorreta retorna ao teclado;
- [ ] reconexão automática não congela a interface;
- [ ] LocalLink em LAN não muda STA para APSTA;
- [ ] open_recall usa revelar -> autoavaliação;
- [ ] cloze usa revelar -> autoavaliação;
- [ ] application usa revelar -> autoavaliação;
- [ ] multiple_choice exibe alternativas mas usa revelar -> autoavaliação;
- [ ] true_false exibe alternativas mas usa revelar -> autoavaliação;
- [ ] backend status anuncia keyboard=false;
- [ ] backend status anuncia typedRecall=false;
- [ ] backend status anuncia microSD=true;
- [ ] LocalLink info anuncia sdStorage=true;
- [ ] HTTPS sem CA é rejeitado explicitamente;
- [ ] /backend_ca.pem válido habilita HTTPS;
- [ ] cursor HTTP 410 tenta recuperação sem apagar histórico local.
'''
write("docs/TEST_CHECKLIST.md", check)

root_todo = ROOT / "../../docs/integration/T5_TOUCH_EXTERNAL_TODO.md"
root_todo.parent.mkdir(parents=True, exist_ok=True)
root_todo.write_text('''# T5 Touch — TODO de integração externa

Este arquivo registra somente dependências que pertencem a App, Web ou
Backend. O firmware não altera essas áreas.

## LocalLink / App

O QR pode usar:

- `transport=lan`: `host` é o IP atual do terminal na mesma rede;
- `transport=ap`: fallback SoftAP.

O App não deve assumir `host=192.168.4.1`.

## Capabilities

Tratar como normativo:

```text
primary=touch
touch=true
keyboard=false
typedRecall=false
microSD=true
bleSync=false
display=epaper-960x540
```

## Estudo

No T5 Touch, inclusive `multiple_choice` e `true_false` usam tentativa mental,
revelação e autoavaliação. Não inferir correção automática apenas pelo tipo.

## Timezone

Definir futuramente um campo de timezone por usuário/terminal. Preferir
identificador IANA quando o contrato compartilhado suportar; offset numérico
pode ser transitório.

## OTA

O firmware implementará a instalação, mas a distribuição depende de manifesto
externo com:

- versão;
- modelo de hardware;
- URL HTTPS;
- tamanho;
- SHA-256;
- versão de protocolo compatível;
- obrigatória/opcional.

Não distribuir OTA sem HTTPS e hash.

## Biblioteca SD-first

O firmware passará a manter decks completos no microSD e apenas um cache ativo
em RAM. `max_cards` deverá representar capacidade do cache ativo, não tamanho
máximo da biblioteca do usuário.

Snapshot/sync não deve presumir que toda a biblioteca cabe simultaneamente em
RAM.

## Redes corporativas

Credenciais EAP/certificados devem continuar vindo por provisionamento externo.

## T5S3 Pro

A migração futura deve preservar os contratos acima e expor novas capacidades
de bateria/PMIC via capability.
''', encoding="utf-8")

# guards
guards = {
    "version": '0.7.0-preview.1-touch' in read("include/config.h"),
    "demo off": 'DEMO_INTERVALS = false' in read("include/config.h"),
    "seed off": 'SEED_MANDARIN_TRAINING_DECK = false' in read("include/config.h"),
    "async wifi": 'startConnectSavedSsidAsync' in read("include/network_service.h"),
    "async ntp": 'NTP assincrono iniciado' in read("src/time_service.cpp"),
    "objective reveal": 'drawPrimaryButton(\n        "Ver resposta");' in read("src/t5_display.cpp"),
    "cap local": 'doc["features"]["keyboard"] = false;' in read("src/local_link_service.cpp"),
    "cap backend": 'doc["capabilities"]["typedRecall"] = false;' in read("src/backend_sync_service.cpp"),
    "https ca": 'Config::BACKEND_CA_FILE' in read("src/backend_sync_service.cpp"),
}

bad = [k for k, v in guards.items() if not v]
if bad:
    raise RuntimeError("validacao final falhou: " + ", ".join(bad))

print("[OK] v0.7.0-preview.1 aplicada")
print("[OK] Wi-Fi e NTP cooperativos")
print("[OK] autoavaliacao uniforme")
print("[OK] capabilities corrigidas")
print("[OK] HTTPS com CA compilada ou LittleFS")
print("[OK] documentacao e TODO externo atualizados")
