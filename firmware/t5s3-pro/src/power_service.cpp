#include "power_service.h"

#include <algorithm>
#include <Wire.h>
#include <driver/gpio.h>
#include <driver/rtc_io.h>
#include <esp_sleep.h>
#include <esp_system.h>
#include <esp_timer.h>

#define XPOWERS_CHIP_BQ25896
#include <XPowersLib.h>

#include "config.h"

namespace {

XPowersPPM PPM;

void configureVendorPowerProfile() {
    PPM.setSysPowerDownVoltage(3300);
    PPM.setInputCurrentLimit(3250);
    PPM.disableCurrentLimitPin();
    PPM.setChargeTargetVoltage(4208);
    PPM.setPrechargeCurr(64);
    PPM.setChargerConstantCurr(1024);
    PPM.enableMeasure();
    PPM.enableCharge();

    // Sequencia do firmware factory H752-01.
    PPM.enableOTG();
    PPM.disableOTG();
}

const char* resetReasonName(
    esp_reset_reason_t reason) {

    switch (reason) {
        case ESP_RST_POWERON:
            return "POWERON";
        case ESP_RST_EXT:
            return "EXT";
        case ESP_RST_SW:
            return "SW";
        case ESP_RST_PANIC:
            return "PANIC";
        case ESP_RST_INT_WDT:
            return "INT_WDT";
        case ESP_RST_TASK_WDT:
            return "TASK_WDT";
        case ESP_RST_WDT:
            return "WDT";
        case ESP_RST_DEEPSLEEP:
            return "DEEPSLEEP";
        case ESP_RST_BROWNOUT:
            return "BROWNOUT";
        case ESP_RST_SDIO:
            return "SDIO";
        default:
            return "UNKNOWN";
    }
}

}  // namespace


uint64_t PowerService::nowUs() {
    return static_cast<uint64_t>(esp_timer_get_time());
}

PowerWakeReason PowerService::mapWakeCause(int cause) {
    switch (static_cast<esp_sleep_wakeup_cause_t>(cause)) {
        case ESP_SLEEP_WAKEUP_GPIO:
        case ESP_SLEEP_WAKEUP_EXT0:
        case ESP_SLEEP_WAKEUP_EXT1:
            return PowerWakeReason::TouchOrButton;

        case ESP_SLEEP_WAKEUP_TIMER:
            return PowerWakeReason::Timer;

        case ESP_SLEEP_WAKEUP_UNDEFINED:
            return PowerWakeReason::ColdBoot;

        default:
            return PowerWakeReason::Other;
    }
}

void PowerService::begin() {
    rtc_gpio_deinit(
        static_cast<gpio_num_t>(
            Config::WAKE_BUTTON_PIN));

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

    /*
     * Mesma inicializacao usada pelo firmware factory LilyGO.
     * Sem resetDefault() e sem escrita manual de REG09.
     */
    pmicAvailable_ =
        PPM.init(
            Wire,
            Config::SYSTEM_I2C_SDA,
            Config::SYSTEM_I2C_SCL,
            BQ25896_SLAVE_ADDRESS);

    if (pmicAvailable_) {
        configureVendorPowerProfile();

        Serial.printf(
            "[power] BQ25896 XPowers online "
            "vbus=%d pg=%d bus=%s iin=%u mA ichg=%u mA\n",
            PPM.isVbusIn() ? 1 : 0,
            PPM.isPowerGood() ? 1 : 0,
            PPM.getBusStatusString(),
            static_cast<unsigned>(
                PPM.getInputCurrentLimit()),
            static_cast<unsigned>(
                PPM.getChargerConstantCurr()));
    } else {
        Serial.println(
            "[power] BQ25896 XPowers indisponivel");
    }


    const esp_sleep_wakeup_cause_t rawWakeCause =
        esp_sleep_get_wakeup_cause();

    const uint64_t ext1WakeStatus =
        esp_sleep_get_ext1_wakeup_status();

    Serial.printf(
        "[power] boot reset=%s wake=%u raw=%d ext1=0x%llx "
        "light=%lu ms deep=%lu ms\n",
        resetReasonName(
            esp_reset_reason()),
        static_cast<unsigned>(
            bootWakeReason_),
        static_cast<int>(
            rawWakeCause),
        static_cast<unsigned long long>(
            ext1WakeStatus),
        static_cast<unsigned long>(
            Config::LIGHT_SLEEP_IDLE_MS),
        static_cast<unsigned long>(
            Config::DEEP_SLEEP_IDLE_MS));
}


