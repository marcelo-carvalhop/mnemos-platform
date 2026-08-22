#include <Arduino.h>

#include "backend_sync_service.h"
#include "cards.h"
#include "config.h"
#include "cyd_display.h"
#include "learning_model.h"
#include "local_link_service.h"
#include "metrics_service.h"
#include "network_service.h"
#include "schedule_service.h"
#include "storage.h"
#include "study_engine.h"
#include "time_service.h"

enum class AppScreen : uint8_t {
    Home,
    Menu,
    Agenda,
    Sync,
    Connection,
    LocalLink,
    Question,
    Confidence,
    SelfAssessment,
    ObjectiveFeedback,
    Effort,
    Summary,
};

Storage storage;
NetworkService networkService;
TimeService clockService;
LearningModel learningModel;
CydDisplay display;
CardDefinition cards[Config::MAX_DEVICE_CARDS];
CardState states[Config::MAX_DEVICE_CARDS];
size_t cardCount = 0;
ScheduleService scheduleService(clockService, states, cardCount);
StudyEngine* engine = nullptr;
MetricsService metrics(storage, clockService, cards, states, cardCount);
LocalLinkService localLink(storage, clockService, networkService, metrics,
                           cards, states, Config::MAX_DEVICE_CARDS, cardCount);
BackendSyncService backendSync(networkService, storage,
                               cards, states, Config::MAX_DEVICE_CARDS, cardCount);
AppScreen screen = AppScreen::Home;
Outcome pendingOutcome = Outcome::Unknown;

void rebuildEngine() {
    if (engine != nullptr) {
        delete engine;
        engine = nullptr;
    }
    engine = new StudyEngine(cards, states, cardCount, storage, clockService, learningModel);
    engine->initializeStates();
}

void renderHome() {
    screen = AppScreen::Home;
    const ScheduleOverview overview = scheduleService.snapshot();
    String nextReview = overview.nextReviewAt == 0 ? "" : scheduleService.humanize(overview.nextReviewAt);
    if (!clockService.trusted() && overview.nextReviewAt != 0) nextReview += " (aprox.)";
    display.showHome(overview.dueNow,
                     overview.newCards,
                     cardCount,
                     clockService.trusted(),
                     engine != nullptr && engine->hasResumableSession(),
                     nextReview);
}

void renderMenu() {
    screen = AppScreen::Menu;
    display.showMainMenu();
}

void renderAgenda() {
    screen = AppScreen::Agenda;
    const ScheduleOverview overview = scheduleService.snapshot();
    String nextReview = overview.dueNow > 0 ? "agora" : scheduleService.humanize(overview.nextReviewAt);
    if (!clockService.trusted() && overview.nextReviewAt != 0) nextReview += " (aprox.)";
    display.showAgenda(overview.dueNow, overview.laterToday, overview.tomorrow,
                       overview.next7Days, nextReview);
}

void renderSync() {
    screen = AppScreen::Sync;
    display.showSyncMenu(cardCount, storage.pendingReviewCount(), networkService.connected());
}

void renderConnection() {
    screen = AppScreen::Connection;
    display.showConnectionMenu(networkService.enabled(), networkService.connected(),
                               networkService.ssid(), networkService.profileCount());
}

void renderQuestion() {
    screen = AppScreen::Question;
    display.showQuestion(engine->currentCard(), engine->currentPosition(), engine->sessionCount());
}

void renderConfidence() {
    screen = AppScreen::Confidence;
    display.showConfidence(engine->currentCard(), engine->currentPosition(), engine->sessionCount());
}

void renderSelfAssessment() {
    screen = AppScreen::SelfAssessment;
    display.showSelfAssessment(engine->currentCard(), engine->currentPosition(), engine->sessionCount());
}

void renderObjectiveFeedback() {
    screen = AppScreen::ObjectiveFeedback;
    display.showObjectiveFeedback(engine->currentCard(), engine->currentPosition(), engine->sessionCount(),
                                  engine->selectedOptionIndex(), pendingOutcome);
}

void renderEffort() {
    screen = AppScreen::Effort;
    display.showEffort(engine->currentPosition(), engine->sessionCount());
}

void renderSummary() {
    screen = AppScreen::Summary;
    const ScheduleOverview overview = scheduleService.snapshot();
    String nextReview = overview.nextReviewAt == 0 ? "" : scheduleService.humanize(overview.nextReviewAt);
    if (!clockService.trusted() && overview.nextReviewAt != 0) nextReview += " (aprox.)";
    display.showSummary(engine->stats(), overview.dueNow, overview.newCards, nextReview);
}

bool startStudyFromCurrentState() {
    if (engine == nullptr || cardCount == 0) return false;
    if (engine->hasResumableSession()) return engine->resumeSession();
    const ScheduleOverview overview = scheduleService.snapshot();
    if (overview.dueNow > 0 || overview.newCards > 0) return engine->startReviewSession();
    return engine->startPracticeSession();
}

void advanceAfterCommit(bool finished, Outcome committedOutcome) {
    (void)committedOutcome;
    pendingOutcome = Outcome::Unknown;
    if (finished) renderSummary();
    else renderQuestion();
}

void startLocalLink(LocalLinkMode mode) {
    if (!localLink.start(mode)) return;
    screen = AppScreen::LocalLink;
    display.showLocalLink(localLink.qrPayload(), localLink.ssid(), localLink.password(),
                          mode == LocalLinkMode::Provisioning);
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
        storage.saveStates(states, cardCount);
    }

    backendSync.begin();
    if (networkService.connected() && networkService.backendUrl().length() > 0) backendSync.syncNow();

    rebuildEngine();
    delay(300);
    renderHome();
}

