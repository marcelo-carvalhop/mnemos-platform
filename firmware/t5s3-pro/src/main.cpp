#include <Arduino.h>
#include <algorithm>
#include <Preferences.h>
#include <Wire.h>
#include <ctime>

#include "backend_sync_service.h"
#include "backlight_service.h"
#include "battery_service.h"
#include "cards.h"
#include <cstring>

#include "config.h"
#include "hmi_layout.h"
#include "local_link_service.h"
#include "metrics_service.h"
#include "network_service.h"
#include "ota_service.h"
#include "platform_sync_config.h"
#include "power_service.h"
#include "schedule_service.h"
#include "sd_card_service.h"
#include "serial_console.h"
#include "storage.h"
#include "study_engine.h"
#include "t5_display.h"
#include "terminal_identity.h"
#include "time_service.h"
#include "touch_input.h"
#include "ui_actions.h"
#include "wifi_keyboard.h"

enum class AppScreen : uint8_t {
    Home,
    Menu,
    Decks,
    Agenda,
    Sync,
    Connection,
    WifiNetworks,
    WifiPassword,
    WifiMessage,
    Storage,
    Settings,
    LocalLink,
    Question,
    SelfAssessment,
    ObjectiveFeedback,
    Effort,
    Summary,
    AbortConfirm,
};

struct TouchZone {
    const char* name = "none";
    int16_t x = 0;
    int16_t y = 0;
    int16_t w = 0;
    int16_t h = 0;
    UiAction action = UiAction::None;
    int8_t argument = -1;
};

struct RoutedTouch {
    UiAction action = UiAction::None;
    int8_t argument = -1;
    const char* zone = "none";
    int16_t x = 0;
    int16_t y = 0;
    int16_t w = 0;
    int16_t h = 0;
};

constexpr size_t MAX_VISIBLE_DECKS = 5;

BatteryService batteryService;
BacklightService backlightService;
Preferences uiPreferences;
Storage storage;
NetworkService networkService;
SdCardService sdCardService;
TimeService clockService;
PowerService powerService;
OtaService otaService;
T5Display display;
TouchInput touchInput;

CardDefinition cards[Config::MAX_DEVICE_CARDS];
CardState states[Config::MAX_DEVICE_CARDS];
size_t cardCount = 0;

ScheduleService scheduleService(
    clockService,
    states,
    cardCount);

StudyEngine* engine = nullptr;

MetricsService metrics(
    storage,
    clockService,
    cards,
    states,
    cardCount);

LocalLinkService localLink(
    storage,
    clockService,
    networkService,
    metrics,
    cards,
    states,
    Config::MAX_DEVICE_CARDS,
    cardCount);

BackendSyncService backendSync(
    networkService,
    storage,
    clockService,
    cards,
    states,
    Config::MAX_DEVICE_CARDS,
    cardCount);

AppScreen screen =
    AppScreen::Home;

AppScreen abortReturnScreen =
    AppScreen::Question;

Outcome pendingOutcome =
    Outcome::Unknown;

uint32_t lastTouchRetryMs = 0;
uint32_t lastAcceptedTouchMs = 0;

bool powerOffRequested = false;
bool networkRadioSuspended = false;
uint32_t lastNetworkDemandMs = 0;

bool localLinkProvisioning = false;

SerialConsole serialConsole;

// Para onde o botão da tela de mensagem volta. As mensagens de Wi-Fi voltam
// para Conexão; as de sincronização, para Sincronização.
AppScreen messageReturnScreen = AppScreen::Connection;

bool lastWifiConnected = false;

void canonicalizeActiveLibraryIfPossible();
void finishLocalLinkScreen();
void handleSerialCommand(JsonDocument& command);
void prepareForSleep();

DeckSummary deckView[MAX_VISIBLE_DECKS];
size_t deckViewCount = 0;

String selectedDeckIds[MAX_VISIBLE_DECKS];
size_t selectedDeckCount = 0;

NetworkScanResult wifiScan[NetworkService::MAX_SCAN_RESULTS];
size_t wifiScanCount = 0;
int8_t wifiSelectedIndex = -1;
String wifiPassword;
WifiKeyboardPage wifiKeyboardPage = WifiKeyboardPage::Lower;
String wifiHint;
String wifiMessageTitle;
String wifiMessageText;
String wifiMessagePrimary = "Voltar à conexão";
bool wifiConnectRetryPassword = false;
bool wifiUserConnectionPending = false;

String sdPaths[SdCardService::MAX_VISIBLE_FILES];
String sdNames[SdCardService::MAX_VISIBLE_FILES];
uint32_t sdSizes[SdCardService::MAX_VISIBLE_FILES] = {0};
size_t sdFileCount = 0;
String sdStatus;

CardDefinition displayCardBuffer;


void noteNetworkDemand() {
    lastNetworkDemandMs = millis();

    if (networkRadioSuspended) {
        networkRadioSuspended = false;
        networkService.resumeAfterSleep();
        Serial.println(
            "[wifi] radio reativado por demanda do usuário");
    }
}

void serviceNetworkPowerPolicy() {
    if (networkService.busy() || localLink.active()) {
        lastNetworkDemandMs = millis();
        return;
    }

    if (networkRadioSuspended) {
        return;
    }

    if (millis() - lastNetworkDemandMs <
        Config::WIFI_RADIO_IDLE_OFF_MS) {
        return;
    }

    networkService.forceRadioOff();
    networkRadioSuspended = true;
}

bool activeStudyForPowerPolicy() {
    switch (screen) {
        case AppScreen::Question:
        case AppScreen::SelfAssessment:
        case AppScreen::ObjectiveFeedback:
        case AppScreen::Effort:
        case AppScreen::AbortConfirm:
            return true;
        default:
            return false;
    }
}

void rebuildEngine() {
    if (engine != nullptr) {
        delete engine;
        engine = nullptr;
    }

    engine =
        new StudyEngine(
            cards,
            states,
            cardCount,
            storage,
            clockService);

    engine->initializeStates();
}

uint32_t academicDayStart(
    uint32_t epoch) {

    const int64_t local =
        static_cast<int64_t>(epoch) +
        static_cast<int64_t>(
            clockService.utcOffsetSeconds()) +
        static_cast<int64_t>(
            clockService.daylightOffsetSeconds());

    const int64_t cutoff =
        static_cast<int64_t>(
            Config::DAY_CUTOFF_HOUR) *
        3600LL;

    const int64_t shifted =
        local -
        cutoff;

    const int64_t startLocal =
        (
            shifted /
            86400LL
        ) *
            86400LL +
        cutoff;

    const int64_t utc =
        startLocal -
        static_cast<int64_t>(
            clockService.utcOffsetSeconds()) -
        static_cast<int64_t>(
            clockService.daylightOffsetSeconds());

    return
        utc > 0
            ? static_cast<uint32_t>(
                  utc)
            : 0U;
}

String weeklyDayLabel(
    uint32_t epoch) {

    static const char* NAMES[] = {
        "DOM",
        "SEG",
        "TER",
        "QUA",
        "QUI",
        "SEX",
        "SÁB"
    };

    time_t shifted =
        static_cast<time_t>(epoch) +
        clockService.utcOffsetSeconds() +
        clockService.daylightOffsetSeconds();

    tm value{};
    gmtime_r(
        &shifted,
        &value);

    char buffer[20];

    snprintf(
        buffer,
        sizeof(buffer),
        "%s %02d/%02d",
        NAMES[value.tm_wday],
        value.tm_mday,
        value.tm_mon + 1);

    return
        String(buffer);
}

void addDeckToPlan(
    WeeklyPlanDay& day,
    const String& deck) {

    if (
        deck.length() == 0 ||
        day.decks.indexOf(
            deck) >= 0
    ) {
        return;
    }

    if (
        day.decks.length() == 0
    ) {
        day.decks =
            deck;
        return;
    }

    if (
        day.decks.length() < 30
    ) {
        day.decks += ", ";
        day.decks += deck;
    } else if (
        !day.decks.endsWith("+")
    ) {
        day.decks += " +";
    }
}

void buildWeeklyPlan(
    WeeklyPlanDay* days) {

    const uint32_t now =
        clockService.now();

    const uint32_t todayStart =
        academicDayStart(now);

    for (
        uint8_t day = 0;
        day < 7;
        ++day
    ) {
        days[day] =
            WeeklyPlanDay{};

        days[day].today =
            day == 0;

        days[day].label =
            weeklyDayLabel(
                todayStart +
                day * 86400U);
    }

    for (
        size_t i = 0;
        i < cardCount;
        ++i
    ) {
        uint8_t dayIndex = 0;

        if (
            states[i].fsrsInitialized &&
            states[i].fsrsDueAtMs > 0
        ) {
            const uint32_t dueEpoch =
                static_cast<uint32_t>(
                    states[i].
                        fsrsDueAtMs /
                    1000ULL);

            if (dueEpoch > now) {
                const uint32_t dueDay =
                    academicDayStart(
                        dueEpoch);

                const uint32_t delta =
                    dueDay > todayStart
                        ? (
                              dueDay -
                              todayStart
                          ) /
                              86400U
                        : 0U;

                if (delta > 6) {
                    continue;
                }

                dayIndex =
                    static_cast<uint8_t>(
                        delta);
            }
        }

        ++days[dayIndex].cards;

        addDeckToPlan(
            days[dayIndex],
            cards[i].deck);
    }
}

const char* appScreenName(
    AppScreen value) {

    switch (value) {
        case AppScreen::Home:
            return "Home";
        case AppScreen::Menu:
            return "Menu";
        case AppScreen::Decks:
            return "Decks";
        case AppScreen::Agenda:
            return "Agenda";
        case AppScreen::Sync:
            return "Sync";
        case AppScreen::Connection:
            return "Connection";
        case AppScreen::WifiNetworks:
            return "WifiNetworks";
        case AppScreen::WifiPassword:
            return "WifiPassword";
        case AppScreen::WifiMessage:
            return "WifiMessage";
        case AppScreen::Storage:
            return "Storage";
        case AppScreen::Settings:
            return "Settings";
        case AppScreen::LocalLink:
            return "LocalLink";
        case AppScreen::Question:
            return "Question";
        case AppScreen::SelfAssessment:
            return "SelfAssessment";
        case AppScreen::ObjectiveFeedback:
            return "ObjectiveFeedback";
        case AppScreen::Effort:
            return "Effort";
        case AppScreen::Summary:
            return "Summary";
        case AppScreen::AbortConfirm:
            return "AbortConfirm";
    }

    return "Unknown";
}

bool activeStudyScreen() {
    return
        screen ==
            AppScreen::Question ||
        screen ==
            AppScreen::SelfAssessment ||
        screen ==
            AppScreen::ObjectiveFeedback ||
        screen ==
            AppScreen::Effort;
}

bool homeAvailable() {
    return
        screen != AppScreen::Home &&
        screen != AppScreen::LocalLink &&
        screen != AppScreen::AbortConfirm;
}


bool menuAvailable() {
    return
        screen == AppScreen::Home ||
        screen == AppScreen::Menu ||
        screen == AppScreen::Decks ||
        screen == AppScreen::Sync ||
        screen == AppScreen::Connection ||
        screen == AppScreen::Settings ||
        screen == AppScreen::Storage;
}



