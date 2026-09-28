
from pathlib import Path
import re
import shutil

ROOT = Path.cwd()
PKG = Path(__file__).resolve().parent

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")

def write(rel, text):
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")

# New service files.
shutil.copy2(
    PKG / "payload/include/power_service.h",
    ROOT / "include/power_service.h")
shutil.copy2(
    PKG / "payload/src/power_service.cpp",
    ROOT / "src/power_service.cpp")

# config.h
p = "include/config.h"
s = read(p)

if "0.7.0-preview.1.1-touch" not in s:
    raise RuntimeError(
        "baseline esperada 0.7.0-preview.1.1-touch")

s = re.sub(
    r'constexpr char APP_VERSION\[\]\s*=\s*"[^"]+"\s*;',
    'constexpr char APP_VERSION[] = "0.7.0-preview.2-touch";',
    s,
    count=1)

battery_anchor = (
    "constexpr uint8_t "
    "BATTERY_DISPLAY_STEP_PERCENT = 5;\n"
)

if battery_anchor not in s:
    raise RuntimeError("config battery anchor ausente")

s = s.replace(
    battery_anchor,
    battery_anchor + r'''
constexpr uint8_t BATTERY_LOW_PERCENT = 15;
constexpr uint8_t BATTERY_CRITICAL_PERCENT = 5;

// Política de energia da T5 Touch atual.
constexpr bool LIGHT_SLEEP_ENABLED = true;
constexpr bool DEEP_SLEEP_ENABLED = true;
constexpr uint32_t LIGHT_SLEEP_IDLE_MS =
    2U * 60U * 1000U;
constexpr uint32_t DEEP_SLEEP_IDLE_MS =
    20U * 60U * 1000U;
constexpr uint32_t LIGHT_SLEEP_MAX_TIMER_MS =
    20U * 60U * 1000U;
constexpr uint32_t DEEP_SLEEP_MAINTENANCE_SECONDS =
    6U * 60U * 60U;
''',
    1)

write(p, s)

# board_config.h
p = "include/board_config.h"
s = read(p)
s = s.replace(
    "constexpr bool USE_SD = false;",
    "constexpr bool USE_SD = true;")
write(p, s)

# BatteryService
p = "include/battery_service.h"
s = read(p)

if '#include "config.h"' not in s:
    s = s.replace(
        '#include <Arduino.h>\n',
        '#include <Arduino.h>\n'
        '#include "config.h"\n',
        1)

anchor = '''    bool available() const { return available_; }
    uint8_t percent() const { return displayPercent_; }
    float voltage() const { return voltage_; }
'''

if anchor not in s:
    raise RuntimeError("battery header anchor ausente")

s = s.replace(
    anchor,
    anchor + '''
    bool low() const {
        return
            available_ &&
            displayPercent_ <=
                Config::BATTERY_LOW_PERCENT;
    }

    bool critical() const {
        return
            available_ &&
            displayPercent_ <=
                Config::BATTERY_CRITICAL_PERCENT;
    }
''',
    1)

write(p, s)

# Network sleep lifecycle
p = "include/network_service.h"
s = read(p)

anchor = '''    bool busy() const {
        return asyncState_ != NetworkAsyncState::Idle;
    }

    void disable();
'''

if anchor not in s:
    raise RuntimeError("network sleep anchor ausente")

s = s.replace(
    anchor,
    '''    bool busy() const {
        return asyncState_ != NetworkAsyncState::Idle;
    }

    void suspendForSleep();
    void resumeAfterSleep();

    void disable();
''',
    1)

write(p, s)

p = "src/network_service.cpp"
s = read(p)
marker = "void NetworkService::disable()"
pos = s.find(marker)

if pos < 0:
    raise RuntimeError("network disable marker ausente")

impl = r'''void NetworkService::suspendForSleep() {
    if (
        asyncState_ !=
        NetworkAsyncState::Idle
    ) {
        return;
    }

    WiFi.disconnect(
        false,
        false);

    WiFi.mode(
        WIFI_OFF);

    connectedSsid_ = "";

    Serial.println(
        "[wifi] radio suspenso");
}


void NetworkService::resumeAfterSleep() {
    if (
        !enabled_ ||
        !hasCredentials()
    ) {
        return;
    }

    WiFi.mode(
        WIFI_STA);

    lastReconnectAttemptMs_ = 0;
    reconnectBackoffMs_ = 0;

    Serial.println(
        "[wifi] radio retomado");
}


'''

