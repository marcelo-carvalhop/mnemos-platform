#include <Arduino.h>

#include "backend_sync_service.h"
#include "battery_service.h"
#include "cardkb_input.h"
#include "cards.h"
#include "config.h"
#include "local_link_service.h"
#include "metrics_service.h"
#include "network_service.h"
#include "schedule_service.h"
#include "storage.h"
#include "study_engine.h"
#include "t5_display.h"
#include "time_service.h"
#include "ui_actions.h"

enum class AppScreen : uint8_t {
    Home,
    Menu,
    Agenda,
    Sync,
    Connection,
    LocalLink,
    Question,
    SelfAssessment,
    ObjectiveFeedback,
    Effort,
    Summary,
};

BatteryService batteryService;
Storage storage;
NetworkService networkService;
TimeService clockService;
T5Display display;
CardKbInput keyboard;
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
uint32_t lastKeyboardRetryMs = 0;

void rebuildEngine() {
    if (engine != nullptr) {
        delete engine;
        engine = nullptr;
    }
    engine = new StudyEngine(
        cards,
        states,
        cardCount,
        storage,
        clockService);
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

void advanceAfterCommit(bool finished) {
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

UiAction mapNavigationKey(uint8_t key) {
    const char lower = (key >= 'A' && key <= 'Z') ? static_cast<char>(key - 'A' + 'a') : static_cast<char>(key);
    const bool enter = CardKbInput::isEnter(key);
    const bool back = CardKbInput::isBackspace(key);

    switch (screen) {
        case AppScreen::Home:
            if (enter || lower == ' ') return UiAction::PrimaryStudy;
            if (lower == 'm') return UiAction::OpenMenu;
            break;
        case AppScreen::Menu:
            if (key == '1') return UiAction::OpenSync;
            if (key == '2') return UiAction::OpenAgenda;
            if (key == '3') return UiAction::OpenConnection;
            if (back) return UiAction::Back;
            break;
        case AppScreen::Agenda:
            if (back || enter) return UiAction::Back;
            break;
        case AppScreen::Sync:
            if (key == '1') return UiAction::SyncBackend;
            if (key == '2') return UiAction::SyncPhone;
            if (back) return UiAction::Back;
            break;
        case AppScreen::Connection:
            if (key == '1') return UiAction::ConfigureNetwork;
            if (key == '2') return UiAction::ToggleWifi;
            if (back) return UiAction::Back;
            break;
        case AppScreen::LocalLink:
            if (back) return UiAction::CancelLocalLink;
            break;
        case AppScreen::Question:
            if (engine != nullptr) {
                if (engine->currentIsObjective()) {
                    if (key == '1') return UiAction::Choice0;
                    if (key == '2') return UiAction::Choice1;
                    if (key == '3') return UiAction::Choice2;
                    if (key == '4') return UiAction::Choice3;
                } else if (enter || lower == ' ') {
                    return UiAction::AnswerReady;
                }
            }
            break;
        case AppScreen::SelfAssessment:
            if (key == '1') return UiAction::SelfIncorrect;
            if (key == '2') return UiAction::SelfCorrect;
            break;
        case AppScreen::ObjectiveFeedback:
            if (enter || lower == ' ') return UiAction::Continue;
            break;
        case AppScreen::Effort:
            if (key == '1') return UiAction::EffortDifficult;
            if (key == '2') return UiAction::EffortNormal;
            if (key == '3') return UiAction::EffortEasy;
            break;
        case AppScreen::Summary:
            if (key == '1') return UiAction::StudyAgain;
            if (enter || back) return UiAction::Home;
            break;
    }
    return UiAction::None;
}

void processAction(UiAction action) {
    if (action == UiAction::None) return;

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
                backendSync.syncNow();

                if (
                    backendSync.consumeLibraryUpdated()
                ) {
                    rebuildEngine();
                }

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

        case AppScreen::Question: {
            if (engine == nullptr) break;

            if (!engine->currentIsObjective() && action == UiAction::AnswerReady) {
                // O instante de revelar encerra o tempo de recuperação.
                engine->markResponseReady();
                renderSelfAssessment();
                break;
            }

            int option = -1;
            if (action == UiAction::Choice0) option = 0;
            else if (action == UiAction::Choice1) option = 1;
            else if (action == UiAction::Choice2) option = 2;
            else if (action == UiAction::Choice3) option = 3;

            if (option >= 0 && engine->selectOption(static_cast<uint8_t>(option))) {
                pendingOutcome = engine->evaluateAutomatic();
                renderObjectiveFeedback();
            }
            break;
        }

        case AppScreen::SelfAssessment:
            if (action == UiAction::SelfIncorrect) {
                advanceAfterCommit(engine->commitCurrent(Outcome::Incorrect, Effort::None));
            } else if (action == UiAction::SelfCorrect) {
                pendingOutcome = Outcome::Correct;
                renderEffort();
            }
            break;

        case AppScreen::ObjectiveFeedback:
            if (action == UiAction::Continue) {
                if (pendingOutcome == Outcome::Correct) renderEffort();
                else advanceAfterCommit(engine->commitCurrent(Outcome::Incorrect, Effort::None));
            }
            break;

        case AppScreen::Effort: {
            Effort effort = Effort::None;
            if (action == UiAction::EffortDifficult) effort = Effort::Difficult;
            else if (action == UiAction::EffortNormal) effort = Effort::Normal;
            else if (action == UiAction::EffortEasy) effort = Effort::Easy;
            if (effort != Effort::None) {
                advanceAfterCommit(engine->commitCurrent(Outcome::Correct, effort));
            }
            break;
        }

        case AppScreen::Summary:
            if (action == UiAction::StudyAgain) {
                if (startStudyFromCurrentState()) renderQuestion();
                else renderHome();
            } else if (action == UiAction::Home) {
                renderHome();
            }
            break;
    }
}

void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.printf("\n[app] Mnemos T5 v%s iniciando\n", Config::APP_VERSION);

    if (!display.begin()) {
        Serial.println("[app] display indisponivel; sistema interrompido");
        while (true) delay(1000);
    }

    batteryService.begin();
    display.setBatteryStatus(batteryService.available(), batteryService.percent());

    display.showBoot("Inicializando T5 + CardKB...");

    keyboard.begin();
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
    if (keyboard.online()) renderHome();
    else display.showKeyboardMissing();
}