bool orientationAvailable() {
    return false;
}


/*
 * Telas com a barra de abas do web no celular (Hoje, Baralhos, Estudar,
 * Sincronizar, Mais). Nelas os ícones antigos do topo não existem: a
 * navegação é toda pelas abas.
 */
void addZone(
    TouchZone* zones,
    size_t& count,
    const char* name,
    int16_t x,
    int16_t y,
    int16_t w,
    int16_t h,
    UiAction action,
    int8_t argument = -1);

bool tabbedScreen() {
    switch (screen) {
        case AppScreen::Home:
        case AppScreen::Menu:
        case AppScreen::Decks:
        case AppScreen::Agenda:
        case AppScreen::Sync:
        case AppScreen::Connection:
        case AppScreen::Settings:
        case AppScreen::Storage:
            return true;
        default:
            return false;
    }
}

void addTabZones(TouchZone* zones, size_t& count) {
    static const char* const NAMES[HmiLayout::TAB_COUNT] = {
        "tab_today", "tab_decks", "tab_study", "tab_sync", "tab_more"};
    static const UiAction ACTIONS[HmiLayout::TAB_COUNT] = {
        UiAction::Home,
        UiAction::OpenDecks,
        UiAction::PrimaryStudy,
        UiAction::OpenSync,
        UiAction::OpenMenu};

    for (uint8_t i = 0; i < HmiLayout::TAB_COUNT; ++i) {
        const HmiLayout::Rect r = HmiLayout::tab(i);
        if (ACTIONS[i] == UiAction::Home && screen == AppScreen::Home) {
            continue;
        }
        addZone(zones, count, NAMES[i], r.x, r.y, r.w, r.h, ACTIONS[i]);
    }

    // Subtelas do "Mais": "‹ Voltar" no topo.
    if (
        screen == AppScreen::Settings ||
        screen == AppScreen::Connection ||
        screen == AppScreen::Storage ||
        screen == AppScreen::Agenda
    ) {
        addZone(zones, count, "top_back", 0, 0, 200, HmiLayout::TOP_BAR_H,
                UiAction::Back);
    }
}


bool isDeckSelected(
    const String& deckId) {

    for (
        size_t i = 0;
        i < selectedDeckCount;
        ++i
    ) {
        if (
            selectedDeckIds[i] ==
            deckId
        ) {
            return true;
        }
    }

    return false;
}

void clearDeckSelection() {
    selectedDeckCount = 0;

    for (
        size_t i = 0;
        i < MAX_VISIBLE_DECKS;
        ++i
    ) {
        selectedDeckIds[i] =
            "";
    }
}

void buildDeckView() {
    deckViewCount = 0;

    for (
        size_t i = 0;
        i < MAX_VISIBLE_DECKS;
        ++i
    ) {
        deckView[i] =
            DeckSummary{};
    }

    const uint32_t now =
        clockService.now();

    for (
        size_t cardIndex = 0;
        cardIndex < cardCount;
        ++cardIndex
    ) {
        const String& deckId =
            cards[cardIndex].deckId;

        if (
            deckId.length() == 0
        ) {
            continue;
        }

        size_t deckIndex = 0;

        while (
            deckIndex <
                deckViewCount &&
            deckView[deckIndex].id !=
                deckId
        ) {
            ++deckIndex;
        }

        if (
            deckIndex ==
            deckViewCount
        ) {
            if (
                deckViewCount >=
                MAX_VISIBLE_DECKS
            ) {
                continue;
            }

            deckView[deckIndex].id =
                deckId;

            deckView[deckIndex].name =
                cards[cardIndex].deck;

            ++deckViewCount;
        }

        ++deckView[
            deckIndex].
            cardCount;

        const uint64_t nowMs =
            static_cast<uint64_t>(
                now) *
            1000ULL;

        if (
            !states[cardIndex].
                fsrsInitialized ||
            states[cardIndex].
                fsrsDueAtMs == 0 ||
            states[cardIndex].
                fsrsDueAtMs <=
                nowMs
        ) {
            ++deckView[
                deckIndex].
                dueCount;
        }
    }

    for (
        size_t i = 0;
        i < deckViewCount;
        ++i
    ) {
        deckView[i].selected =
            isDeckSelected(
                deckView[i].id);
    }
}

void toggleDeckSelection(
    int8_t viewIndex) {

    buildDeckView();

    if (
        viewIndex < 0 ||
        static_cast<size_t>(
            viewIndex) >=
            deckViewCount
    ) {
        return;
    }

    const String id =
        deckView[
            static_cast<size_t>(
                viewIndex)].
            id;

    for (
        size_t i = 0;
        i < selectedDeckCount;
        ++i
    ) {
        if (
            selectedDeckIds[i] ==
            id
        ) {
            for (
                size_t j = i;
                j + 1 <
                    selectedDeckCount;
                ++j
            ) {
                selectedDeckIds[j] =
                    selectedDeckIds[
                        j + 1];
            }

            --selectedDeckCount;

            selectedDeckIds[
                selectedDeckCount] =
                "";

            return;
        }
    }

    if (
        selectedDeckCount <
        MAX_VISIBLE_DECKS
    ) {
        selectedDeckIds[
            selectedDeckCount++] =
            id;
    }
}

void applyDeckFilter() {
    if (!engine) {
        return;
    }

    if (
        selectedDeckCount == 0
    ) {
        engine->clearCardFilter();
        return;
    }

    bool allowed[
        Config::MAX_DEVICE_CARDS] =
        {false};

    for (
        size_t i = 0;
        i < cardCount;
        ++i
    ) {
        allowed[i] =
            isDeckSelected(
                cards[i].deckId);
    }

    engine->setCardFilter(
        allowed,
        cardCount);
}

void renderHome() {
    screen =
        AppScreen::Home;

    WeeklyPlanDay days[7];
    buildWeeklyPlan(days);

    display.showHome(
        days,
        7,
        clockService.trusted(),
        engine != nullptr &&
            engine->
                hasResumableSession());
}

void renderMenu() {
    screen =
        AppScreen::Menu;

    display.showMainMenu();
}

void renderSettings() {
    screen =
        AppScreen::Settings;

    display.showSettings(
        backlightService.label());
}


void renderDecks() {
    screen =
        AppScreen::Decks;

    buildDeckView();

    display.showDecks(
        deckView,
        deckViewCount,
        selectedDeckCount > 0,
        engine != nullptr &&
            engine->
                hasResumableSession());
}

void renderAgenda() {
    screen =
        AppScreen::Agenda;

    const ScheduleOverview overview =
        scheduleService.snapshot();

    String nextReview =
        overview.dueNow > 0
            ? "agora"
            : scheduleService.
                  humanize(
                      overview.
                          nextReviewAt);

    if (
        !clockService.trusted() &&
        overview.nextReviewAt != 0
    ) {
        nextReview +=
            " (aprox.)";
    }

    display.showAgenda(
        overview.dueNow,
        overview.laterToday,
        overview.tomorrow,
        overview.next7Days,
        nextReview);
}

void renderSync() {
    screen =
        AppScreen::Sync;

    display.showSyncMenu(
        cardCount,
        storage.
            pendingReviewCount(),
        networkService.
            connected());
}

void renderConnection() {
    screen =
        AppScreen::Connection;

    display.showConnectionMenu(
        networkService.enabled(),
        networkService.connected(),
        networkService.ssid(),
        networkService.
            profileCount());
}


void renderWifiNetworks() {
    screen = AppScreen::WifiNetworks;

    String ssids[NetworkService::MAX_SCAN_RESULTS];
    int32_t rssis[NetworkService::MAX_SCAN_RESULTS] = {0};
    uint8_t flags[NetworkService::MAX_SCAN_RESULTS] = {0};

    for (size_t i = 0; i < wifiScanCount; ++i) {
        ssids[i] = wifiScan[i].ssid;
        rssis[i] = wifiScan[i].rssi;

        if (wifiScan[i].open) flags[i] |= 0x01;
        if (wifiScan[i].enterprise) flags[i] |= 0x02;
        if (wifiScan[i].known) flags[i] |= 0x04;
    }

    display.showWifiNetworks(
        ssids,
        rssis,
        flags,
        wifiScanCount);
}

String friendlyWifiError();
void renderWifiMessage();

void scanWifiNetworks() {
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
        messageReturnScreen = AppScreen::Connection;

        wifiMessageText =
            friendlyWifiError();

        wifiMessagePrimary =
            "Voltar à conexão";

        renderWifiMessage();
    }
}


void renderWifiPassword() {
    screen = AppScreen::WifiPassword;

    if (
        wifiSelectedIndex < 0 ||
        static_cast<size_t>(wifiSelectedIndex) >= wifiScanCount
    ) {
        renderConnection();
        return;
    }

    display.showWifiPassword(
        wifiScan[wifiSelectedIndex].ssid,
        wifiPassword.length(),
        wifiKeyboardPage,
        wifiHint);
}

void renderWifiMessage() {
    screen = AppScreen::WifiMessage;
    display.showWifiMessage(
        wifiMessageTitle,
        wifiMessageText,
        wifiMessagePrimary);
}

void showInfoMessage(
    const String& title,
    const String& text,
    const String& primary,
    AppScreen returnTo) {

    wifiMessageTitle = title;
    wifiMessageText = text;
    wifiMessagePrimary = primary;
    messageReturnScreen = returnTo;
    renderWifiMessage();
}

// Biblioteca/estado FSRS mudou numa sincronização com o backend.
bool applyBackendLibraryUpdate() {
    if (!backendSync.consumeLibraryUpdated()) {
        return false;
    }

    canonicalizeActiveLibraryIfPossible();
    rebuildEngine();

    // O texto de um cartão pode mudar mantendo o id: descarta o cache de
    // conteúdo hidratado do microSD.
    displayCardBuffer = CardDefinition{};

    Serial.printf(
        "[app] biblioteca sincronizada com a conta: %u cartoes\n",
        static_cast<unsigned>(cardCount));

    return true;
}

bool waitForWifi(uint32_t timeoutMs) {
    if (networkService.connected()) {
        return true;
    }

    // Reinicia o backoff de reconexão: quem pediu a sincronização está
    // esperando agora, não daqui a alguns minutos.
    networkService.resumeAfterSleep();

    const uint32_t started = millis();

    while (
        !networkService.connected() &&
        millis() - started < timeoutMs
    ) {
        networkService.loop();
        delay(40);
    }

    return networkService.connected();
}