s = s[:pos] + impl + s[pos:]
write(p, s)

# SD sleep lifecycle
p = "include/sd_card_service.h"
s = read(p)

anchor = '''    bool begin();
    bool remount();
    bool mounted() const { return mounted_; }
'''

if anchor not in s:
    raise RuntimeError("sd header anchor ausente")

s = s.replace(
    anchor,
    '''    bool begin();
    bool remount();
    void suspend();
    bool resume();
    bool mounted() const { return mounted_; }
''',
    1)

write(p, s)

p = "src/sd_card_service.cpp"
s = read(p)
marker = "bool SdCardService::ensureFolders()"
pos = s.find(marker)

if pos < 0:
    raise RuntimeError("sd ensureFolders marker ausente")

impl = r'''void SdCardService::suspend() {
    if (!mounted_) {
        return;
    }

    SD.end();
    SPI.end();
    mounted_ = false;

    Serial.println(
        "[sd] suspenso para economia de energia");
}


bool SdCardService::resume() {
    return remount();
}


'''

s = s[:pos] + impl + s[pos:]
write(p, s)

# StudyEngine checkpoint
p = "include/study_engine.h"
s = read(p)

anchor = (
    "    bool commitCurrent("
    "Outcome outcome, Effort effort);\n"
)

if anchor not in s:
    raise RuntimeError("study header anchor ausente")

s = s.replace(
    anchor,
    anchor + '''
    void prepareForSleep();
''',
    1)

write(p, s)

p = "src/study_engine.cpp"
s = read(p)
marker = "void StudyEngine::persistSession()"
pos = s.find(marker)

if pos < 0:
    raise RuntimeError("study persist marker ausente")

impl = r'''void StudyEngine::prepareForSleep() {
    storage_.saveStates(
        states_,
        count_);

    if (resumableSession_) {
        persistSession();
    }
}


'''

s = s[:pos] + impl + s[pos:]
write(p, s)

# TimeService runtime timezone
p = "include/time_service.h"
s = read(p)

if '#include "config.h"' not in s:
    s = s.replace(
        '#include <SensorPCF8563.hpp>\n',
        '#include <SensorPCF8563.hpp>\n'
        '#include "config.h"\n',
        1)

pub_anchor = '''    bool ntpSynchronized() const { return ntpSynchronized_; }

    void setFromEpoch(uint32_t epochSeconds);
'''

if pub_anchor not in s:
    raise RuntimeError("time public anchor ausente")

s = s.replace(
    pub_anchor,
    '''    bool ntpSynchronized() const { return ntpSynchronized_; }

    int32_t utcOffsetSeconds() const {
        return utcOffsetSeconds_;
    }

    int32_t daylightOffsetSeconds() const {
        return daylightOffsetSeconds_;
    }

    bool setTimezoneOffsetSeconds(
        int32_t utcOffsetSeconds,
        int32_t daylightOffsetSeconds = 0);

    void setFromEpoch(uint32_t epochSeconds);
''',
    1)

priv_anchor = '''    bool ntpPending_ = false;

    bool tryNtp(uint32_t waitMs);  // legado; fora do fluxo normal
'''

if priv_anchor not in s:
    raise RuntimeError("time private anchor ausente")

s = s.replace(
    priv_anchor,
    '''    bool ntpPending_ = false;

    int32_t utcOffsetSeconds_ =
        Config::GMT_OFFSET_SECONDS;

    int32_t daylightOffsetSeconds_ =
        Config::DAYLIGHT_OFFSET_SECONDS;

    bool tryNtp(uint32_t waitMs);  // legado; fora do fluxo normal
''',
    1)

write(p, s)

p = "src/time_service.cpp"
s = read(p)

begin_marker = '''    preferences_.begin(
        "mnemos-clock",
        false);
'''

if begin_marker not in s:
    raise RuntimeError("time begin preferences anchor ausente")

load_tz = begin_marker + '''
    utcOffsetSeconds_ =
        preferences_.getInt(
            "tzOffset",
            Config::
                GMT_OFFSET_SECONDS);

    daylightOffsetSeconds_ =
        preferences_.getInt(
            "dstOffset",
            Config::
                DAYLIGHT_OFFSET_SECONDS);

    if (
        utcOffsetSeconds_ <
            -12L * 3600L ||
        utcOffsetSeconds_ >
            14L * 3600L
    ) {
        utcOffsetSeconds_ =
            Config::
                GMT_OFFSET_SECONDS;
    }

    if (
        daylightOffsetSeconds_ <
            -2L * 3600L ||
        daylightOffsetSeconds_ >
            2L * 3600L
    ) {
        daylightOffsetSeconds_ =
            Config::
                DAYLIGHT_OFFSET_SECONDS;
    }

    Serial.printf(
        "[clock] timezone UTC%+ld s dst=%+ld s\\n",
        static_cast<long>(
            utcOffsetSeconds_),
        static_cast<long>(
            daylightOffsetSeconds_));
'''

