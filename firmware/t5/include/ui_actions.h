#pragma once

#include <Arduino.h>

enum class UiAction : uint8_t {
    None = 0,
    PrimaryStudy,
    OpenMenu,
    OpenSync,
    OpenAgenda,
    OpenConnection,
    SyncBackend,
    SyncPhone,
    ConfigureNetwork,
    ToggleWifi,
    Back,
    CancelLocalLink,
    AnswerReady,
    Choice0,
    Choice1,
    Choice2,
    Choice3,
    ConfidenceLow,
    ConfidenceMedium,
    ConfidenceHigh,
    SelfIncorrect,
    SelfCorrect,
    EffortDifficult,
    EffortNormal,
    EffortEasy,
    Continue,
    StudyAgain,
    Home,
};