void runManualBackendSync() {
    if (!backendSync.paired()) {
        BackendSyncReport report;
        report.outcome = SyncOutcome::NotPaired;
        showInfoMessage(
            BackendSyncService::outcomeTitle(report),
            BackendSyncService::outcomeMessage(report),
            "Voltar à sincronização",
            AppScreen::Sync);
        return;
    }

    noteNetworkDemand();

    if (!networkService.connected()) {
        if (!networkService.hasCredentials()) {
            showInfoMessage(
                "Sem rede Wi-Fi",
                "O terminal ainda não conhece nenhuma rede. Use Menu > Conexão > Procurar redes "
                "ou Configurar pelo celular.",
                "Voltar à sincronização",
                AppScreen::Sync);
            return;
        }

        if (!networkService.enabled()) {
            networkService.enable();
        }

        display.showWifiMessage(
            "Conectando",
            "Conectando ao Wi-Fi para sincronizar com a conta...",
            "");

        if (!waitForWifi(PlatformSync::SYNC_WAIT_FOR_WIFI_MS)) {
            BackendSyncReport report;
            report.outcome = SyncOutcome::Offline;
            showInfoMessage(
                BackendSyncService::outcomeTitle(report),
                BackendSyncService::outcomeMessage(report),
                "Voltar à sincronização",
                AppScreen::Sync);
            return;
        }
    }

    display.showWifiMessage(
        "Sincronizando",
        "Enviando revisões e baixando os cartões da conta...",
        "");

    backendSync.clearAuthRejected();
    backendSync.syncNow(SyncTrigger::Manual);
    applyBackendLibraryUpdate();

    const BackendSyncReport& report =
        backendSync.lastReport();

    showInfoMessage(
        BackendSyncService::outcomeTitle(report),
        BackendSyncService::outcomeMessage(report),
        "Voltar à sincronização",
        AppScreen::Sync);
}

String friendlyWifiError() {
    const String error = networkService.lastError();

    if (error == "connection_failed") {
        return "Não foi possível autenticar ou obter conexão. Verifique a senha e a intensidade do sinal.";
    }
    if (error == "network_profile_capacity") {
        return "O limite de redes salvas foi atingido.";
    }
    if (error == "invalid_network_profile") {
        return "A senha precisa ter entre 8 e 63 caracteres para uma rede protegida.";
    }
    if (error == "no_networks_found") {
        return "Nenhuma rede visível foi encontrada.";
    }

    return "Falha de conexão: " + error;
}

void showWifiConnecting(const String& ssid) {
    screen = AppScreen::WifiMessage;
    display.showWifiMessage(
        "Conectando",
        "Tentando conectar a " + ssid + ". Aguarde...",
        "");
}

void selectWifiNetwork(
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
        messageReturnScreen = AppScreen::Connection;

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
                messageReturnScreen = AppScreen::Connection;
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
            messageReturnScreen = AppScreen::Connection;
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
}



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
        messageReturnScreen = AppScreen::Connection;

        wifiMessageText =
            friendlyWifiError();

        wifiMessagePrimary =
            "Voltar à conexão";

        renderWifiMessage();
    }
}


void refreshSdView(bool remount) {
    if (remount || !sdCardService.mounted()) {
        sdCardService.remount();
    }

    sdFileCount = 0;
    for (size_t i = 0; i < SdCardService::MAX_VISIBLE_FILES; ++i) {
        sdPaths[i] = "";
        sdNames[i] = "";
        sdSizes[i] = 0;
    }

    if (sdCardService.mounted()) {
        sdFileCount = sdCardService.listDeckFiles(
            sdPaths,
            sdNames,
            sdSizes,
            SdCardService::MAX_VISIBLE_FILES);
    }
}

void renderStorage() {
    screen = AppScreen::Storage;
    refreshSdView(false);

    display.showStorage(
        sdCardService.mounted(),
        sdCardService.cardSizeBytes(),
        sdCardService.usedBytes(),
        sdNames,
        sdSizes,
        sdFileCount,
        sdStatus);
}


const CardDefinition& cardForDisplay() {
    const CardDefinition& source =
        engine->currentCard();

    if (
        source.question.length() > 0
    ) {
        return source;
    }

    if (
        displayCardBuffer.id ==
            source.id &&
        displayCardBuffer.
            question.length() > 0
    ) {
        return displayCardBuffer;
    }

    const uint32_t started =
        millis();

    const bool hydrated =
        sdCardService.mounted() &&
        sdCardService.
            hydrateCard(
                source.id,
                displayCardBuffer);

    const uint32_t elapsed =
        millis() -
        started;

    Serial.printf(
        "[perf] hydrate id=%s ok=%d %lums\n",
        source.id.c_str(),
        hydrated ? 1 : 0,
        static_cast<unsigned long>(
            elapsed));

    if (hydrated) {
        return
            displayCardBuffer;
    }

    displayCardBuffer =
        source;

    displayCardBuffer.question =
        "Conteudo indisponivel. Insira o microSD da biblioteca.";

    displayCardBuffer.answer =
        "O conteudo completo deste cartao esta armazenado no microSD.";

    return
        displayCardBuffer;
}


void renderQuestion() {
    screen =
        AppScreen::Question;

    display.showQuestion(
        cardForDisplay(),
        engine->currentPosition(),
        engine->sessionCount());
}

void renderSelfAssessment() {
    screen =
        AppScreen::SelfAssessment;

    display.showSelfAssessment(
        cardForDisplay(),
        engine->currentPosition(),
        engine->sessionCount());
}

void renderObjectiveFeedback() {
    screen =
        AppScreen::
            ObjectiveFeedback;

    display.
        showObjectiveFeedback(
            cardForDisplay(),
            engine->
                currentPosition(),
            engine->
                sessionCount(),
            engine->
                selectedOptionIndex(),
            pendingOutcome);
}

void renderEffort() {
    screen =
        AppScreen::Effort;

    display.showEffort(
        engine->currentPosition(),
        engine->sessionCount());
}

void renderSummary() {
    screen =
        AppScreen::Summary;

    const ScheduleOverview overview =
        scheduleService.snapshot();

    String nextReview =
        overview.nextReviewAt == 0
            ? ""
            : scheduleService.
                  humanize(
                      overview.
                          nextReviewAt);

    if (
        !clockService.trusted() &&
        overview.nextReviewAt != 0
    ) {
        nextReview +=
            " (aprox.)";
    }

    display.showSummary(
        engine->stats(),
        overview.dueNow,
        overview.newCards,
        nextReview);
}

void renderAbortConfirm() {
    screen =
        AppScreen::AbortConfirm;

    display.showAbortConfirm(
        engine
            ? engine->
                  remainingCount()
            : 0);
}

void renderCurrentScreen() {
    switch (screen) {
        case AppScreen::Home:
            renderHome();
            break;

        case AppScreen::Menu:
            renderMenu();
            break;

        case AppScreen::Settings:
            renderSettings();
            break;

        case AppScreen::Decks:
            renderDecks();
            break;

        case AppScreen::Agenda:
            renderAgenda();
            break;

        case AppScreen::Sync:
            renderSync();
            break;

        case AppScreen::Connection:
            renderConnection();
            break;

        case AppScreen::WifiNetworks:
            renderWifiNetworks();
            break;

        case AppScreen::WifiPassword:
            renderWifiPassword();
            break;

        case AppScreen::WifiMessage:
            renderWifiMessage();
            break;

        case AppScreen::Storage:
            renderStorage();
            break;

        case AppScreen::LocalLink:
            display.showLocalLink(
                localLink.qrPayload(),
                localLink.ssid(),
                localLink.password(),
                localLinkProvisioning);
            break;

        case AppScreen::Question:
            renderQuestion();
            break;

        case AppScreen::SelfAssessment:
            renderSelfAssessment();
            break;

        case AppScreen::
            ObjectiveFeedback:
            renderObjectiveFeedback();
            break;

        case AppScreen::Effort:
            renderEffort();
            break;

        case AppScreen::Summary:
            renderSummary();
            break;

        case AppScreen::AbortConfirm:
            renderAbortConfirm();
            break;
    }
}


bool startStudyFromCurrentState(
    bool useDeckFilter) {

    const uint32_t started =
        millis();

    if (
        engine == nullptr ||
        cardCount == 0
    ) {
        Serial.printf(
            "[perf] start-study rejected %lums\n",
            static_cast<unsigned long>(
                millis() -
                started));
        return false;
    }

    bool ok = false;

    if (
        engine->
            hasResumableSession()
    ) {
        ok =
            engine->
                resumeSession();
    } else {
        if (useDeckFilter) {
            applyDeckFilter();
        } else {
            engine->
                clearCardFilter();
        }

        ok =
            engine->
                startReviewSession();

        if (!ok) {
            ok =
                engine->
                    startPracticeSession();
        }
    }

    Serial.printf(
        "[perf] start-study ok=%d %lums\n",
        ok ? 1 : 0,
        static_cast<unsigned long>(
            millis() -
            started));

    return ok;
}


void advanceAfterCommit(
    bool finished) {

    pendingOutcome =
        Outcome::Unknown;

    if (finished) {
        renderSummary();

        // As revisões sobem assim que a pessoa sai do resumo e o Wi-Fi
        // estiver de pé: app e web veem a sessão em segundos.
        if (
            backendSync.paired() &&
            storage.pendingReviewCount() > 0
        ) {
            backendSync.requestSync(
                SyncTrigger::SessionEnd,
                PlatformSync::AUTO_SYNC_AFTER_SESSION_DELAY_MS);
        }
    } else {
        renderQuestion();
    }
}

void startLocalLink(LocalLinkMode mode) {
    Serial.printf(
        "[app] LocalLink start requested mode=%s heap=%u\n",
        mode == LocalLinkMode::Provisioning ? "provision" : "sync",
        static_cast<unsigned>(ESP.getFreeHeap()));

    if (!localLink.start(mode)) {
        Serial.println("[app] LocalLink start failed");
        return;
    }

    localLinkProvisioning = mode == LocalLinkMode::Provisioning;
    screen = AppScreen::LocalLink;

    Serial.printf(
        "[app] LocalLink render begin heap=%u\n",
        static_cast<unsigned>(ESP.getFreeHeap()));

    display.showLocalLink(
        localLink.qrPayload(),
        localLink.ssid(),
        localLink.password(),
        localLinkProvisioning);

    Serial.printf(
        "[app] LocalLink render end heap=%u\n",
        static_cast<unsigned>(ESP.getFreeHeap()));
}


void addZone(
    TouchZone* zones,
    size_t& count,
    const char* name,
    int16_t x,
    int16_t y,
    int16_t w,
    int16_t h,
    UiAction action,
    int8_t argument) {

    // Nas telas com abas os botões "Voltar" não são desenhados; a volta é
    // pelo topo ("top_back") ou pelas abas.
    if (
        tabbedScreen() &&
        action == UiAction::Back &&
        std::strcmp(name, "top_back") != 0
    ) {
        return;
    }

    TouchZone& zone =
        zones[count++];

    zone.name = name;
    zone.x = x;
    zone.y = y;
    zone.w = w;
    zone.h = h;
    zone.action = action;
    zone.argument = argument;
}


bool pointInside(
    int16_t x,
    int16_t y,
    const TouchZone& zone) {

    return
        x >= zone.x &&
        y >= zone.y &&
        x <
            zone.x +
            zone.w &&
        y <
            zone.y +
            zone.h;
}