void loop() {
    localLink.loop();
    networkService.loop();

    if (localLink.consumeLibraryUpdated()) {
        rebuildEngine();
        Serial.printf("[app] biblioteca atualizada por Wi-Fi local: %u cartoes\n",
                      static_cast<unsigned>(cardCount));
    }

    const bool nonStudyScreen = screen == AppScreen::Home || screen == AppScreen::Menu ||
                                screen == AppScreen::Agenda || screen == AppScreen::Sync || screen == AppScreen::Connection;
    if (nonStudyScreen && !localLink.active()) {
        backendSync.loop();
        if (backendSync.consumeLibraryUpdated()) {
            rebuildEngine();
            if (screen == AppScreen::Home) renderHome();
            else if (screen == AppScreen::Sync) renderSync();
            Serial.printf("[app] biblioteca atualizada pelo backend: %u cartoes\n",
                          static_cast<unsigned>(cardCount));
        }
    }

    if (screen == AppScreen::LocalLink && !localLink.active()) {
        rebuildEngine();
        renderMenu();
    }

    const UiAction action = display.pollAction();
    if (action == UiAction::None) {
        delay(8);
        return;
    }

    switch (screen) {
        case AppScreen::Home:
            if (action == UiAction::PrimaryStudy && startStudyFromCurrentState()) renderQuestion();
            else if (action == UiAction::OpenMenu) renderMenu();
            break;

        case AppScreen::Menu:
            if (action == UiAction::OpenSync) renderSync();
            else if (action == UiAction::OpenAgenda) renderAgenda();
            else if (action == UiAction::OpenConnection) renderConnection();
            else if (action == UiAction::Back) renderHome();
            break;

        case AppScreen::Agenda:
            if (action == UiAction::Back) renderMenu();
            break;

        case AppScreen::Sync:
            if (action == UiAction::SyncBackend) {
                if (backendSync.syncNow() && backendSync.consumeLibraryUpdated()) rebuildEngine();
                renderSync();
            } else if (action == UiAction::SyncPhone) {
                startLocalLink(LocalLinkMode::DirectSync);
            } else if (action == UiAction::Back) {
                renderMenu();
            }
            break;

        case AppScreen::Connection:
            if (action == UiAction::ConfigureNetwork) {
                startLocalLink(LocalLinkMode::Provisioning);
            } else if (action == UiAction::ToggleWifi) {
                if (networkService.enabled()) networkService.disable();
                else networkService.enable();
                renderConnection();
            } else if (action == UiAction::Back) {
                renderMenu();
            }
            break;

        case AppScreen::LocalLink:
            if (action == UiAction::CancelLocalLink) {
                localLink.stop();
                rebuildEngine();
                renderMenu();
            }
            break;

        case AppScreen::Question:
            if (action == UiAction::AnswerReady && !engine->currentIsObjective()) {
                engine->markResponseReady();
                renderConfidence();
            } else {
                int option = -1;
                if (action == UiAction::Choice0) option = 0;
                else if (action == UiAction::Choice1) option = 1;
                else if (action == UiAction::Choice2) option = 2;
                else if (action == UiAction::Choice3) option = 3;
                if (option >= 0 && engine->selectOption(static_cast<uint8_t>(option))) renderConfidence();
            }
            break;

        case AppScreen::Confidence: {
            Confidence confidence = Confidence::None;
            if (action == UiAction::ConfidenceLow) confidence = Confidence::Low;
            else if (action == UiAction::ConfidenceMedium) confidence = Confidence::Medium;
            else if (action == UiAction::ConfidenceHigh) confidence = Confidence::High;
            if (confidence == Confidence::None) break;
            engine->setConfidence(confidence);
            if (engine->currentIsObjective()) {
                pendingOutcome = engine->evaluateAutomatic();
                renderObjectiveFeedback();
            } else {
                renderSelfAssessment();
            }
            break;
        }

        case AppScreen::SelfAssessment:
            if (action == UiAction::SelfIncorrect) {
                advanceAfterCommit(engine->commitCurrent(Outcome::Incorrect, Effort::None), Outcome::Incorrect);
            } else if (action == UiAction::SelfCorrect) {
                pendingOutcome = Outcome::Correct;
                renderEffort();
            }
            break;

        case AppScreen::ObjectiveFeedback:
            if (action == UiAction::Continue) {
                if (pendingOutcome == Outcome::Correct) renderEffort();
                else advanceAfterCommit(engine->commitCurrent(Outcome::Incorrect, Effort::None), Outcome::Incorrect);
            }
            break;

        case AppScreen::Effort: {
            Effort effort = Effort::None;
            if (action == UiAction::EffortDifficult) effort = Effort::Difficult;
            else if (action == UiAction::EffortNormal) effort = Effort::Normal;
            else if (action == UiAction::EffortEasy) effort = Effort::Easy;
            if (effort != Effort::None) advanceAfterCommit(engine->commitCurrent(Outcome::Correct, effort), Outcome::Correct);
            break;
        }

        case AppScreen::Summary:
            if (action == UiAction::StudyAgain) {
                const bool started = startStudyFromCurrentState();
                if (started) renderQuestion();
                else renderHome();
            } else if (action == UiAction::Home) {
                renderHome();
            }
            break;
    }
}
