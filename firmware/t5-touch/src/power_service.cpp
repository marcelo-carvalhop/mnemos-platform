#include "power_service.h"

#include <algorithm>
#include <driver/gpio.h>
#include <esp_sleep.h>
#include <esp_timer.h>

#include "config.h"

uint64_t PowerService::nowUs() {
    return
        static_cast<uint64_t>(
            esp_timer_get_time());
}


PowerWakeReason PowerService::mapWakeCause(
    int cause) {

    switch (
        static_cast<
            esp_sleep_wakeup_cause_t>(
            cause)
    ) {
        case ESP_SLEEP_WAKEUP_GPIO:
        case ESP_SLEEP_WAKEUP_EXT0:
        case ESP_SLEEP_WAKEUP_EXT1:
            return
                PowerWakeReason::
                    TouchOrButton;

        case ESP_SLEEP_WAKEUP_TIMER:
            return
                PowerWakeReason::Timer;

        case ESP_SLEEP_WAKEUP_UNDEFINED:
            return
                PowerWakeReason::ColdBoot;

        default:
            return
                PowerWakeReason::Other;
    }
}


void PowerService::begin() {
    pinMode(
        Config::WAKE_BUTTON_PIN,
        INPUT_PULLUP);

    pinMode(
        Config::TOUCH_IRQ_PIN,
        INPUT_PULLUP);

    bootWakeReason_ =
        mapWakeCause(
            static_cast<int>(
                esp_sleep_get_wakeup_cause()));

    lastActivityUs_ =
        nowUs();

    Serial.printf(
        "[power] boot wake=%u light=%lu ms deep=%lu ms\n",
        static_cast<unsigned>(
            bootWakeReason_),
        static_cast<unsigned long>(
            Config::
                LIGHT_SLEEP_IDLE_MS),
        static_cast<unsigned long>(
            Config::
                DEEP_SLEEP_IDLE_MS));
}


void PowerService::noteActivity() {
    lastActivityUs_ =
        nowUs();
}


uint64_t PowerService::idleMs() const {
    const uint64_t current =
        nowUs();

    if (
        current <
        lastActivityUs_
    ) {
        return 0;
    }

    return
        (
            current -
            lastActivityUs_
        ) /
        1000ULL;
}


PowerDecision PowerService::evaluate(
    bool sleepAllowed,
    bool criticalBattery) const {

    if (
        !Config::LIGHT_SLEEP_ENABLED &&
        !Config::DEEP_SLEEP_ENABLED
    ) {
        return
            PowerDecision::None;
    }

    if (criticalBattery) {
        return
            PowerDecision::DeepSleep;
    }

    if (!sleepAllowed) {
        return
            PowerDecision::None;
    }

    const uint64_t idle =
        idleMs();

    if (
        Config::DEEP_SLEEP_ENABLED &&
        idle >=
            Config::
                DEEP_SLEEP_IDLE_MS
    ) {
        return
            PowerDecision::DeepSleep;
    }

    if (
        Config::LIGHT_SLEEP_ENABLED &&
        idle >=
            Config::
                LIGHT_SLEEP_IDLE_MS
    ) {
        return
            PowerDecision::LightSleep;
    }

    return
        PowerDecision::None;
}


PowerWakeReason PowerService::enterLightSleep() {
    if (!Config::LIGHT_SLEEP_ENABLED) {
        return
            PowerWakeReason::Other;
    }

    gpio_wakeup_enable(
        static_cast<gpio_num_t>(
            Config::TOUCH_IRQ_PIN),
        GPIO_INTR_LOW_LEVEL);

    gpio_wakeup_enable(
        static_cast<gpio_num_t>(
            Config::WAKE_BUTTON_PIN),
        GPIO_INTR_LOW_LEVEL);

    esp_sleep_enable_gpio_wakeup();

    const uint64_t idle =
        idleMs();

    uint64_t remainingMs =
        Config::DEEP_SLEEP_IDLE_MS >
                idle
            ? Config::
                  DEEP_SLEEP_IDLE_MS -
                  idle
            : 1000ULL;

    remainingMs =
        std::max<uint64_t>(
            1000ULL,
            std::min<uint64_t>(
                remainingMs,
                Config::
                    LIGHT_SLEEP_MAX_TIMER_MS));

    esp_sleep_enable_timer_wakeup(
        remainingMs *
        1000ULL);

    Serial.printf(
        "[power] light sleep, idle=%llu ms timer=%llu ms\n",
        static_cast<unsigned long long>(
            idle),
        static_cast<unsigned long long>(
            remainingMs));

    const esp_err_t result =
        esp_light_sleep_start();

    const PowerWakeReason reason =
        mapWakeCause(
            static_cast<int>(
                esp_sleep_get_wakeup_cause()));

    gpio_wakeup_disable(
        static_cast<gpio_num_t>(
            Config::TOUCH_IRQ_PIN));

    gpio_wakeup_disable(
        static_cast<gpio_num_t>(
            Config::WAKE_BUTTON_PIN));

    esp_sleep_disable_wakeup_source(
        ESP_SLEEP_WAKEUP_GPIO);

    esp_sleep_disable_wakeup_source(
        ESP_SLEEP_WAKEUP_TIMER);

    if (
        reason ==
        PowerWakeReason::
            TouchOrButton
    ) {
        noteActivity();
    }

    Serial.printf(
        "[power] light wake reason=%u result=%d\n",
        static_cast<unsigned>(
            reason),
        static_cast<int>(
            result));

    return reason;
}


void PowerService::enterDeepSleep() {
    if (!Config::DEEP_SLEEP_ENABLED) {
        return;
    }

    gpio_wakeup_disable(
        static_cast<gpio_num_t>(
            Config::TOUCH_IRQ_PIN));

    gpio_wakeup_disable(
        static_cast<gpio_num_t>(
            Config::WAKE_BUTTON_PIN));

    esp_sleep_disable_wakeup_source(
        ESP_SLEEP_WAKEUP_ALL);

    pinMode(
        Config::WAKE_BUTTON_PIN,
        INPUT_PULLUP);

    // GPIO21 é RTC IO no ESP32-S3. O touch IRQ desta placa está no
    // GPIO47 e não é fonte EXT0/EXT1 válida sem modificação física.
    esp_sleep_enable_ext0_wakeup(
        static_cast<gpio_num_t>(
            Config::WAKE_BUTTON_PIN),
        0);

    esp_sleep_enable_timer_wakeup(
        static_cast<uint64_t>(
            Config::
                DEEP_SLEEP_MAINTENANCE_SECONDS) *
        1000000ULL);

    Serial.printf(
        "[power] deep sleep; wake=GPIO%d baixo ou timer=%lu s\n",
        Config::WAKE_BUTTON_PIN,
        static_cast<unsigned long>(
            Config::
                DEEP_SLEEP_MAINTENANCE_SECONDS));

    Serial.flush();

    esp_deep_sleep_start();
}
