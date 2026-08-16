#include <Arduino.h>

#include "backend_sync_service.h"
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
    Pairing,
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
AppScreen screen = AppScreen::Home;

void rebuildEngine() {
    if (engine != nullptr) {
        delete engine;
        engine = nullptr;
    }
    engine = new StudyEngine(cards, states, cardCount, storage, clockService);
    engine->initializeStates();
}

void renderHome() {
    screen = AppScreen::Home;
    display.showHome(engine == nullptr ? 0 : engine->dueCount(),
                     cardCount,
                     clockService.trusted(),
                     networkService.enabled(),
                     networkService.connected());
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
    networkService.loop();

    if (pairing.consumeLibraryUpdated()) {
        rebuildEngine();
        Serial.printf("[app] biblioteca atualizada pelo app: %u cartoes\n",
                      static_cast<unsigned>(cardCount));
    }

    if (screen == AppScreen::Home) {
        backendSync.loop();
        if (backendSync.consumeLibraryUpdated()) {
            rebuildEngine();
            renderHome();
            Serial.printf("[app] biblioteca atualizada pelo backend: %u cartoes\n",
                          static_cast<unsigned>(cardCount));
        }
    }

    if (screen == AppScreen::Pairing && !pairing.active()) {
        rebuildEngine();
        if (networkService.connected() && networkService.backendUrl().length() > 0) {
            backendSync.syncNow();
            if (backendSync.consumeLibraryUpdated()) rebuildEngine();
        }
        renderHome();
    }

    const UiAction action = display.pollAction();
    if (action == UiAction::None) {
        delay(8);
        return;
    }

    switch (screen) {
        case AppScreen::Home:
            if (action == UiAction::Start && engine != nullptr && engine->startSession()) {
                renderQuestion();
            } else if (action == UiAction::PairDevice) {
                startPairing();
            } else if (action == UiAction::ToggleWifi) {
                if (networkService.enabled()) {
                    networkService.disable();
                } else {
                    networkService.enable();
                    if (networkService.connected() && networkService.backendUrl().length() > 0) {
                        backendSync.syncNow();
                        if (backendSync.consumeLibraryUpdated()) rebuildEngine();
                    }
                }
                renderHome();
            }
            break;

        case AppScreen::Pairing:
            if (action == UiAction::CancelPairing) {
                pairing.stop();
                renderHome();
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