s = s.replace(begin_marker, load_tz, 1)

s = s.replace(
    "Config::GMT_OFFSET_SECONDS",
    "utcOffsetSeconds_")
s = s.replace(
    "Config::DAYLIGHT_OFFSET_SECONDS",
    "daylightOffsetSeconds_")

marker = "bool TimeService::tryNtp("
pos = s.find(marker)

if pos < 0:
    raise RuntimeError("time tryNtp marker ausente")

tz_impl = r'''bool TimeService::setTimezoneOffsetSeconds(
    int32_t utcOffsetSeconds,
    int32_t daylightOffsetSeconds) {

    if (
        utcOffsetSeconds <
            -12L * 3600L ||
        utcOffsetSeconds >
            14L * 3600L ||
        daylightOffsetSeconds <
            -2L * 3600L ||
        daylightOffsetSeconds >
            2L * 3600L
    ) {
        return false;
    }

    if (
        utcOffsetSeconds_ ==
            utcOffsetSeconds &&
        daylightOffsetSeconds_ ==
            daylightOffsetSeconds
    ) {
        return true;
    }

    const uint32_t current =
        now();

    utcOffsetSeconds_ =
        utcOffsetSeconds;

    daylightOffsetSeconds_ =
        daylightOffsetSeconds;

    preferences_.putInt(
        "tzOffset",
        utcOffsetSeconds_);

    preferences_.putInt(
        "dstOffset",
        daylightOffsetSeconds_);

    if (
        current >=
        MIN_VALID_EPOCH
    ) {
        writeRtc(current);
    }

    Serial.printf(
        "[clock] timezone atualizado utc=%+ld dst=%+ld\\n",
        static_cast<long>(
            utcOffsetSeconds_),
        static_cast<long>(
            daylightOffsetSeconds_));

    return true;
}


'''

s = s[:pos] + tz_impl + s[pos:]
write(p, s)

# main.cpp
p = "src/main.cpp"
s = read(p)

if '#include "power_service.h"' not in s:
    s = s.replace(
        '#include "network_service.h"\n',
        '#include "network_service.h"\n'
        '#include "power_service.h"\n',
        1)

global_anchor = '''NetworkService networkService;
SdCardService sdCardService;
TimeService clockService;
'''

if global_anchor not in s:
    raise RuntimeError("main service globals anchor ausente")

s = s.replace(
    global_anchor,
    '''NetworkService networkService;
SdCardService sdCardService;
TimeService clockService;
PowerService powerService;
''',
    1)

s = s.replace(
    '''            Config::GMT_OFFSET_SECONDS) +
        static_cast<int64_t>(
            Config::DAYLIGHT_OFFSET_SECONDS);''',
    '''            clockService.utcOffsetSeconds()) +
        static_cast<int64_t>(
            clockService.daylightOffsetSeconds());''',
    1)

s = s.replace(
    '''            Config::GMT_OFFSET_SECONDS) -
        static_cast<int64_t>(
            Config::DAYLIGHT_OFFSET_SECONDS);''',
    '''            clockService.utcOffsetSeconds()) -
        static_cast<int64_t>(
            clockService.daylightOffsetSeconds());''',
    1)

s = s.replace(
    '''        Config::GMT_OFFSET_SECONDS +
        Config::DAYLIGHT_OFFSET_SECONDS;''',
    '''        clockService.utcOffsetSeconds() +
        clockService.daylightOffsetSeconds();''',
    1)

setup_anchor = '''    batteryService.begin();

    display.setBatteryStatus(
'''

if setup_anchor not in s:
    raise RuntimeError("main battery setup anchor ausente")

s = s.replace(
    setup_anchor,
    '''    batteryService.begin();
    powerService.begin();

    display.setBatteryStatus(
''',
    1)

marker = "void setup()"
pos = s.find(marker)

if pos < 0:
    raise RuntimeError("main setup marker ausente")

