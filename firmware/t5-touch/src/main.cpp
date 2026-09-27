#include <Arduino.h>
#include <algorithm>
#include <Preferences.h>
#include <ctime>

#include "backend_sync_service.h"
#include "battery_service.h"
#include "cards.h"
#include "config.h"
#include "hmi_layout.h"
#include "local_link_service.h"
#include "metrics_service.h"
#include "network_service.h"
#include "schedule_service.h"
#include "sd_card_service.h"
#include "storage.h"
#include "study_engine.h"
#include "t5_display.h"
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
Preferences uiPreferences;
Storage storage;
NetworkService networkService;
SdCardService sdCardService;
TimeService clockService;
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

bool localLinkProvisioning = false;

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

String sdPaths[SdCardService::MAX_VISIBLE_FILES];
String sdNames[SdCardService::MAX_VISIBLE_FILES];
uint32_t sdSizes[SdCardService::MAX_VISIBLE_FILES] = {0};
size_t sdFileCount = 0;
String sdStatus;

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
            Config::GMT_OFFSET_SECONDS) +
        static_cast<int64_t>(
            Config::DAYLIGHT_OFFSET_SECONDS);

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
            Config::GMT_OFFSET_SECONDS) -
        static_cast<int64_t>(
            Config::DAYLIGHT_OFFSET_SECONDS);

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
        Config::GMT_OFFSET_SECONDS +
        Config::DAYLIGHT_OFFSET_SECONDS;

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
        screen == AppScreen::Agenda ||
        screen == AppScreen::Sync ||
        screen == AppScreen::Connection;
}

