#pragma once

#include <Arduino.h>

enum class PowerDecision : uint8_t {
    None = 0,
    LightSleep,
    DeepSleep,
};

enum class PowerWakeReason : uint8_t {
    ColdBoot = 0,
    TouchOrButton,
    Timer,
    Other,
};

class PowerService {
public:
    void begin();
    void noteActivity();

    PowerDecision evaluate(
        bool sleepAllowed,
        bool criticalBattery) const;

    PowerWakeReason enterLightSleep();
    void enterDeepSleep();
    void enterPowerOff();

    uint64_t idleMs() const;

    PowerWakeReason bootWakeReason() const {
        return bootWakeReason_;
    }

private:
    uint64_t lastActivityUs_ = 0;

    PowerWakeReason bootWakeReason_ =
        PowerWakeReason::ColdBoot;

    static uint64_t nowUs();

    static PowerWakeReason mapWakeCause(
        int cause);
};