void PowerService::noteActivity() {
    lastActivityUs_ = nowUs();
}

uint64_t PowerService::idleMs() const {
    const uint64_t current = nowUs();

    if (current < lastActivityUs_) {
        return 0;
    }

    return (current - lastActivityUs_) / 1000ULL;
}

bool PowerService::externalPowerPresent() {
    if (!pmicAvailable_) {
        return false;
    }

    return PPM.isVbusIn();
}


bool PowerService::canPowerOff() {
    return
        pmicAvailable_ &&
        !externalPowerPresent();
}

PowerDecision PowerService::evaluate(
    bool sleepAllowed,
    bool criticalBattery) const {

    if (!Config::LIGHT_SLEEP_ENABLED &&
        !Config::DEEP_SLEEP_ENABLED) {
        return PowerDecision::None;
    }

    if (criticalBattery) {
        return PowerDecision::DeepSleep;
    }

    if (!sleepAllowed) {
        return PowerDecision::None;
    }

    const uint64_t idle = idleMs();

    if (Config::DEEP_SLEEP_ENABLED &&
        idle >= Config::DEEP_SLEEP_IDLE_MS) {
        return PowerDecision::DeepSleep;
    }

    if (Config::LIGHT_SLEEP_ENABLED &&
        idle >= Config::LIGHT_SLEEP_IDLE_MS) {
        return PowerDecision::LightSleep;
    }

    return PowerDecision::None;
}

PowerWakeReason PowerService::enterLightSleep() {
    if (!Config::LIGHT_SLEEP_ENABLED) {
        return PowerWakeReason::Other;
    }

    gpio_wakeup_enable(
        static_cast<gpio_num_t>(
            Config::TOUCH_IRQ_PIN),
        GPIO_INTR_LOW_LEVEL);

    esp_sleep_enable_gpio_wakeup();

    const uint64_t idle = idleMs();

    const uint64_t sleepDeadlineMs =
        std::min<uint64_t>(
            Config::DEEP_SLEEP_IDLE_MS,
            Config::AUTO_POWER_OFF_IDLE_MS);

    uint64_t remainingMs =
        sleepDeadlineMs > idle
            ? sleepDeadlineMs - idle
            : 1000ULL;

    remainingMs =
        std::max<uint64_t>(
            1000ULL,
            std::min<uint64_t>(
                remainingMs,
                Config::LIGHT_SLEEP_MAX_TIMER_MS));

    esp_sleep_enable_timer_wakeup(
        remainingMs * 1000ULL);

    Serial.printf(
        "[power] light sleep, idle=%llu ms timer=%llu ms\n",
        static_cast<unsigned long long>(idle),
        static_cast<unsigned long long>(remainingMs));

    const esp_err_t result =
        esp_light_sleep_start();

    const PowerWakeReason reason =
        mapWakeCause(
            static_cast<int>(
                esp_sleep_get_wakeup_cause()));

    gpio_wakeup_disable(
        static_cast<gpio_num_t>(
            Config::TOUCH_IRQ_PIN));

    esp_sleep_disable_wakeup_source(
        ESP_SLEEP_WAKEUP_GPIO);

    esp_sleep_disable_wakeup_source(
        ESP_SLEEP_WAKEUP_TIMER);

    if (reason == PowerWakeReason::TouchOrButton) {
        noteActivity();
    }

    Serial.printf(
        "[power] light wake reason=%u result=%d\n",
        static_cast<unsigned>(reason),
        static_cast<int>(result));

    return reason;
}