helper = r'''bool powerSleepAllowed() {
    if (
        localLink.active() ||
        networkService.busy()
    ) {
        return false;
    }

    switch (screen) {
        case AppScreen::WifiNetworks:
        case AppScreen::WifiPassword:
        case AppScreen::WifiMessage:
        case AppScreen::LocalLink:
            return false;

        default:
            return true;
    }
}


void prepareForSleep() {
    clockService.checkpoint();

    if (engine) {
        engine->prepareForSleep();
    } else {
        storage.saveStates(
            states,
            cardCount);
    }
}


void performLightSleep() {
    prepareForSleep();

    const bool resumeSd =
        sdCardService.mounted();

    sdCardService.suspend();
    networkService.suspendForSleep();

    const PowerWakeReason wake =
        powerService.enterLightSleep();

    touchInput.begin();

    touchInput.setPortrait(
        display.portrait());

    if (resumeSd) {
        sdCardService.resume();
    }

    networkService.resumeAfterSleep();

    if (
        wake ==
        PowerWakeReason::TouchOrButton
    ) {
        powerService.noteActivity();
    }
}


void performDeepSleep() {
    prepareForSleep();

    sdCardService.suspend();
    networkService.suspendForSleep();

    Serial.println(
        "[app] entrando em deep sleep; acorde pelo botao GPIO21");

    delay(20);

    powerService.enterDeepSleep();
}


'''

s = s[:pos] + helper + s[pos:]

battery_block = '''    if (
        batteryService.update()
    ) {
        display.setBatteryStatus(
            batteryService.available(),
            batteryService.percent());
    }

'''

if battery_block not in s:
    raise RuntimeError("main battery loop block ausente")

s = s.replace(
    battery_block,
    battery_block + '''    const PowerDecision powerDecision =
        powerService.evaluate(
            powerSleepAllowed(),
            batteryService.critical());

    if (
        powerDecision ==
        PowerDecision::DeepSleep
    ) {
        performDeepSleep();
        return;
    }

    if (
        powerDecision ==
        PowerDecision::LightSleep
    ) {
        performLightSleep();
    }

''',
    1)

touch_anchor = '''    lastAcceptedTouchMs =
        now;

    display.showTouchFeedback(
'''

if touch_anchor not in s:
    raise RuntimeError("main accepted touch anchor ausente")

s = s.replace(
    touch_anchor,
    '''    lastAcceptedTouchMs =
        now;

    powerService.noteActivity();

    display.showTouchFeedback(
''',
    1)

write(p, s)

# capabilities
p = "src/local_link_service.cpp"
s = read(p)
cap_anchor = 'doc["features"]["sdStorage"] = true;'

if cap_anchor in s and "deepSleepTouchWake" not in s:
    s = s.replace(
        cap_anchor,
        cap_anchor + '''
        doc["features"]["lightSleep"] = true;
        doc["features"]["deepSleep"] = true;
        doc["features"]["deepSleepTouchWake"] = false;
''',
        1)

write(p, s)

p = "src/backend_sync_service.cpp"
s = read(p)
cap_anchor = 'doc["capabilities"]["microSD"] = true;'

if cap_anchor in s and "deepSleepTouchWake" not in s:
    s = s.replace(
        cap_anchor,
        cap_anchor + '''
    doc["capabilities"]["lightSleep"] = true;
    doc["capabilities"]["deepSleep"] = true;
    doc["capabilities"]["deepSleepTouchWake"] = false;
''',
        1)

write(p, s)

# Documentation.
readme = read("README.md")

if "## Gerenciamento de energia" not in readme:
    readme += r'''

## Gerenciamento de energia

A `0.7.0-preview.2` introduz política em dois níveis.

Após 2 minutos sem interação, quando não há LocalLink nem operação de rede em
andamento, o terminal entra em **light sleep**. Touch GPIO47 e botão GPIO21
podem acordá-lo.

Após 20 minutos de inatividade, ou quando uma bateria detectada chega a 5%,
o terminal entra em **deep sleep**. Na placa T5-4.7-S3 atual o GT911 está no
GPIO47, que não é RTC IO; portanto o touch não acorda deep sleep sem alteração
física. O wake suportado é o botão GPIO21, além de um timer de manutenção a
cada 6 horas.

Antes de dormir, FSRS/sessão e relógio são persistidos, microSD é desmontado e
Wi-Fi é desligado sem alterar a preferência de rede do usuário. Após light
sleep esses serviços são retomados.

Os limiares de 15% (bateria baixa) e 5% (crítica) são provisórios para a T5
atual e devem ser reavaliados na futura T5S3 Pro.

## Timezone

`TimeService` passa a persistir `tzOffset` e `dstOffset` em Preferences.
`Config::GMT_OFFSET_SECONDS` e `DAYLIGHT_OFFSET_SECONDS` continuam como
fallback. A agenda e o cálculo do dia acadêmico usam o offset efetivo.

O offset UTC aceito vai de UTC-12 a UTC+14.
'''