size_t buildTouchZones(
    TouchZone* zones,
    size_t capacity) {

    if (
        !zones ||
        capacity < 12
    ) {
        return 0;
    }

    size_t count = 0;

    const bool portrait =
        display.portrait();

    const int16_t width =
        static_cast<int16_t>(
            display.logicalWidth());

    const HmiLayout::Rect actionZone =
        HmiLayout::actionZone(
            portrait,
            tabbedScreen());

    const int16_t actionTop =
        actionZone.y;

    if (tabbedScreen()) {
        addTabZones(zones, count);
    }

        if (!tabbedScreen() && homeAvailable()) {

addZone(
            zones,
            count,
            "system_home",
            0,
            0,
            88,
            88,
            UiAction::Home);
    }

    if (!tabbedScreen() && menuAvailable()) {

addZone(
            zones,
            count,
            "system_menu",
            homeAvailable()
                ? 88
                : 0,
            0,
            88,
            88,
            UiAction::OpenMenu);
    }


    if (!tabbedScreen() && menuAvailable()) {
        addZone(
            zones,
            count,
            "system_sync",
            homeAvailable()
                ? 132
                : 100,
            0,
            72,
            portrait
                ? 88
                : 72,
            UiAction::OpenSync);
    }

    if (orientationAvailable()) {
        addZone(
            zones,
            count,
            "system_rotate",
            portrait
                ? 393
                : 813,
            portrait
                ? 16
                : 8,
            56,
            56,
            UiAction::
                RotateOrientation);
    }

    if (activeStudyScreen()) {

addZone(
            zones,
            count,
            "system_abort",
            452,
            0,
            88,
            88,
            UiAction::AbortSession);
    }

    switch (screen) {
        case AppScreen::Home: {
            // O botão ao lado de "Hoje" e o bloco "Vencendo agora".
            const HmiLayout::Rect pill = HmiLayout::HOME_STUDY_PILL;
            addZone(zones, count, "home_primary",
                    pill.x - 8, pill.y - 8, pill.w + 16, pill.h + 16,
                    UiAction::PrimaryStudy);
            const HmiLayout::Rect panel = HmiLayout::HOME_PANEL;
            addZone(zones, count, "home_panel",
                    panel.x, panel.y, panel.w, panel.h,
                    UiAction::PrimaryStudy);
            break;
        }

        case AppScreen::Menu: {
            const UiAction actions[4] = {
                UiAction::OpenDecks,
                UiAction::OpenConnection,
                UiAction::OpenSettings,
                UiAction::PowerOff
            };

            const char* names[4] = {
                "menu_decks",
                "menu_connection",
                "menu_settings",
                "menu_power_off"
            };

            for (
                uint8_t i = 0;
                i < 4;
                ++i
            ) {
                const HmiLayout::Rect card =
                    HmiLayout::menuCard(
                        portrait,
                        i);

                addZone(
                    zones,
                    count,
                    names[i],
                    card.x,
                    card.y,
                    card.w,
                    card.h,
                    actions[i]);
            }

            addZone(
                zones,
                count,
                "menu_back",
                actionZone.x,
                actionZone.y,
                actionZone.w,
                actionZone.h,
                UiAction::Back);

            break;
        }

        case AppScreen::Settings: {
            const UiAction actions[3] = {
                UiAction::CycleBacklight,
                UiAction::DeepCleanDisplay,
                UiAction::OpenStorage
            };

            const char* names[3] = {
                "settings_backlight",
                "settings_deep_clean",
                "settings_storage"
            };

            for (uint8_t i = 0; i < 3; ++i) {
                const HmiLayout::Rect card =
                    HmiLayout::connectionCard(
                        portrait, i);

                addZone(
                    zones, count, names[i],
                    card.x, card.y,
                    card.w, card.h,
                    actions[i]);
            }

            addZone(
                zones, count,
                "settings_back",
                actionZone.x, actionZone.y,
                actionZone.w, actionZone.h,
                UiAction::Back);
            break;
        }

        case AppScreen::Decks: {
            const HmiLayout::Rect allCard =
                HmiLayout::deckAllCard(
                    portrait);

            addZone(
                zones,
                count,
                "decks_all",
                allCard.x,
                allCard.y,
                allCard.w,
                allCard.h,
                UiAction::
                    ClearDeckFilter);

            for (
                size_t i = 0;
                i < deckViewCount &&
                i < MAX_VISIBLE_DECKS;
                ++i
            ) {
                const HmiLayout::Rect card =
                    HmiLayout::deckCard(
                        portrait,
                        static_cast<uint8_t>(
                            i));

                addZone(
                    zones,
                    count,
                    "deck_filter",
                    card.x,
                    card.y,
                    card.w,
                    card.h,
                    UiAction::
                        ToggleDeckFilter,
                    static_cast<int8_t>(
                        i));
            }

            addZone(
                zones,
                count,
                "decks_primary",
                actionZone.x,
                actionZone.y,
                actionZone.w,
                actionZone.h,
                UiAction::
                    PrimaryStudy);

            break;
        }

        case AppScreen::Agenda:
            addZone(
                zones,
                count,
                "agenda_back",
                HmiLayout::MARGIN,
                actionTop,
                width - 2 * HmiLayout::MARGIN,
                portrait
                    ? 136
                    : 72,
                UiAction::Back);
            break;

        case AppScreen::Sync:
            if (portrait) {
                addZone(
                    zones,
                    count,
                    "sync_account",
                    HmiLayout::MARGIN,
                    290,
                    width - 2 * HmiLayout::MARGIN,
                    112,
                    UiAction::
                        SyncBackend);

                addZone(
                    zones,
                    count,
                    "sync_phone",
                    HmiLayout::MARGIN,
                    430,
                    width - 2 * HmiLayout::MARGIN,
                    112,
                    UiAction::
                        SyncPhone);
            } else {
                addZone(
                    zones,
                    count,
                    "sync_account",
                    HmiLayout::MARGIN,
                    220,
                    408,
                    130,
                    UiAction::
                        SyncBackend);

                addZone(
                    zones,
                    count,
                    "sync_phone",
                    504,
                    220,
                    408,
                    130,
                    UiAction::
                        SyncPhone);
            }

            addZone(
                zones,
                count,
                "sync_back",
                HmiLayout::MARGIN,
                actionTop,
                width - 2 * HmiLayout::MARGIN,
                portrait
                    ? 136
                    : 72,
                UiAction::Back);
            break;

        case AppScreen::Connection: {
            const UiAction actions[3] = {
                UiAction::ScanWifi,
                UiAction::ToggleWifi,
                UiAction::ConfigureNetwork
            };

            const char* names[3] = {
                "connection_scan",
                "connection_wifi",
                "connection_phone"
            };

            for (
                uint8_t i = 0;
                i < 3;
                ++i
            ) {
                const HmiLayout::Rect card =
                    HmiLayout::connectionCard(
                        portrait,
                        i);

                addZone(
                    zones,
                    count,
                    names[i],
                    card.x,
                    card.y,
                    card.w,
                    card.h,
                    actions[i]);
            }

            addZone(
                zones,
                count,
                "connection_back",
                actionZone.x,
                actionZone.y,
                actionZone.w,
                actionZone.h,
                UiAction::Back);

            break;
        }

        case AppScreen::WifiNetworks: {
            const size_t visible = std::min<size_t>(wifiScanCount, 6);
            if (portrait) {
                for (size_t i = 0; i < visible; ++i) {
                    addZone(zones, count, "wifi_network", HmiLayout::MARGIN, HmiLayout::wifiNetworkRowY(static_cast<uint8_t>(i)), width - 2 * HmiLayout::MARGIN, 86, UiAction::SelectWifiNetwork, static_cast<int8_t>(i));
                }
            } else {
                for (size_t i = 0; i < visible; ++i) {
                    addZone(zones, count, "wifi_network", HmiLayout::MARGIN + (i % 2) * 456, 112 + (i / 2) * 110, 408, 96, UiAction::SelectWifiNetwork, static_cast<int8_t>(i));
                }
            }
            addZone(zones, count, "wifi_rescan", HmiLayout::MARGIN, actionTop, width - 2 * HmiLayout::MARGIN, portrait ? 136 : 72, UiAction::ScanWifi);
            break;
        }

        case AppScreen::WifiPassword: {
            const size_t keyCount = wifiKeyboardCharCount(wifiKeyboardPage);
            const int16_t cols = portrait ? 6 : 9;
            const int16_t gap = portrait ? 6 : 8;
            const int16_t totalW = width - 2 * HmiLayout::MARGIN;
            const int16_t keyW = (totalW - (cols - 1) * gap) / cols;
            const int16_t keyH = portrait ? 58 : 46;
            const int16_t startY = portrait ? 300 : 212;
            const int16_t rows = static_cast<int16_t>((keyCount + cols - 1) / cols);

            for (size_t i = 0; i < keyCount; ++i) {
                const char key = wifiKeyboardCharAt(wifiKeyboardPage, i);
                addZone(
                    zones, count, "wifi_key",
                    HmiLayout::MARGIN + static_cast<int16_t>(i % cols) * (keyW + gap),
                    startY + static_cast<int16_t>(i / cols) * (keyH + gap),
                    keyW, keyH,
                    UiAction::WifiKey,
                    static_cast<int8_t>(key));
            }

            const int16_t controlY = startY + rows * (keyH + gap) + 8;
            const int16_t controlH = portrait ? 66 : 46;
            const int16_t controlGap = 8;
            const int16_t usable = totalW - 3 * controlGap;
            const int16_t w1 = usable * 18 / 100;
            const int16_t w2 = usable * 18 / 100;
            const int16_t w3 = usable * 34 / 100;
            const int16_t w4 = usable - w1 - w2 - w3;
            addZone(zones, count, "wifi_shift", HmiLayout::MARGIN, controlY, w1, controlH, UiAction::WifiShift);
            addZone(zones, count, "wifi_symbols", HmiLayout::MARGIN + w1 + controlGap, controlY, w2, controlH, UiAction::WifiSymbols);
            addZone(zones, count, "wifi_space", HmiLayout::MARGIN + w1 + w2 + 2 * controlGap, controlY, w3, controlH, UiAction::WifiSpace);
            addZone(zones, count, "wifi_backspace", HmiLayout::MARGIN + w1 + w2 + w3 + 3 * controlGap, controlY, w4, controlH, UiAction::WifiBackspace);

            const int16_t buttonW = (width - 2 * HmiLayout::MARGIN - 24) / 2;
            addZone(zones, count, "wifi_cancel", HmiLayout::MARGIN, actionTop, buttonW, portrait ? 136 : 72, UiAction::WifiCancel);
            addZone(zones, count, "wifi_connect", HmiLayout::MARGIN + buttonW + 24, actionTop, buttonW, portrait ? 136 : 72, UiAction::WifiConnect);
            break;
        }

        case AppScreen::WifiMessage:
            addZone(zones, count, "wifi_message_back", HmiLayout::MARGIN, actionTop, width - 2 * HmiLayout::MARGIN, portrait ? 136 : 72, UiAction::WifiCancel);
            break;

        case AppScreen::Storage: {
            if (sdCardService.mounted()) {
                const size_t visible =
                    std::min<size_t>(
                        sdFileCount,
                        portrait
                            ? 5
                            : 6);

                for (
                    size_t i = 0;
                    i < visible;
                    ++i
                ) {
                    const HmiLayout::Rect card =
                        HmiLayout::storageFileCard(
                            portrait,
                            static_cast<uint8_t>(
                                i));

                    addZone(
                        zones,
                        count,
                        "sd_file",
                        card.x,
                        card.y,
                        card.w,
                        card.h,
                        UiAction::
                            ImportSdFile,
                        static_cast<int8_t>(
                            i));
                }

                const int16_t buttonW =
                    (
                        actionZone.w -
                        24
                    ) /
                    2;

                addZone(
                    zones,
                    count,
                    "sd_refresh",
                    actionZone.x,
                    actionZone.y,
                    buttonW,
                    actionZone.h,
                    UiAction::RefreshSd);

                addZone(
                    zones,
                    count,
                    "sd_export",
                    actionZone.x +
                        buttonW +
                        24,
                    actionZone.y,
                    buttonW,
                    actionZone.h,
                    UiAction::
                        ExportLibraryToSd);
            } else {
                addZone(
                    zones,
                    count,
                    "sd_mount",
                    actionZone.x,
                    actionZone.y,
                    actionZone.w,
                    actionZone.h,
                    UiAction::RefreshSd);
            }

            break;
        }

        case AppScreen::LocalLink:
            addZone(
                zones,
                count,
                "local_cancel",
                HmiLayout::MARGIN,
                actionTop,
                width - 2 * HmiLayout::MARGIN,
                portrait
                    ? 136
                    : 72,
                UiAction::
                    CancelLocalLink);
            break;

        case AppScreen::Question:
            if (!engine) {
                break;
            }

            addZone(
                zones,
                count,
                "question_reveal",
                HmiLayout::MARGIN,
                actionTop,
                width - 2 * HmiLayout::MARGIN,
                portrait
                    ? 136
                    : 72,
                UiAction::AnswerReady);

            break;

        case AppScreen::SelfAssessment: {
            const int16_t gap =
                24;

            const int16_t totalW =
                width - 2 * HmiLayout::MARGIN;

            const int16_t buttonW =
                (
                    totalW -
                    gap
                ) /
                2;

            addZone(
                zones,
                count,
                "self_incorrect",
                HmiLayout::MARGIN,
                actionTop,
                buttonW,
                portrait
                    ? 136
                    : 72,
                UiAction::
                    SelfIncorrect);

            addZone(
                zones,
                count,
                "self_correct",
                HmiLayout::MARGIN +
                    buttonW +
                    gap,
                actionTop,
                buttonW,
                portrait
                    ? 136
                    : 72,
                UiAction::
                    SelfCorrect);
            break;
        }

        case AppScreen::
            ObjectiveFeedback:
            addZone(
                zones,
                count,
                "feedback_continue",
                HmiLayout::MARGIN,
                actionTop,
                width - 2 * HmiLayout::MARGIN,
                portrait
                    ? 136
                    : 72,
                UiAction::
                    Continue);
            break;

        case AppScreen::Effort: {
            const int16_t gap =
                portrait
                    ? 12
                    : 16;

            const int16_t totalW =
                width - 2 * HmiLayout::MARGIN;

            const int16_t buttonW =
                (
                    totalW -
                    2 * gap
                ) /
                3;

            const UiAction actions[3] = {
                UiAction::
                    EffortDifficult,
                UiAction::
                    EffortNormal,
                UiAction::
                    EffortEasy
            };

            const char* names[3] = {
                "effort_difficult",
                "effort_normal",
                "effort_easy"
            };

            for (
                uint8_t i = 0;
                i < 3;
                ++i
            ) {
                addZone(
                    zones,
                    count,
                    names[i],
                    HmiLayout::MARGIN +
                        i *
                            (
                                buttonW +
                                gap
                            ),
                    actionTop,
                    buttonW,
                    portrait
                        ? 136
                        : 72,
                    actions[i]);
            }
            break;
        }

        case AppScreen::Summary:
            addZone(
                zones,
                count,
                "summary_continue",
                HmiLayout::MARGIN,
                actionTop,
                width - 2 * HmiLayout::MARGIN,
                portrait
                    ? 136
                    : 72,
                UiAction::Continue);
            break;

        case AppScreen::AbortConfirm: {
            const int16_t gap =
                24;

            const int16_t totalW =
                width - 2 * HmiLayout::MARGIN;

            const int16_t buttonW =
                (
                    totalW -
                    gap
                ) /
                2;

            addZone(
                zones,
                count,
                "abort_cancel",
                HmiLayout::MARGIN,
                actionTop,
                buttonW,
                portrait
                    ? 136
                    : 72,
                UiAction::
                    CancelAbort);

            addZone(
                zones,
                count,
                "abort_confirm",
                HmiLayout::MARGIN +
                    buttonW +
                    gap,
                actionTop,
                buttonW,
                portrait
                    ? 136
                    : 72,
                UiAction::
                    ConfirmAbort);
            break;
        }
    }

    return count;
}

