#include <Arduino.h>

#include "backend_sync_service.h"
#include "ble_sync_service.h"
#include "cards.h"
#include "config.h"
#include "cyd_display.h"
#include "network_service.h"
#include "pairing_service.h"
#include "storage.h"
#include "study_engine.h"
#include "time_service.h"

enum class AppScreen : uint8_t {
    Home,
    Sync,
    Connection,
    Pairing,
    BluetoothSync,
    Question,
    Answer,
    Summary,
};

Storage storage;
NetworkService networkService;
TimeService clockService;
CydDisplay display;
CardDefinition cards[Config::MAX_DEVICE_CARDS];
CardState states[Config::MAX_DEVICE_CARDS];
size_t cardCount = 0;
StudyEngine* engine = nullptr;
PairingService pairing(storage, clockService, networkService,
                       cards, states, Config::MAX_DEVICE_CARDS, cardCount);
BackendSyncService backendSync(networkService, storage,
                               cards, states, Config::MAX_DEVICE_CARDS, cardCount);
BleSyncService bleSync(storage, cards, states, Config::MAX_DEVICE_CARDS, cardCount);
AppScreen screen = AppScreen::Home;

void rebuildEngine() {
    if (engine != nullptr) {
        delete engine;
        engine = nullptr;
    }
    engine = new StudyEngine(cards, states, cardCount, storage, clockService);
    engine->initializeStates();
}

uint16_t pendingReviewCount() {
    const String rows = storage.reviewsNdjson();
    if (rows.length() == 0) return 0;
    uint16_t count = 0;
    for (size_t i = 0; i < rows.length(); ++i) {
        if (rows[i] == '\n') ++count;
    }
    if (!rows.endsWith("\n")) ++count;
    return count;
}

void renderHome() {
    screen = AppScreen::Home;
    display.showHome(engine == nullptr ? 0 : engine->dueCount(),
                     cardCount,
                     clockService.trusted(),
                     engine != nullptr && engine->hasResumableSession());
}

void renderSync() {
    screen = AppScreen::Sync;
    display.showSyncMenu(cardCount, pendingReviewCount(), networkService.connected());
}

void renderConnection() {
    screen = AppScreen::Connection;
    display.showConnectionMenu(networkService.enabled(),
                               networkService.connected(),
                               networkService.ssid(),
                               networkService.profileCount());
}

void renderQuestion() {
    screen = AppScreen::Question;
    display.showQuestion(engine->currentCard(),
                         engine->currentPosition(),
                         engine->sessionCount(),
                         engine->confidence());
}

void renderAnswer() {
    screen = AppScreen::Answer;
    display.showAnswer(engine->currentCard(),
                       engine->currentPosition(),
                       engine->sessionCount());
}

void renderSummary() {
    screen = AppScreen::Summary;
    display.showSummary(engine->stats(), engine->dueCount());
}

void startPairing() {
    if (!pairing.start()) return;
    screen = AppScreen::Pairing;
    display.showPairing(pairing.qrPayload(), pairing.ssid(), pairing.password());
}

void startBluetoothSync() {
    if (!bleSync.start()) return;
    screen = AppScreen::BluetoothSync;
    display.showBluetoothSync(bleSync.deviceId(), bleSync.connected());
}

void handleQuestionAction(UiAction action) {
    switch (action) {
        case UiAction::ConfidenceDontKnow:
            engine->setConfidence(Confidence::DontKnow);
            renderQuestion();
            break;
        case UiAction::ConfidenceMaybe:
            engine->setConfidence(Confidence::Maybe);
            renderQuestion();
            break;
        case UiAction::ConfidenceCertain:
            engine->setConfidence(Confidence::Certain);
            renderQuestion();
            break;
        case UiAction::Reveal:
            if (engine->canReveal()) {
                engine->revealCurrent();
                renderAnswer();
            }
            break;
        default:
            break;
    }
}

void handleAnswerAction(UiAction action) {
    Rating rating;
    bool hasRating = true;
    switch (action) {
        case UiAction::RateAgain: rating = Rating::Again; break;
        case UiAction::RateHard: rating = Rating::Hard; break;
        case UiAction::RateGood: rating = Rating::Good; break;
        case UiAction::RateEasy: rating = Rating::Easy; break;
        default: hasRating = false; break;
    }
    if (!hasRating) return;
    const bool finished = engine->rateCurrent(rating);
    if (finished) renderSummary();
    else renderQuestion();
}

