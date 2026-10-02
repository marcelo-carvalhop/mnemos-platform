#include "backlight_service.h"

#include "config.h"

namespace {

constexpr uint8_t DUTY[4] = {
    0,
    50,
    100,
    230,
};

}  // namespace


bool BacklightService::begin() {
    preferences_.begin(
        "mnemos-bl",
        false);

    level_ =
        preferences_.getUChar(
            "level",
            Config::
                BACKLIGHT_DEFAULT_LEVEL);

    if (
        level_ >=
        LEVEL_COUNT
    ) {
        level_ =
            Config::
                BACKLIGHT_DEFAULT_LEVEL;
    }

    ledcSetup(
        Config::BACKLIGHT_PWM_CHANNEL,
        Config::BACKLIGHT_PWM_FREQUENCY_HZ,
        8);

    ledcAttachPin(
        Config::BACKLIGHT_PIN,
        Config::BACKLIGHT_PWM_CHANNEL);

    initialized_ = true;
    apply();

    Serial.printf(
        "[backlight] level=%u duty=%u\n",
        static_cast<unsigned>(level_),
        static_cast<unsigned>(duty()));

    return true;
}


void BacklightService::apply() {
    if (!initialized_) {
        return;
    }

    ledcWrite(
        Config::BACKLIGHT_PWM_CHANNEL,
        duty());
}


void BacklightService::setLevel(
    uint8_t level) {

    level_ =
        level %
        LEVEL_COUNT;

    preferences_.putUChar(
        "level",
        level_);

    apply();

    Serial.printf(
        "[backlight] level=%u duty=%u\n",
        static_cast<unsigned>(level_),
        static_cast<unsigned>(duty()));
}


void BacklightService::cycle() {
    setLevel(
        static_cast<uint8_t>(
            (
                level_ +
                1
            ) %
            LEVEL_COUNT));
}


void BacklightService::suspend() {
    if (!initialized_) {
        return;
    }

    ledcWrite(
        Config::BACKLIGHT_PWM_CHANNEL,
        0);
}


void BacklightService::resume() {
    apply();
}


uint8_t BacklightService::duty() const {
    return
        DUTY[
            level_ <
                    LEVEL_COUNT
                ? level_
                : 0];
}


const char* BacklightService::label() const {
    switch (level_) {
        case 0:
            return "Desligada";
        case 1:
            return "Baixa";
        case 2:
            return "Média";
        case 3:
            return "Alta";
        default:
            return "Desligada";
    }
}