RoutedTouch routeTouch(
    const MnemosTouchPoint& point) {

    TouchZone zones[64];

    const size_t count = buildTouchZones(zones, 64);

    for (size_t i = 0; i < count; ++i) {
        if (pointInside(point.x, point.y, zones[i])) {
            RoutedTouch routed;
            routed.action = zones[i].action;
            routed.argument = zones[i].argument;
            routed.zone = zones[i].name;
            routed.x = zones[i].x;
            routed.y = zones[i].y;
            routed.w = zones[i].w;
            routed.h = zones[i].h;
            return routed;
        }
    }

    RoutedTouch none;
    return none;
}




void toggleOrientation() {
    display.setOrientation(
        DisplayOrientation::Portrait);

    touchInput.setPortrait(
        true);
}


void returnFromAbortConfirmation() {
    screen =
        abortReturnScreen;

    renderCurrentScreen();
}

void processAction(
    UiAction action,
    int8_t argument = -1) {

    if (
        action ==
        UiAction::None
    ) {
        return;
    }

    if (
        action ==
        UiAction::
            RotateOrientation
    ) {
        toggleOrientation();
        return;
    }

    if (
        action ==
        UiAction::Home &&
        homeAvailable()
    ) {
        if (activeStudyScreen()) {
            Serial.println(
                "[study] sessao pausada pela Home; "
                "fila e cartao atual preservados para retomar");
        }

        pendingOutcome = Outcome::Unknown;
        renderHome();
        return;
    }

    if (
        action ==
        UiAction::AbortSession &&
        activeStudyScreen()
    ) {
        abortReturnScreen =
            screen;

        renderAbortConfirm();
        return;
    }

    if (
        action ==
        UiAction::CancelAbort &&
        screen ==
            AppScreen::
                AbortConfirm
    ) {
        returnFromAbortConfirmation();
        return;
    }

    if (
        action ==
        UiAction::ConfirmAbort &&
        screen ==
            AppScreen::
                AbortConfirm
    ) {
        if (engine) {
            engine->
                abortSession();

            engine->
                clearCardFilter();
        }

        clearDeckSelection();

        pendingOutcome =
            Outcome::Unknown;

        Serial.println(
            "[study] sessao interrompida; "
            "revisoes ja confirmadas preservadas; "
            "fila restante descartada");

        renderHome();
        return;
    }

    if (
        action ==
        UiAction::OpenMenu &&
        menuAvailable()
    ) {
        renderMenu();
        return;
    }


    if (
        action ==
        UiAction::OpenSync &&
        menuAvailable()
    ) {
        renderSync();
        return;
    }

    // A aba "Baralhos" abre a lista de qualquer tela com abas, não só do Menu.
    if (
        action == UiAction::OpenDecks &&
        tabbedScreen() &&
        screen != AppScreen::Decks
    ) {
        renderDecks();
        return;
    }

    // A aba central "Estudar" faz o mesmo que o botão do Hoje.
    if (
        action == UiAction::PrimaryStudy &&
        tabbedScreen() &&
        screen != AppScreen::Home &&
        screen != AppScreen::Decks
    ) {
        screen = AppScreen::Home;
    }

    switch (action) {
        case UiAction::OpenSync:
        case UiAction::OpenConnection:
        case UiAction::SyncBackend:
        case UiAction::SyncPhone:
        case UiAction::ConfigureNetwork:
        case UiAction::ToggleWifi:
        case UiAction::ScanWifi:
        case UiAction::SelectWifiNetwork:
        case UiAction::WifiConnect:
            noteNetworkDemand();
            break;
        default:
            break;
    }

    switch (screen) {
        case AppScreen::Home:
            if (
                action ==
                UiAction::
                    PrimaryStudy
            ) {
                clearDeckSelection();

                if (cardCount == 0) {
                    showInfoMessage(
                        "Nenhum cartão",
                        backendSync.paired()
                            ? "Escolha os baralhos deste terminal em Dispositivo, no app ou na web, "
                              "e toque em Sincronizar com a conta."
                            : "Pareie o terminal com o app (Menu > Conexão > Configurar pelo celular) "
                              "ou importe um baralho do microSD em Configurações.",
                        "Ir para sincronização",
                        AppScreen::Sync);
                } else if (
                    startStudyFromCurrentState(
                        false)
                ) {
                    renderQuestion();
                }
            }
            break;

        case AppScreen::Menu:
            if (
                action ==
                UiAction::OpenDecks
            ) {
                renderDecks();
            } else if (
                action ==
                UiAction::OpenConnection
            ) {
                renderConnection();
            } else if (
                action ==
                UiAction::OpenSettings
            ) {
                renderSettings();
            } else if (
                action ==
                UiAction::PowerOff
            ) {
                powerOffRequested = true;
            } else if (
                action ==
                UiAction::Back
            ) {
                renderHome();
            }
            break;

        case AppScreen::Settings:
            if (action == UiAction::CycleBacklight) {
                backlightService.cycle();
                renderSettings();
            } else if (action == UiAction::DeepCleanDisplay) {
                display.deepClean();
                renderSettings();
            } else if (action == UiAction::OpenStorage) {
                sdStatus = "";
                renderStorage();
            } else if (action == UiAction::PowerOff) {
                powerOffRequested = true;
            } else if (action == UiAction::Back) {
                renderMenu();
            }
            break;

        case AppScreen::Decks:
            if (
                action ==
                UiAction::
                    ToggleDeckFilter
            ) {
                toggleDeckSelection(
                    argument);

                renderDecks();
            } else if (
                action ==
                UiAction::
                    ClearDeckFilter
            ) {
                clearDeckSelection();
                renderDecks();
            } else if (
                action ==
                UiAction::
                    PrimaryStudy
            ) {
                if (
                    startStudyFromCurrentState(
                        true)
                ) {
                    renderQuestion();
                }
            }
            break;

        case AppScreen::Agenda:
            if (
                action ==
                UiAction::Back
            ) {
                renderMenu();
            }
            break;

        case AppScreen::Sync:
            if (
                action ==
                UiAction::
                    SyncBackend
            ) {
                runManualBackendSync();
            } else if (
                action ==
                UiAction::SyncPhone
            ) {
                // O app atual sincroniza com o terminal pela conta (Wi-Fi):
                // "com o celular" significa parear/reparear com o app. O QR
                // de pareamento é o que o app sabe ler.
                startLocalLink(
                    LocalLinkMode::
                        Provisioning);
            } else if (
                action ==
                UiAction::Back
            ) {
                renderMenu();
            }
            break;

        case AppScreen::Connection:
            if (action == UiAction::ScanWifi) {
                scanWifiNetworks();
            } else if (action == UiAction::ConfigureNetwork) {
                startLocalLink(LocalLinkMode::Provisioning);
            } else if (action == UiAction::ToggleWifi) {
                if (networkService.enabled()) networkService.disable();
                else networkService.enable();
                renderConnection();
            } else if (action == UiAction::Back) {
                renderMenu();
            }
            break;

        case AppScreen::WifiNetworks:
            if (action == UiAction::SelectWifiNetwork) {
                selectWifiNetwork(argument);
            } else if (action == UiAction::ScanWifi) {
                scanWifiNetworks();
            }
            break;

        case AppScreen::WifiPassword:
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
                }

                renderWifiPassword();
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
                }

                renderWifiPassword();
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

            break;

        case AppScreen::WifiMessage:
            if (action == UiAction::WifiCancel) {
                const AppScreen target = messageReturnScreen;
                messageReturnScreen = AppScreen::Connection;

                if (target == AppScreen::Sync) {
                    renderSync();
                } else if (target == AppScreen::Home) {
                    renderHome();
                } else if (target == AppScreen::Menu) {
                    renderMenu();
                } else {
                    renderConnection();
                }
            }
            break;

        case AppScreen::Storage:
            if (action == UiAction::RefreshSd) {
                sdStatus = "";
                refreshSdView(true);
                renderStorage();
            } else if (action == UiAction::ImportSdFile) {
                if (argument >= 0 && static_cast<size_t>(argument) < sdFileCount) {
                    const SdImportResult result =
                        sdCardService.
                            importDeckFileToCanonical(
                                sdPaths[argument],
                                Config::
                                    MAX_DEVICE_CARDS);

                    if (result.ok) {
                        size_t loaded = 0;

                        if (
                            sdCardService.
                                loadCatalog(
                                    cards,
                                    states,
                                    Config::
                                        MAX_DEVICE_CARDS,
                                    loaded)
                        ) {
                            cardCount =
                                loaded;

                            // Biblioteca agora mistura conteúdo local: deixa
                            // de ser espelho da conta (não reporta baralhos
                            // locais ao backend). Um snapshot com baralhos
                            // escolhidos na conta volta a substituí-la.
                            storage.setLibraryFromBackend(false);

                            rebuildEngine();

                            sdStatus =
                                "SD-first: +" +
                                String(
                                    result.added) +
                                ", atualizados " +
                                String(
                                    result.updated) +
                                ", ignorados " +
                                String(
                                    result.skipped);
                        } else {
                            sdStatus =
                                "Importado, mas catalogo nao pode ser recarregado";
                        }
                    } else {
                        sdStatus =
                            result.error;
                    }

                    renderStorage();
                }
            } else if (action == UiAction::ExportLibraryToSd) {
                String exported;
                if (sdCardService.exportLibrary(cards, cardCount, exported)) {
                    sdStatus = "Biblioteca exportada para " + exported;
                } else {
                    sdStatus = "Falha ao exportar: " + sdCardService.lastError();
                }
                renderStorage();
            } else if (action == UiAction::Back) {
                // "‹ Voltar" do topo: o Armazenamento abre a partir de Configurações.
                renderSettings();
            }
            break;

        case AppScreen::LocalLink:
            if (
                action ==
                UiAction::
                    CancelLocalLink
            ) {
                localLink.stop();
                finishLocalLinkScreen();
            }
            break;

        case AppScreen::Question:
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

            break;

        case AppScreen::SelfAssessment:
            if (
                action ==
                UiAction::
                    SelfIncorrect
            ) {
                advanceAfterCommit(
                    engine->
                        commitCurrent(
                            Outcome::
                                Incorrect,
                            Effort::None));
            } else if (
                action ==
                UiAction::
                    SelfCorrect
            ) {
                pendingOutcome =
                    Outcome::Correct;

                renderEffort();
            }
            break;

        case AppScreen::
            ObjectiveFeedback:
            if (
                action ==
                UiAction::Continue
            ) {
                if (
                    pendingOutcome ==
                    Outcome::Correct
                ) {
                    renderEffort();
                } else {
                    advanceAfterCommit(
                        engine->
                            commitCurrent(
                                Outcome::
                                    Incorrect,
                                Effort::
                                    None));
                }
            }
            break;

        case AppScreen::Effort: {
            Effort effort =
                Effort::None;

            if (
                action ==
                UiAction::
                    EffortDifficult
            ) {
                effort =
                    Effort::Difficult;
            } else if (
                action ==
                UiAction::
                    EffortNormal
            ) {
                effort =
                    Effort::Normal;
            } else if (
                action ==
                UiAction::
                    EffortEasy
            ) {
                effort =
                    Effort::Easy;
            }

            if (
                effort !=
                Effort::None
            ) {
                advanceAfterCommit(
                    engine->
                        commitCurrent(
                            Outcome::Correct,
                            effort));
            }

            break;
        }

        case AppScreen::Summary:
            if (
                action ==
                UiAction::Continue
            ) {
                clearDeckSelection();

                if (engine) {
                    engine->
                        clearCardFilter();
                }

                renderHome();
            }
            break;

        case AppScreen::AbortConfirm:
            // Tratado antes do switch.
            break;
    }
}