void setup() {
    Serial.begin(115200);
    delay(200);
    Serial.printf("\n[app] Mnemos v%s iniciando\n", Config::APP_VERSION);

    display.begin();
    display.showBoot("Inicializando...");
    storage.begin();
    networkService.begin();
    clockService.begin();

    if (!storage.loadLibrary(cards, states, Config::MAX_DEVICE_CARDS, cardCount)) {
        cardCount = loadDefaultCards(cards, Config::MAX_DEVICE_CARDS);
        for (size_t i = 0; i < cardCount; ++i) {
            states[i] = CardState{};
            states[i].id = cards[i].id;
        }
        storage.saveLibrary(cards, states, cardCount);
    }

    backendSync.begin();
    if (networkService.connected() && networkService.backendUrl().length() > 0) {
        backendSync.syncNow();
    }

    rebuildEngine();
    delay(350);
    renderHome();
}

void loop() {
    pairing.loop();
    bleSync.loop();
    networkService.loop();

    if (pairing.consumeLibraryUpdated() || bleSync.consumeLibraryUpdated()) {
        rebuildEngine();
        Serial.printf("[app] biblioteca local atualizada: %u cartoes\n",
                      static_cast<unsigned>(cardCount));
    }

    const bool nonStudyScreen = screen == AppScreen::Home ||
                                screen == AppScreen::Sync ||
                                screen == AppScreen::Connection;
    if (nonStudyScreen && !pairing.active() && !bleSync.active()) {
        backendSync.loop();
        if (backendSync.consumeLibraryUpdated()) {
            rebuildEngine();
            if (screen == AppScreen::Home) renderHome();
            else if (screen == AppScreen::Sync) renderSync();
            Serial.printf("[app] biblioteca atualizada pelo backend: %u cartoes\n",
                          static_cast<unsigned>(cardCount));
        }
    }

    if (screen == AppScreen::Pairing && !pairing.active()) {
        rebuildEngine();
        renderConnection();
    }
    if (screen == AppScreen::BluetoothSync) {
        if (!bleSync.active()) {
            rebuildEngine();
            renderSync();
        } else {
            static bool lastConnected = false;
            if (lastConnected != bleSync.connected()) {
                lastConnected = bleSync.connected();
                display.showBluetoothSync(bleSync.deviceId(), lastConnected);
            }
        }
    }

    const UiAction action = display.pollAction();
    if (action == UiAction::None) {
        delay(8);
        return;
    }

    switch (screen) {
        case AppScreen::Home:
            if (action == UiAction::Start && engine != nullptr &&
                (engine->hasResumableSession() ? engine->resumeSession() : engine->startSession())) {
                renderQuestion();
            } else if (action == UiAction::OpenSync) {
                renderSync();
            } else if (action == UiAction::OpenConnection) {
                renderConnection();
            }
            break;

        case AppScreen::Sync:
            if (action == UiAction::SyncBackend) {
                if (backendSync.syncNow() && backendSync.consumeLibraryUpdated()) rebuildEngine();
                renderSync();
            } else if (action == UiAction::SyncBluetooth) {
                startBluetoothSync();
            } else if (action == UiAction::Back) {
                renderHome();
            }
            break;

        case AppScreen::Connection:
            if (action == UiAction::ConfigureNetwork) {
                startPairing();
            } else if (action == UiAction::ToggleWifi) {
                if (networkService.enabled()) networkService.disable();
                else networkService.enable();
                renderConnection();
            } else if (action == UiAction::Back) {
                renderHome();
            }
            break;

        case AppScreen::Pairing:
            if (action == UiAction::CancelPairing) {
                pairing.stop();
                renderConnection();
            }
            break;

        case AppScreen::BluetoothSync:
            if (action == UiAction::CancelBluetooth) {
                bleSync.stop();
                renderSync();
            }
            break;

        case AppScreen::Question:
            handleQuestionAction(action);
            break;

        case AppScreen::Answer:
            handleAnswerAction(action);
            break;

        case AppScreen::Summary:
            if (action == UiAction::Home) renderHome();
            break;
    }
}