write("README.md", readme)

changelog = read("CHANGELOG.md")
entry = '''## 0.7.0-preview.2-touch

- adiciona `PowerService`;
- light sleep com wake por touch GPIO47 e botão GPIO21;
- deep sleep com wake por botão GPIO21 e timer de manutenção;
- deep sleep automático em bateria crítica;
- persiste sessão/FSRS e checkpoint do relógio antes do sleep;
- suspende/retoma Wi-Fi e microSD em light sleep;
- corrige `BoardConfig::USE_SD=true`;
- timezone passa a ser persistido em Preferences e usado pela agenda;
- anuncia `deepSleepTouchWake=false`;
- mantém a HMI congelada.

'''

first, rest = changelog.split("\n", 1)
changelog = first + "\n\n" + entry + rest.lstrip("\n")
write("CHANGELOG.md", changelog)

check = read("docs/TEST_CHECKLIST.md")
check += r'''

## Série 0.7 preview.2 — energia e timezone

- [ ] após 2 min o terminal entra em light sleep quando ocioso;
- [ ] toque acorda do light sleep;
- [ ] botão GPIO21 acorda do light sleep;
- [ ] sessão continua retomável depois do sleep;
- [ ] SD volta a montar após light sleep se estava presente;
- [ ] Wi-Fi reconecta assincronamente após light sleep;
- [ ] após 20 min o terminal entra em deep sleep;
- [ ] touch GPIO47 não é anunciado como wake de deep sleep;
- [ ] botão GPIO21 acorda/reinicia do deep sleep;
- [ ] wake periódico de 6 h inicializa normalmente;
- [ ] bateria <=5% força deep sleep somente quando detectada;
- [ ] agenda usa offset persistido;
- [ ] mudança de timezone reescreve RTC preservando UTC.
'''

write("docs/TEST_CHECKLIST.md", check)

todo_path = (
    ROOT /
    "../../docs/integration/T5_TOUCH_EXTERNAL_TODO.md"
)

if todo_path.exists():
    todo = todo_path.read_text(encoding="utf-8")

    if "## Energia / wake" not in todo:
        todo += r'''

## Energia / wake

A T5-4.7-S3 atual anuncia `deepSleepTouchWake=false`: o GT911 usa GPIO47 e
não pode acordar EXT0/EXT1 no ESP32-S3. Interfaces externas não devem instruir
o usuário a tocar para acordar quando o terminal estiver em deep sleep. O wake
suportado é o botão onboard GPIO21.

No futuro T5S3 Pro essa capability deve ser reavaliada.
'''

    todo_path.write_text(
        todo,
        encoding="utf-8")

guards = {
    "version":
        "0.7.0-preview.2-touch" in
        read("include/config.h"),
    "power h":
        (ROOT / "include/power_service.h").exists(),
    "power cpp":
        (ROOT / "src/power_service.cpp").exists(),
    "sleep checkpoint":
        "prepareForSleep" in
        read("src/study_engine.cpp"),
    "network suspend":
        "suspendForSleep" in
        read("src/network_service.cpp"),
    "sd suspend":
        "SdCardService::suspend" in
        read("src/sd_card_service.cpp"),
    "timezone prefs":
        '"tzOffset"' in
        read("src/time_service.cpp"),
    "runtime agenda tz":
        "clockService.utcOffsetSeconds()" in
        read("src/main.cpp"),
    "touch activity":
        "powerService.noteActivity();" in
        read("src/main.cpp"),
    "use sd":
        "USE_SD = true" in
        read("include/board_config.h"),
}

bad = [
    name
    for name, ok in guards.items()
    if not ok
]

if bad:
    raise RuntimeError(
        "validacao falhou: " +
        ", ".join(bad))

print("[OK] 0.7.0-preview.2-touch aplicada")
print("[OK] PowerService + light/deep sleep")
print("[OK] persistencia antes de sleep")
print("[OK] timezone persistente")
print("[OK] HMI/layout nao alterados")