void PowerService::enterDeepSleep() {
    if (!Config::DEEP_SLEEP_ENABLED) {
        return;
    }

    gpio_wakeup_disable(
        static_cast<gpio_num_t>(
            Config::TOUCH_IRQ_PIN));

    esp_sleep_disable_wakeup_source(
        ESP_SLEEP_WAKEUP_ALL);

    esp_sleep_enable_timer_wakeup(
        static_cast<uint64_t>(
            Config::DEEP_SLEEP_MAINTENANCE_SECONDS) *
        1000000ULL);

    Serial.printf(
        "[power] deep sleep interno; timer=%lu s\n",
        static_cast<unsigned long>(
            Config::DEEP_SLEEP_MAINTENANCE_SECONDS));

    Serial.flush();
    esp_deep_sleep_start();
}

void PowerService::enterPowerOff() {
    if (!pmicAvailable_) {
        while (true) {
            delay(1000);
        }
    }

    /*
     * Nao entrar em ship mode com VBUS presente.
     * O BQ25896 usa a entrada externa para manter/recuperar VSYS.
     */
    if (PPM.isVbusIn()) {
        while (true) {
            delay(1000);
        }
    }

    /*
     * Estado eletrico deterministico do frontlight antes
     * da remocao de VSYS.
     */
    ledcWrite(
        Config::BACKLIGHT_PWM_CHANNEL,
        0);

    ledcDetachPin(
        Config::BACKLIGHT_PIN);

    pinMode(
        Config::BACKLIGHT_PIN,
        OUTPUT);

    digitalWrite(
        Config::BACKLIGHT_PIN,
        LOW);

    delay(20);

    /*
     * BQ25896 REG09:
     *
     * bit 5 BATFET_DIS = 1 -> desliga BATFET / ship mode
     * bit 3 BATFET_DLY = 0 -> corte imediato
     *
     * Todos os demais bits sao preservados, inclusive
     * BATFET_RST_EN. Nao fazemos reset global do PMIC.
     *
     * Nao usar Serial.print/printf/flush neste caminho:
     * durante um desligamento real o USB ja pode estar ausente.
     */
    constexpr uint8_t REG09 = 0x09;
    constexpr uint8_t BATFET_DIS = 0x20;
    constexpr uint8_t BATFET_DLY = 0x08;

    for (
        uint8_t attempt = 0;
        attempt < 3;
        ++attempt
    ) {
        if (PPM.isVbusIn()) {
            break;
        }

        const int reg09 =
            PPM.readRegister(
                REG09);

        if (reg09 < 0) {
            delay(15);
            continue;
        }

        uint8_t target =
            static_cast<uint8_t>(
                reg09);

        target &=
            static_cast<uint8_t>(
                ~BATFET_DLY);

        target |=
            BATFET_DIS;

        const int result =
            PPM.writeRegister(
                REG09,
                target);

        if (result != 0) {
            delay(15);
            continue;
        }

        /*
         * Em bateria, o fluxo normal termina por perda de
         * VSYS antes do fim deste delay.
         */
        delay(120);

        /*
         * Se a CPU ainda estiver viva, confirme se o PMIC
         * manteve BATFET_DIS. Se o bit foi limpo, tente
         * novamente. Se permaneceu em 1, nao ha beneficio
         * em repetir a escrita: mantenha o sistema inerte.
         */
        const int verify =
            PPM.readRegister(
                REG09);

        if (
            verify >= 0
            && (
                verify
                & BATFET_DIS
            )
        ) {
            break;
        }

        delay(20);
    }

    /*
     * Falha segura. Nunca mascarar falha de hard-off com
     * ESP.restart() ou esp_deep_sleep_start().
     */
    while (true) {
        delay(1000);
    }
}