bool powerSleepAllowed() {
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
    networkService.forceRadioOff();
    networkRadioSuspended = true;
    backlightService.suspend();

    const PowerWakeReason wake =
        powerService.enterLightSleep();

    touchInput.begin();

    touchInput.setPortrait(true);

    if (resumeSd) {
        sdCardService.resume();
    }

    backlightService.resume();

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
    networkService.forceRadioOff();
    backlightService.suspend();

    Serial.println(
        "[app] entrando em deep sleep interno por timer");

    delay(20);

    powerService.enterDeepSleep();
}


void performPowerOff(bool automatic) {
    if (!powerService.pmicAvailable()) {
        Serial.println(
            "[power] power-off indisponivel: "
            "BQ25896 ausente");

        powerService.noteActivity();
        return;
    }

    if (powerService.externalPowerPresent()) {
        Serial.println(
            "[power] power-off indisponivel: "
            "desconecte o USB");

        powerService.noteActivity();
        return;
    }

    prepareForSleep();

    display.showPowerOff(
        automatic);

    networkService.forceRadioOff();
    networkRadioSuspended = true;

    /*
     * Coloca o frontlight em zero antes do corte de VSYS.
     * Nao existe Serial.flush() no caminho final de hard-off:
     * o USB pode ja estar fisicamente desconectado.
     */
    backlightService.suspend();

    ledcWrite(
        Config::BACKLIGHT_PWM_CHANNEL,
        0);

    sdCardService.suspend();

    /*
     * A partir daqui nao depender de USB CDC.
     * enterPowerOff() deve terminar com a remocao de VSYS.
     */
    powerService.enterPowerOff();

    /*
     * Hard-off correto nunca retorna.
     * Se retornar, permanece inerte em vez de reiniciar.
     */
    while (true) {
        delay(1000);
    }
}

void canonicalizeActiveLibraryIfPossible() {
    if (
        !Config::SD_FIRST_LIBRARY ||
        !sdCardService.mounted()
    ) {
        return;
    }

    bool hasFullContent = true;

    for (
        size_t i = 0;
        i < cardCount;
        ++i
    ) {
        if (
            cards[i].
                question.length() ==
            0
        ) {
            hasFullContent = false;
            break;
        }
    }

    if (!hasFullContent) {
        return;
    }

    if (
        sdCardService.
            saveCanonicalLibrary(
                cards,
                cardCount)
    ) {
        sdCardService.
            compactCatalog(
                cards,
                cardCount);
    }
}

void finishLocalLinkScreen() {
    rebuildEngine();

    if (!localLink.consumeProvisioned()) {
        renderMenu();
        return;
    }

    // O app gravou rede (e credencial, se o registro no backend deu certo).
    // A primeira sincronização roda assim que o Wi-Fi subir.
    backendSync.clearAuthRejected();
    noteNetworkDemand();

    if (backendSync.paired()) {
        backendSync.requestSync(
            SyncTrigger::Provisioned,
            PlatformSync::AUTO_SYNC_AFTER_CONNECT_DELAY_MS);

        showInfoMessage(
            "Terminal conectado",
            "Rede e conta gravadas. O terminal sincroniza sozinho assim que o Wi-Fi conectar.\n"
            "Escolha os baralhos deste terminal em Dispositivo, no app ou na web.",
            "Ver sincronização",
            AppScreen::Sync);
    } else {
        showInfoMessage(
            "Rede gravada",
            "O app gravou a rede, mas não registrou o terminal na conta (servidor "
            "inacessível ou endereço local como localhost). Pareie de novo com o "
            "app apontando para o IP do servidor.",
            "Voltar ao menu",
            AppScreen::Menu);
    }
}


String maskedToken(const String& token) {
    if (token.length() == 0) return String();
    if (token.length() <= 4) return "****";
    return "..." + token.substring(token.length() - 4);
}

void describeTerminal(JsonDocument& response) {
    response["deviceId"] = TerminalIdentity::deviceId();
    response["identityGeneration"] = TerminalIdentity::generation();
    response["firmware"] = Config::APP_VERSION;
    response["model"] = Config::DEVICE_MODEL;
    response["protocol"] = Config::DEVICE_PROTOCOL_VERSION;
    response["build"] = Config::BUILD_FLAVOR;
    response["cards"] = cardCount;
    response["maxCards"] = Config::MAX_DEVICE_CARDS;
    response["librarySource"] = storage.libraryFromBackend() ? "backend" : "local";
    response["pendingReviews"] = storage.pendingReviewCount();
    response["rejectedReviews"] = storage.rejectedReviewCount();

    JsonObject wifi = response["wifi"].to<JsonObject>();
    wifi["enabled"] = networkService.enabled();
    wifi["connected"] = networkService.connected();
    wifi["ssid"] = networkService.ssid();
    wifi["ip"] = networkService.ip();
    wifi["profiles"] = networkService.profileCount();
    wifi["radioSuspended"] = networkRadioSuspended;
    wifi["lastError"] = networkService.lastError();

    JsonObject backend = response["backend"].to<JsonObject>();
    backend["url"] = networkService.backendUrl();
    backend["paired"] = backendSync.paired();
    backend["token"] = maskedToken(networkService.deviceToken());
    backend["authRejected"] = backendSync.authRejected();
    backend["syncIntervalSeconds"] = networkService.syncIntervalSeconds();

    JsonObject clock = response["clock"].to<JsonObject>();
    clock["epoch"] = clockService.now();
    clock["trusted"] = clockService.trusted();
    clock["ntp"] = clockService.ntpSynchronized();

    const BackendSyncReport& report = backendSync.lastReport();
    JsonObject sync = response["lastSync"].to<JsonObject>();
    sync["outcome"] = BackendSyncService::outcomeName(report.outcome);
    sync["trigger"] = BackendSyncService::triggerName(report.trigger);
    if (report.outcome != SyncOutcome::NeverRan) {
        sync["ageSeconds"] = (millis() - report.finishedAtMs) / 1000U;
        sync["durationMs"] = report.durationMs;
        sync["failedStep"] = report.failedStep;
        sync["httpStatus"] = report.httpStatus;
        sync["detail"] = report.detail;
        sync["pushed"] = report.reviewsPushed;
        sync["quarantined"] = report.reviewsQuarantined;
        sync["remoteReviews"] = report.remoteReviews;
        sync["libraryChanged"] = report.libraryChanged;
        sync["keptLocalLibrary"] = report.keptLocalLibrary;
    }
    sync["pendingRequest"] = backendSync.hasPendingRequest();
}