void loop() {
    // Atualiza apenas o estado em RAM. O e-paper mostrará o novo valor
    // na próxima mudança natural de tela, evitando refresh por telemetria.
    if (batteryService.update()) {
        display.setBatteryStatus(batteryService.available(), batteryService.percent());
    }

    localLink.loop();
    networkService.loop();

    if (!keyboard.online() && millis() - lastKeyboardRetryMs > 1200U) {
        lastKeyboardRetryMs = millis();
        if (keyboard.probe()) renderHome();
    }

    if (localLink.consumeLibraryUpdated()) {
        rebuildEngine();
        Serial.printf("[app] biblioteca atualizada por Wi-Fi local: %u cartoes\n",
                      static_cast<unsigned>(cardCount));
    }

    const bool nonStudyScreen = screen == AppScreen::Home || screen == AppScreen::Menu ||
                                screen == AppScreen::Agenda || screen == AppScreen::Sync ||
                                screen == AppScreen::Connection;
    if (nonStudyScreen && !localLink.active()) {
        backendSync.loop();
        if (backendSync.consumeLibraryUpdated()) {
            rebuildEngine();
            if (screen == AppScreen::Home) renderHome();
            else if (screen == AppScreen::Sync) renderSync();
        }
    }

    if (screen == AppScreen::LocalLink && !localLink.active()) {
        rebuildEngine();
        renderMenu();
    }


    const uint8_t key = keyboard.pollKey();
    if (key == 0) {
        delay(2);
        return;
    }

    Serial.printf("[cardkb] key=0x%02X", key);
    if (CardKbInput::printable(key)) Serial.printf(" '%c'", key);
    Serial.println();

    processAction(mapNavigationKey(key));
}