bool orientationAvailable() {
    return
        screen !=
        AppScreen::LocalLink;
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

void scanWifiNetworks() {
    screen = AppScreen::WifiNetworks;
    display.showWifiScanning();

    wifiScanCount = networkService.scanVisible(
        wifiScan,
        NetworkService::MAX_SCAN_RESULTS);

    wifiSelectedIndex = -1;
    wifiPassword = "";
    wifiHint = "";
    renderWifiNetworks();
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

void selectWifiNetwork(int8_t index) {
    if (
        index < 0 ||
        static_cast<size_t>(index) >= wifiScanCount
    ) {
        return;
    }

    wifiSelectedIndex = index;
    NetworkScanResult& selected = wifiScan[index];

    if (selected.enterprise) {
        wifiMessageTitle = "Rede corporativa";
        wifiMessageText =
            "Esta rede exige identidade/usuário. Use Configurar pelo celular para informar as credenciais corporativas.";
        wifiMessagePrimary = "Voltar à conexão";
        renderWifiMessage();
        return;
    }

    if (selected.known) {
        showWifiConnecting(selected.ssid);
        if (networkService.connectSavedSsid(selected.ssid)) {
            renderConnection();
        } else {
            if (!selected.open) {
                selected.known = false;
                wifiPassword = "";
                wifiKeyboardPage = WifiKeyboardPage::Lower;
                wifiHint = "A credencial salva falhou. Digite a senha novamente.";
                renderWifiPassword();
            } else {
                wifiMessageTitle = "Falha ao conectar";
                wifiMessageText = friendlyWifiError();
                wifiMessagePrimary = "Voltar à conexão";
                renderWifiMessage();
            }
        }
        return;
    }

    if (selected.open) {
        showWifiConnecting(selected.ssid);
        if (networkService.connectAndStore(selected.ssid, "", true)) {
            renderConnection();
        } else {
            wifiMessageTitle = "Falha ao conectar";
            wifiMessageText = friendlyWifiError();
            wifiMessagePrimary = "Voltar à conexão";
            renderWifiMessage();
        }
        return;
    }

    wifiPassword = "";
    wifiKeyboardPage = WifiKeyboardPage::Lower;
    wifiHint = "";
    renderWifiPassword();
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

void renderQuestion() {
    screen =
        AppScreen::Question;

    display.showQuestion(
        engine->currentCard(),
        engine->currentPosition(),
        engine->sessionCount());
}

void renderSelfAssessment() {
    screen =
        AppScreen::SelfAssessment;

    display.showSelfAssessment(
        engine->currentCard(),
        engine->currentPosition(),
        engine->sessionCount());
}

void renderObjectiveFeedback() {
    screen =
        AppScreen::
            ObjectiveFeedback;

    display.
        showObjectiveFeedback(
            engine->currentCard(),
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

    if (
        engine == nullptr ||
        cardCount == 0
    ) {
        return false;
    }

    if (
        engine->
            hasResumableSession()
    ) {
        return
            engine->
                resumeSession();
    }

    if (useDeckFilter) {
        applyDeckFilter();
    } else {
        engine->
            clearCardFilter();
    }

    if (
        engine->
            startReviewSession()
    ) {
        return true;
    }

    return
        engine->
            startPracticeSession();
}

void advanceAfterCommit(
    bool finished) {

    pendingOutcome =
        Outcome::Unknown;

    if (finished) {
        renderSummary();
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
    int8_t argument = -1) {

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
            portrait);

    const int16_t actionTop =
        actionZone.y;

        if (homeAvailable()) {
        addZone(
            zones,
            count,
            "system_home",
            12,
            portrait ? 16 : 8,
            56,
            56,
            UiAction::Home);
    }

    if (menuAvailable()) {
        addZone(
            zones,
            count,
            "system_menu",
            homeAvailable() ? 76 : 12,
            homeAvailable() ? (portrait ? 16 : 8) : 0,
            homeAvailable() ? 56 : 88,
            homeAvailable() ? 56 : (portrait ? 88 : 72),
            UiAction::OpenMenu);
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
            portrait
                ? 472
                : 892,
            portrait
                ? 16
                : 8,
            56,
            56,
            UiAction::
                AbortSession);
    }

    switch (screen) {
        case AppScreen::Home:
            addZone(
                zones,
                count,
                "home_primary",
                actionZone.x,
                actionZone.y,
                actionZone.w,
                actionZone.h,
                UiAction::
                    PrimaryStudy);
            break;

        case AppScreen::Menu: {
            const UiAction actions[5] = {
                UiAction::OpenDecks,
                UiAction::OpenAgenda,
                UiAction::OpenSync,
                UiAction::OpenConnection,
                UiAction::OpenStorage
            };

            const char* names[5] = {
                "menu_decks",
                "menu_agenda",
                "menu_sync",
                "menu_connection",
                "menu_storage"
            };

            for (
                uint8_t i = 0;
                i < 5;
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
                48,
                actionTop,
                width - 96,
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
                    48,
                    290,
                    width - 96,
                    112,
                    UiAction::
                        SyncBackend);

                addZone(
                    zones,
                    count,
                    "sync_phone",
                    48,
                    430,
                    width - 96,
                    112,
                    UiAction::
                        SyncPhone);
            } else {
                addZone(
                    zones,
                    count,
                    "sync_account",
                    48,
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
                48,
                actionTop,
                width - 96,
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
                    addZone(zones, count, "wifi_network", 48, 142 + static_cast<int16_t>(i) * 100, width - 96, 86, UiAction::SelectWifiNetwork, static_cast<int8_t>(i));
                }
            } else {
                for (size_t i = 0; i < visible; ++i) {
                    addZone(zones, count, "wifi_network", 48 + (i % 2) * 456, 112 + (i / 2) * 110, 408, 96, UiAction::SelectWifiNetwork, static_cast<int8_t>(i));
                }
            }
            addZone(zones, count, "wifi_rescan", 48, actionTop, width - 96, portrait ? 136 : 72, UiAction::ScanWifi);
            break;
        }

        case AppScreen::WifiPassword: {
            const size_t keyCount = wifiKeyboardCharCount(wifiKeyboardPage);
            const int16_t cols = portrait ? 6 : 9;
            const int16_t gap = portrait ? 6 : 8;
            const int16_t totalW = width - 96;
            const int16_t keyW = (totalW - (cols - 1) * gap) / cols;
            const int16_t keyH = portrait ? 58 : 46;
            const int16_t startY = portrait ? 300 : 212;
            const int16_t rows = static_cast<int16_t>((keyCount + cols - 1) / cols);

            for (size_t i = 0; i < keyCount; ++i) {
                const char key = wifiKeyboardCharAt(wifiKeyboardPage, i);
                addZone(
                    zones, count, "wifi_key",
                    48 + static_cast<int16_t>(i % cols) * (keyW + gap),
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
            addZone(zones, count, "wifi_shift", 48, controlY, w1, controlH, UiAction::WifiShift);
            addZone(zones, count, "wifi_symbols", 48 + w1 + controlGap, controlY, w2, controlH, UiAction::WifiSymbols);
            addZone(zones, count, "wifi_space", 48 + w1 + w2 + 2 * controlGap, controlY, w3, controlH, UiAction::WifiSpace);
            addZone(zones, count, "wifi_backspace", 48 + w1 + w2 + w3 + 3 * controlGap, controlY, w4, controlH, UiAction::WifiBackspace);

            const int16_t buttonW = (width - 96 - 24) / 2;
            addZone(zones, count, "wifi_cancel", 48, actionTop, buttonW, portrait ? 136 : 72, UiAction::WifiCancel);
            addZone(zones, count, "wifi_connect", 48 + buttonW + 24, actionTop, buttonW, portrait ? 136 : 72, UiAction::WifiConnect);
            break;
        }

        case AppScreen::WifiMessage:
            addZone(zones, count, "wifi_message_back", 48, actionTop, width - 96, portrait ? 136 : 72, UiAction::WifiCancel);
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
                48,
                actionTop,
                width - 96,
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

            if (
                !engine->
                    currentIsObjective()
            ) {
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
                    UiAction::
                        AnswerReady);

                break;
            }

            for (
                uint8_t i = 0;
                i <
                    engine->
                        currentCard().
                        optionCount &&
                i < 4;
                ++i
            ) {
                addZone(
                    zones,
                    count,
                    "question_choice",
                    portrait
                        ? 48
                        : 504,
                    portrait
                        ? 390 +
                              i * 98
                        : 112 +
                              i * 84,
                    portrait
                        ? width - 96
                        : 408,
                    portrait
                        ? 90
                        : 74,
                    static_cast<UiAction>(
                        static_cast<uint8_t>(
                            UiAction::Choice0) +
                        i),
                    static_cast<int8_t>(
                        i));
            }
            break;

        case AppScreen::SelfAssessment: {
            const int16_t gap =
                24;

            const int16_t totalW =
                width - 96;

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
                48,
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
                48 +
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
                48,
                actionTop,
                width - 96,
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
                width - 96;

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
                    48 +
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
                48,
                actionTop,
                width - 96,
                portrait
                    ? 136
                    : 72,
                UiAction::Continue);
            break;

        case AppScreen::AbortConfirm: {
            const int16_t gap =
                24;

            const int16_t totalW =
                width - 96;

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
                48,
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
                48 +
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
    const DisplayOrientation next =
        display.portrait()
            ? DisplayOrientation::
                  Landscape
            : DisplayOrientation::
                  Portrait;

    display.setOrientation(
        next);

    touchInput.setPortrait(
        next ==
        DisplayOrientation::
            Portrait);

    uiPreferences.putBool(
        "portraitV6",
        next ==
        DisplayOrientation::
            Portrait);

    Serial.printf(
        "[ui] orientation=%s\n",
        next ==
                DisplayOrientation::
                    Portrait
            ? "portrait"
            : "landscape");

    renderCurrentScreen();
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

    switch (screen) {
        case AppScreen::Home:
            if (
                action ==
                UiAction::
                    PrimaryStudy
            ) {
                clearDeckSelection();

                if (
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
                UiAction::OpenAgenda
            ) {
                renderAgenda();
            } else if (
                action ==
                UiAction::OpenSync
            ) {
                renderSync();
            } else if (
                action ==
                UiAction::
                    OpenConnection
            ) {
                renderConnection();
            } else if (
                action ==
                UiAction::OpenStorage
            ) {
                sdStatus = "";
                renderStorage();
            } else if (
                action ==
                UiAction::Back
            ) {
                renderHome();
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
                if (
                    backendSync.
                        syncNow() &&
                    backendSync.
                        consumeLibraryUpdated()
                ) {
                    rebuildEngine();
                }

                renderSync();
            } else if (
                action ==
                UiAction::SyncPhone
            ) {
                startLocalLink(
                    LocalLinkMode::
                        DirectSync);
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
            if (action == UiAction::WifiKey) {
                if (wifiPassword.length() < 63) {
                    wifiPassword += static_cast<char>(static_cast<uint8_t>(argument));
                    wifiHint = "";
                    renderWifiPassword();
                }
            } else if (action == UiAction::WifiSpace) {
                if (wifiPassword.length() < 63) {
                    wifiPassword += ' ';
                    wifiHint = "";
                    renderWifiPassword();
                }
            } else if (action == UiAction::WifiBackspace) {
                if (wifiPassword.length() > 0) wifiPassword.remove(wifiPassword.length() - 1);
                wifiHint = "";
                renderWifiPassword();
            } else if (action == UiAction::WifiShift) {
                wifiKeyboardPage = wifiKeyboardPage == WifiKeyboardPage::Upper
                    ? WifiKeyboardPage::Lower
                    : WifiKeyboardPage::Upper;
                renderWifiPassword();
            } else if (action == UiAction::WifiSymbols) {
                wifiKeyboardPage = wifiKeyboardPage == WifiKeyboardPage::Symbols
                    ? WifiKeyboardPage::Lower
                    : WifiKeyboardPage::Symbols;
                renderWifiPassword();
            } else if (action == UiAction::WifiCancel) {
                renderWifiNetworks();
            } else if (action == UiAction::WifiConnect) {
                if (wifiPassword.length() < 8 || wifiPassword.length() > 63) {
                    wifiHint = "A senha deve ter entre 8 e 63 caracteres.";
                    renderWifiPassword();
                    break;
                }
                if (wifiSelectedIndex < 0 || static_cast<size_t>(wifiSelectedIndex) >= wifiScanCount) {
                    renderConnection();
                    break;
                }
                const String ssid = wifiScan[wifiSelectedIndex].ssid;
                showWifiConnecting(ssid);
                if (networkService.connectAndStore(ssid, wifiPassword, false)) {
                    wifiPassword = "";
                    renderConnection();
                } else {
                    wifiHint = friendlyWifiError();
                    renderWifiPassword();
                }
            }
            break;

        case AppScreen::WifiMessage:
            if (action == UiAction::WifiCancel) {
                renderConnection();
            }
            break;

        case AppScreen::Storage:
            if (action == UiAction::RefreshSd) {
                sdStatus = "";
                refreshSdView(true);
                renderStorage();
            } else if (action == UiAction::ImportSdFile) {
                if (argument >= 0 && static_cast<size_t>(argument) < sdFileCount) {
                    const SdImportResult result = sdCardService.importDeckFile(
                        sdPaths[argument], cards, states, Config::MAX_DEVICE_CARDS, cardCount);
                    if (result.ok) {
                        storage.saveLibrary(cards, states, cardCount);
                        rebuildEngine();
                        sdStatus = "Importados " + String(result.added) +
                            ", atualizados " + String(result.updated) +
                            ", ignorados " + String(result.skipped);
                    } else {
                        sdStatus = result.error;
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
            }
            break;

        case AppScreen::LocalLink:
            if (
                action ==
                UiAction::
                    CancelLocalLink
            ) {
                localLink.stop();
                rebuildEngine();
                renderMenu();
            }
            break;

        case AppScreen::Question: {
            if (!engine) {
                break;
            }

            if (
                !engine->
                    currentIsObjective() &&
                action ==
                    UiAction::
                        AnswerReady
            ) {
                engine->
                    markResponseReady();

                renderSelfAssessment();
                break;
            }

            int option =
                -1;

            if (
                action ==
                UiAction::Choice0
            ) {
                option = 0;
            } else if (
                action ==
                UiAction::Choice1
            ) {
                option = 1;
            } else if (
                action ==
                UiAction::Choice2
            ) {
                option = 2;
            } else if (
                action ==
                UiAction::Choice3
            ) {
                option = 3;
            }

            if (
                option >= 0 &&
                engine->
                    selectOption(
                        static_cast<uint8_t>(
                            option))
            ) {
                pendingOutcome =
                    engine->
                        evaluateAutomatic();

                renderObjectiveFeedback();
            }

            break;
        }

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

void setup() {
    Serial.begin(
        115200);

    delay(500);

    Serial.printf(
        "\n[app] Mnemos T5 v%s iniciando\n",
        Config::APP_VERSION);

    uiPreferences.begin(
        "mnemos-ui",
        false);

    const bool startPortrait =
        uiPreferences.getBool(
            "portraitV6",
            true);

    if (!display.begin()) {
        Serial.println(
            "[app] display indisponivel; "
            "sistema interrompido");

        while (true) {
            delay(1000);
        }
    }

    display.setOrientation(
        startPortrait
            ? DisplayOrientation::
                  Portrait
            : DisplayOrientation::
                  Landscape);

    batteryService.begin();

    display.setBatteryStatus(
        batteryService.available(),
        batteryService.percent());

    display.showBoot(
        "Inicializando T5 Touch...");

    storage.begin();
    networkService.begin();
    clockService.begin();
    touchInput.begin();
    sdCardService.begin();

    touchInput.setPortrait(
        startPortrait);

    if (
        !storage.loadLibrary(
            cards,
            states,
            Config::MAX_DEVICE_CARDS,
            cardCount)
    ) {
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
    }

    if (
        Config::
            SEED_MANDARIN_TRAINING_DECK
    ) {
        const size_t previousCount =
            cardCount;

        cardCount =
            appendMandarinTrainingDeck(
                cards,
                states,
                Config::MAX_DEVICE_CARDS,
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

    backendSync.begin();

    if (
        networkService.connected() &&
        networkService.
            backendUrl().
            length() > 0
    ) {
        backendSync.syncNow();
    }

    rebuildEngine();

    if (touchInput.online()) {
        renderHome();
    } else {
        display.showTouchMissing();
    }
}

void loop() {
    if (
        batteryService.update()
    ) {
        display.setBatteryStatus(
            batteryService.available(),
            batteryService.percent());
    }

    localLink.loop();
    networkService.loop();

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
            touchInput.setPortrait(
                display.portrait());

            renderHome();
        }
    }

    if (
        localLink.
            consumeLibraryUpdated()
    ) {
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
        !localLink.active()
    ) {
        backendSync.loop();

        if (
            backendSync.
                consumeLibraryUpdated()
        ) {
            rebuildEngine();

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
        rebuildEngine();
        renderMenu();
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

    display.showTouchFeedback(
        routed.x,
        routed.y,
        routed.w,
        routed.h);

    processAction(
        routed.action,
        routed.argument);
}