bool profileFromCommand(
    JsonDocument& command,
    NetworkProfile& profile,
    String& error) {

    profile = NetworkProfile{};
    profile.ssid = command["ssid"] | "";
    profile.ssid.trim();
    const String password = command["password"] | "";
    String security = command["security"] | "";

    if (security.length() == 0) {
        security = password.length() == 0 ? "open" : "personal";
    }

    profile.security = security;
    profile.priority = command["priority"] | 100;
    profile.enabled = true;
    profile.autoConnect = true;

    if (security == "enterprise-password" || security == "enterprise") {
        profile.security = "enterprise-password";
        profile.identity = command["identity"] | "";
        profile.username = command["username"] | "";
        profile.password = password;
    } else if (security == "personal") {
        profile.password = password;
    } else if (security != "open") {
        error = "invalid_security";
        return false;
    }

    // Reaproveita o perfil já gravado para o mesmo SSID (pelo app ou pelo
    // teclado do terminal) em vez de criar um duplicado.
    for (size_t i = 0; i < networkService.profileCount(); ++i) {
        const NetworkProfile* existing = networkService.profileAt(i);
        if (existing != nullptr && existing->ssid == profile.ssid) {
            profile.id = existing->id;
            break;
        }
    }

    if (profile.id.length() == 0) {
        uint32_t hash = 2166136261UL;
        for (size_t i = 0; i < profile.ssid.length(); ++i) {
            hash ^= static_cast<uint8_t>(profile.ssid[i]);
            hash *= 16777619UL;
        }
        profile.id = "serial-" + String(hash, HEX);
    }

    if (profile.ssid.length() == 0) {
        error = "missing_ssid";
        return false;
    }
    return true;
}

void replySyncReport(const char* cmd, bool ok) {
    JsonDocument response;
    response["cmd"] = cmd;
    response["ok"] = ok;
    const BackendSyncReport& report = backendSync.lastReport();
    response["outcome"] = BackendSyncService::outcomeName(report.outcome);
    response["title"] = BackendSyncService::outcomeTitle(report);
    response["message"] = BackendSyncService::outcomeMessage(report);
    response["cards"] = cardCount;
    response["pushed"] = report.reviewsPushed;
    response["pending"] = report.reviewsPending;
    response["quarantined"] = report.reviewsQuarantined;
    response["remoteReviews"] = report.remoteReviews;
    response["libraryChanged"] = report.libraryChanged;
    response["httpStatus"] = report.httpStatus;
    response["failedStep"] = report.failedStep;
    response["detail"] = report.detail;
    response["durationMs"] = report.durationMs;
    SerialConsole::reply(response);
}

void refreshAfterPlatformChange() {
    if (screen == AppScreen::Home) {
        renderHome();
    } else if (screen == AppScreen::Sync) {
        renderSync();
    } else if (screen == AppScreen::Connection) {
        renderConnection();
    }
}

void handleSerialCommand(JsonDocument& command) {
    const String cmd = command["cmd"] | "";
    powerService.noteActivity();

    // Trocar a biblioteca no meio de uma sessão invalidaria a fila em uso.
    const bool studying =
        activeStudyForPowerPolicy() ||
        screen == AppScreen::Summary;

    if (
        (cmd == "sync" || cmd == "provision" || cmd == "wifi" || cmd == "backend") &&
        (studying || localLink.active())
    ) {
        SerialConsole::replyError(
            cmd,
            studying
                ? "busy_studying: volte para a tela inicial do terminal"
                : "busy_pairing: cancele a tela de QR do terminal");
        return;
    }

    if (cmd == "help") {
        JsonDocument response;
        response["cmd"] = cmd;
        response["ok"] = true;
        JsonArray commands = response["commands"].to<JsonArray>();
        commands.add("info");
        commands.add("provision {ssid,password,security?,backendUrl,deviceToken}");
        commands.add("wifi {ssid,password,security?}");
        commands.add("backend {url,token}");
        commands.add("sync");
        commands.add("time {epoch}");
        commands.add("unpair {newIdentity?}");
        commands.add("reboot");
        SerialConsole::reply(response);
        return;
    }

    if (cmd == "info" || cmd == "status") {
        JsonDocument response;
        response["cmd"] = cmd;
        response["ok"] = true;
        describeTerminal(response);
        SerialConsole::reply(response);
        return;
    }

    if (cmd == "time") {
        const uint32_t epoch = command["epoch"] | 0U;
        if (epoch < 1700000000U) {
            SerialConsole::replyError(cmd, "invalid_epoch");
            return;
        }
        clockService.setFromEpoch(epoch);
        JsonDocument response;
        response["cmd"] = cmd;
        response["ok"] = true;
        response["epoch"] = clockService.now();
        SerialConsole::reply(response);
        refreshAfterPlatformChange();
        return;
    }

    if (cmd == "wifi" || cmd == "provision") {
        NetworkProfile profile;
        String error;
        if (!profileFromCommand(command, profile, error)) {
            SerialConsole::replyError(cmd, error);
            return;
        }

        String backendUrl = command["backendUrl"] | "";
        String deviceToken = command["deviceToken"] | "";
        const uint32_t interval =
            command["syncIntervalSeconds"] | networkService.syncIntervalSeconds();

        if (cmd == "wifi") {
            backendUrl = "";
            deviceToken = "";
        }

        const uint32_t epoch = command["epoch"] | 0U;
        if (epoch >= 1700000000U) clockService.setFromEpoch(epoch);

        if (!networkService.storeProfile(profile, backendUrl, deviceToken, interval)) {
            SerialConsole::replyError(cmd, networkService.lastError());
            return;
        }

        networkService.enable();
        backendSync.clearAuthRejected();
        noteNetworkDemand();

        if (backendSync.paired()) {
            backendSync.requestSync(
                SyncTrigger::Provisioned,
                PlatformSync::AUTO_SYNC_AFTER_CONNECT_DELAY_MS);
        }

        JsonDocument response;
        response["cmd"] = cmd;
        response["ok"] = true;
        describeTerminal(response);
        SerialConsole::reply(response);
        refreshAfterPlatformChange();
        return;
    }

    if (cmd == "backend") {
        const String url = command["url"] | "";
        const String token = command["token"] | "";
        if (!networkService.setBackend(url, token)) {
            SerialConsole::replyError(cmd, networkService.lastError());
            return;
        }
        backendSync.clearAuthRejected();
        if (backendSync.paired()) {
            noteNetworkDemand();
            backendSync.requestSync(SyncTrigger::Serial, 0);
        }
        JsonDocument response;
        response["cmd"] = cmd;
        response["ok"] = true;
        describeTerminal(response);
        SerialConsole::reply(response);
        return;
    }

    if (cmd == "sync") {
        if (!backendSync.paired()) {
            SerialConsole::replyError(cmd, "not_paired");
            return;
        }
        noteNetworkDemand();
        if (!networkService.connected()) {
            if (!networkService.enabled()) networkService.enable();
            waitForWifi(PlatformSync::SYNC_WAIT_FOR_WIFI_MS);
        }
        backendSync.clearAuthRejected();
        const bool ok = backendSync.syncNow(SyncTrigger::Serial);
        if (applyBackendLibraryUpdate()) {
            refreshAfterPlatformChange();
        }
        replySyncReport("sync", ok);
        return;
    }

    if (cmd == "unpair") {
        networkService.clearBackend();
        backendSync.cancelPendingRequest();
        const bool newIdentity = command["newIdentity"] | false;
        if (newIdentity) TerminalIdentity::rotate();
        JsonDocument response;
        response["cmd"] = cmd;
        response["ok"] = true;
        response["deviceId"] = TerminalIdentity::deviceId();
        SerialConsole::reply(response);
        return;
    }

    if (cmd == "reboot") {
        JsonDocument response;
        response["cmd"] = cmd;
        response["ok"] = true;
        SerialConsole::reply(response);
        Serial.flush();
        prepareForSleep();
        delay(200);
        ESP.restart();
        return;
    }

    /*
     * Só na bancada: a imagem exata do canvas e um toque sintético, para
     * revisar o desenho das telas pelo computador
     * (tools/hmi_capture.py). Nunca no firmware de produto.
     */
    if (Config::BENCH_BUILD && cmd == "screen") {
        display.dumpCanvas(Serial);
        return;
    }

    if (Config::BENCH_BUILD && cmd == "tap") {
        MnemosTouchPoint point;
        point.x = static_cast<int16_t>(command["x"] | -1);
        point.y = static_cast<int16_t>(command["y"] | -1);
        point.rawX = point.x;
        point.rawY = point.y;

        const RoutedTouch routed = routeTouch(point);
        JsonDocument response;
        response["cmd"] = cmd;
        response["ok"] = routed.action != UiAction::None;
        response["screen"] = appScreenName(screen);
        response["zone"] = routed.zone;
        response["action"] = uiActionName(routed.action);
        SerialConsole::reply(response);

        if (routed.action != UiAction::None) {
            lastAcceptedTouchMs = millis();
            display.showTouchFeedback(
                routed.x, routed.y, routed.w, routed.h);
            processAction(routed.action, routed.argument);
        }
        return;
    }

    SerialConsole::replyError(cmd, "unknown_command");
}


void setup() {
    Serial.begin(
        115200);

    serialConsole.begin();

    Serial.printf(
        "[build] flavor=%s bench=%d demo=%d light-sleep=%d deep-sleep=%d ota-auto=%d\n",
        Config::BUILD_FLAVOR,
        Config::BENCH_BUILD ? 1 : 0,
        Config::DEMO_INTERVALS ? 1 : 0,
        Config::LIGHT_SLEEP_ENABLED ? 1 : 0,
        Config::DEEP_SLEEP_ENABLED ? 1 : 0,
        Config::OTA_AUTO_APPLY_ENABLED ? 1 : 0);


    delay(500);

    Serial.printf(
        "\n[app] Mnemos T5S3 Pro v%s iniciando\n",
        Config::APP_VERSION);

    uiPreferences.begin(
        "mnemos-ui",
        false);

    backlightService.begin();

    /*
     * Wire é o dono do driver I2C0 nesta aplicação.
     * A cópia local do epdiy board_v7 é compilada com
     * MNEMOS_EXTERNAL_I2C_DRIVER e reutiliza o driver.
     */
    Wire.begin(
        Config::SYSTEM_I2C_SDA,
        Config::SYSTEM_I2C_SCL,
        Config::TOUCH_I2C_FREQUENCY);


    if (!display.begin()) {
        Serial.println(
            "[app] display indisponivel; "
            "sistema interrompido");

        while (true) {
            delay(1000);
        }
    }

    display.setOrientation(DisplayOrientation::Portrait);

    // VBUS vem do BQ25896; o BQ27220 é só sensor de bateria.
    powerService.begin();
    batteryService.begin(
        []() {
            return powerService.externalPowerPresent();
        });


    display.setBatteryStatus(
        batteryService.available(),
        batteryService.percent(),
        batteryService.charging());

    display.showBoot(
        "Inicializando T5S3 Pro...");

    storage.begin();
    networkService.begin();
    lastNetworkDemandMs = millis();

    display.setNetworkStatus(
        networkService.enabled(),
        networkService.connected());
    clockService.begin();
    touchInput.begin();
    sdCardService.begin();
    otaService.begin();

    if (
        Config::OTA_AUTO_APPLY_ENABLED &&
        sdCardService.mounted()
    ) {
        otaService.applyLocalUpdateIfRequested(
            batteryService.available(),
            batteryService.percent());
    }

    touchInput.setPortrait(true);

    bool libraryLoaded = false;

    if (
        Config::SD_FIRST_LIBRARY &&
        sdCardService.mounted() &&
        sdCardService.
            canonicalLibraryAvailable()
    ) {
        libraryLoaded =
            sdCardService.
                loadCatalog(
                    cards,
                    states,
                    Config::
                        MAX_DEVICE_CARDS,
                    cardCount);

        if (libraryLoaded) {
            Serial.printf(
                "[app] biblioteca SD-first: %u entradas de catalogo\n",
                static_cast<unsigned>(
                    cardCount));
        }
    }

    if (!libraryLoaded) {
        libraryLoaded =
            storage.loadLibrary(
                cards,
                states,
                Config::
                    MAX_DEVICE_CARDS,
                cardCount);

        if (!libraryLoaded) {
            cardCount =
                loadDefaultCards(
                    cards,
                    Config::
                        MAX_DEVICE_CARDS);

            for (
                size_t i = 0;
                i < cardCount;
                ++i
            ) {
                states[i] =
                    CardState{};

                states[i].id =
                    cards[i].id;
            }

            storage.saveLibrary(
                cards,
                states,
                cardCount);

            storage.saveStates(
                states,
                cardCount);

            libraryLoaded =
                cardCount > 0;
        }

        if (
            libraryLoaded &&
            Config::SD_FIRST_LIBRARY &&
            sdCardService.mounted()
        ) {
            if (
                sdCardService.
                    saveCanonicalLibrary(
                        cards,
                        cardCount)
            ) {
                sdCardService.
                    compactCatalog(
                        cards,
                        cardCount);
            }
        }
    }

    if (
        Config::
            SEED_MANDARIN_TRAINING_DECK &&
        !Config::SD_FIRST_LIBRARY
    ) {
        const size_t previousCount =
            cardCount;

        cardCount =
            appendMandarinTrainingDeck(
                cards,
                states,
                Config::
                    MAX_DEVICE_CARDS,
                cardCount);

        if (
            cardCount !=
            previousCount
        ) {
            storage.saveLibrary(
                cards,
                states,
                cardCount);

            storage.saveStates(
                states,
                cardCount);
        }

        if (
            refreshMandarinTrainingDeck(
                cards,
                cardCount)
        ) {
            storage.saveLibrary(
                cards,
                states,
                cardCount);
        }
    }

    backendSync.begin();

    // O Wi-Fi conecta de forma cooperativa no loop; a primeira sincronização
    // roda assim que houver rede (e só em telas fora do estudo).
    if (backendSync.paired()) {
        backendSync.requestSync(
            SyncTrigger::Boot,
            0);
    }

    Serial.printf(
        "[platform] terminal=%s backend=%s pareado=%d biblioteca=%s\n",
        TerminalIdentity::deviceId().c_str(),
        networkService.backendUrl().length() > 0
            ? networkService.backendUrl().c_str()
            : "-",
        backendSync.paired() ? 1 : 0,
        storage.libraryFromBackend()
            ? "conta"
            : "local");

    rebuildEngine();

    Serial.printf(
        "[sd-first] enabled=%d mounted=%d canonical=%d cards=%u heap=%u\n",
        Config::SD_FIRST_LIBRARY
            ? 1
            : 0,
        sdCardService.mounted()
            ? 1
            : 0,
        sdCardService.canonicalLibraryAvailable()
            ? 1
            : 0,
        static_cast<unsigned>(
            cardCount),
        static_cast<unsigned>(
            ESP.getFreeHeap()));

    if (
        Config::SD_FIRST_LIBRARY &&
        sdCardService.mounted() &&
        !sdCardService.canonicalLibraryAvailable()
    ) {
        Serial.printf(
            "[sd-first] fallback=LittleFS reason=%s\n",
            sdCardService.lastError().
                c_str());
    }

    if (touchInput.online()) {
        renderHome();
    } else {
        display.showTouchMissing();
    }

    otaService.confirmRunningImage();
    otaService.logStatus("setup-ready");
}

void loop() {
    if (
        batteryService.update()
    ) {
        display.setBatteryStatus(
            batteryService.available(),
            batteryService.percent(),
            batteryService.charging());

        // Atualizar o estado interno não altera fisicamente o e-paper.
        // BatteryService só retorna true quando o estado visível mudou.
        renderCurrentScreen();
    }

    if (powerOffRequested) {
        powerOffRequested = false;
        performPowerOff(false);
        return;
    }

    if (
        !activeStudyForPowerPolicy() &&
        !networkService.busy() &&
        !localLink.active() &&
        powerService.idleMs() >= Config::AUTO_POWER_OFF_IDLE_MS &&
        powerService.canPowerOff()
    ) {
        Serial.println(
            "[power] auto-off por inatividade");
        performPowerOff(true);
        return;
    }

    const PowerDecision powerDecision =
        powerService.evaluate(
            powerSleepAllowed(),
            batteryService.critical());

    if (
        powerDecision ==
        PowerDecision::DeepSleep
    ) {
        if (powerService.canPowerOff()) {
            performPowerOff(true);
        } else {
            /*
             * USB/VBUS presente ou PMIC indisponível:
             * não prender o aparelho em deep sleep.
             */
            Serial.println(
                "[power] hard-off adiado; "
                "mantendo terminal ativo");
            powerService.noteActivity();
        }

        return;
    }

    if (
        powerDecision ==
        PowerDecision::LightSleep
    ) {
        performLightSleep();
    }

    localLink.loop();

    JsonDocument serialCommand;
    if (serialConsole.poll(serialCommand)) {
        handleSerialCommand(serialCommand);
    }

    // Sincronização pedida (fim de sessão, provisionamento) acorda o rádio
    // que a política de energia tinha desligado.
    if (
        backendSync.hasPendingRequest() &&
        networkRadioSuspended &&
        !localLink.active()
    ) {
        noteNetworkDemand();
    }

    if (!networkRadioSuspended) {
        networkService.loop();
        display.setNetworkStatus(
            networkService.enabled(),
            networkService.connected());

        handleNetworkEvents();
    } else {
        display.setNetworkStatus(
            networkService.enabled(),
            false);
    }

    const bool wifiConnectedNow =
        networkService.connected();

    if (
        wifiConnectedNow &&
        !lastWifiConnected &&
        backendSync.paired()
    ) {
        const BackendSyncReport& last =
            backendSync.lastReport();

        const bool stale =
            last.outcome != SyncOutcome::Ok ||
            millis() - last.finishedAtMs > 60000UL;

        if (stale || storage.pendingReviewCount() > 0) {
            backendSync.requestSync(
                SyncTrigger::WifiConnected,
                PlatformSync::AUTO_SYNC_AFTER_CONNECT_DELAY_MS);
        }
    }

    lastWifiConnected =
        wifiConnectedNow;

    serviceNetworkPowerPolicy();
    if (clockService.maintain()) {
        if (screen == AppScreen::Home) {
            renderHome();
        } else if (screen == AppScreen::Agenda) {
            renderAgenda();
        }
    }

    if (
        !touchInput.online() &&
        millis() -
            lastTouchRetryMs >
            Config::TOUCH_RETRY_MS
    ) {
        lastTouchRetryMs =
            millis();

        if (
            touchInput.begin()
        ) {
            touchInput.setPortrait(true);

            renderHome();
        }
    }

    if (
        localLink.
            consumeLibraryUpdated()
    ) {
        canonicalizeActiveLibraryIfPossible();
        rebuildEngine();

        Serial.printf(
            "[app] biblioteca atualizada "
            "por Wi-Fi local: %u cartoes\n",
            static_cast<unsigned>(
                cardCount));
    }

    const bool nonStudyScreen =
        screen ==
            AppScreen::Home ||
        screen ==
            AppScreen::Menu ||
        screen ==
            AppScreen::Decks ||
        screen ==
            AppScreen::Agenda ||
        screen ==
            AppScreen::Sync ||
        screen ==
            AppScreen::Connection ||
        screen ==
            AppScreen::WifiNetworks ||
        screen ==
            AppScreen::WifiPassword ||
        screen ==
            AppScreen::WifiMessage ||
        screen ==
            AppScreen::Storage;

    if (
        nonStudyScreen &&
        !localLink.active() &&
        !networkRadioSuspended
    ) {
        backendSync.loop();

        if (applyBackendLibraryUpdate()) {
            if (
                screen ==
                AppScreen::Home
            ) {
                renderHome();
            } else if (
                screen ==
                AppScreen::Sync
            ) {
                renderSync();
            } else if (
                screen ==
                AppScreen::Decks
            ) {
                renderDecks();
            }
        }
    }

    if (
        screen ==
            AppScreen::LocalLink &&
        !localLink.active()
    ) {
        finishLocalLinkScreen();
    }

    MnemosTouchPoint point;

    if (
        !touchInput.poll(
            point)
    ) {
        delay(2);
        return;
    }

    const uint32_t now =
        millis();

    if (
        now -
            lastAcceptedTouchMs <
        Config::
            TOUCH_ACTION_DEBOUNCE_MS
    ) {
        Serial.printf(
            "[touch] raw=(%d,%d) logical=(%d,%d) "
            "ignored=debounce\n",
            point.rawX,
            point.rawY,
            point.x,
            point.y);

        return;
    }

    const RoutedTouch routed =
        routeTouch(
            point);

    Serial.printf(
        "[touch] screen=%s raw=(%d,%d) "
        "logical=(%d,%d) zone=%s action=%s arg=%d\n",
        appScreenName(
            screen),
        point.rawX,
        point.rawY,
        point.x,
        point.y,
        routed.zone,
        uiActionName(
            routed.action),
        routed.argument);

    if (
        routed.action ==
        UiAction::None
    ) {
        return;
    }

    lastAcceptedTouchMs =
        now;

    powerService.noteActivity();

    display.showTouchFeedback(
        routed.x,
        routed.y,
        routed.w,
        routed.h);

    const uint32_t actionStartedMs =
        millis();

    processAction(
        routed.action,
        routed.argument);

    Serial.printf(
        "[perf] action=%s total=%lums\n",
        uiActionName(
            routed.action),
        static_cast<unsigned long>(
            millis() -
            actionStartedMs));
}
