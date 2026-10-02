#include "battery_service.h"

#include <Wire.h>

#include <algorithm>
#include <cmath>

namespace {

struct VoltagePoint {
    float volts;
    uint8_t percent;
};

constexpr VoltagePoint CURVE[] = {
    {4.20f, 100},
    {4.10f,  90},
    {4.00f,  80},
    {3.90f,  65},
    {3.80f,  50},
    {3.70f,  30},
    {3.60f,  15},
    {3.50f,   5},
    {3.40f,   0},
};

constexpr uint8_t BQ27220_ADDRESS =
    0x55;

}  // namespace


bool BatteryService::probe() const {
    Wire.beginTransmission(
        BQ27220_ADDRESS);

    return
        Wire.endTransmission() ==
        0;
}



bool BatteryService::begin() {
    initialized_ = true;

    if (!probe()) {
        available_ = false;
        charging_ = false;

        Serial.println(
            "[battery] BQ27220 0x55 indisponivel");

        return false;
    }

    /*
     * O firmware oficial LilyGO do H752-01 chama bq27220.init()
     * no bring-up. Fazemos o mesmo para validar perfil,
     * INITCOMP e Data Memory antes de confiar no SOC.
     *
     * Se a inicialização completa falhar, ainda tentamos
     * leituras diretas para não perder um gauge funcional
     * por uma falha transitória de configuração.
     */
    const bool gaugeReady =
        gauge_.init();

    Serial.printf(
        "[battery] BQ27220 init=%d\n",
        gaugeReady ? 1 : 0);

    /*
     * No boot, o primeiro acesso pode retornar 0xFFFF.
     * Fazemos até três leituras curtas antes de declarar
     * o gauge indisponível.
     */
    for (
        uint8_t attempt = 0;
        attempt < 3;
        ++attempt
    ) {
        sample(true);

        if (available_) {
            break;
        }

        delay(25);
    }

    if (available_) {
        Serial.printf(
            "[battery] BQ27220 %.3f V %u%% charging=%d\n",
            voltage_,
            static_cast<unsigned>(
                displayPercent_),
            charging_ ? 1 : 0);
    }

    return available_;
}



bool BatteryService::update() {
    if (!initialized_) {
        return begin();
    }

    return sample(false);
}



bool BatteryService::sample(
    bool force) {

    const uint32_t now =
        millis();

    if (
        !force &&
        lastSampleMs_ != 0 &&
        now - lastSampleMs_ <
            Config::BATTERY_SAMPLE_INTERVAL_MS
    ) {
        return false;
    }

    lastSampleMs_ = now;

    const bool oldAvailable =
        available_;

    const bool oldCharging =
        charging_;

    const uint8_t oldPercent =
        displayPercent_;

    const auto registerInvalid =
        [&]() -> bool {

        if (
            invalidReadCount_ <
            255
        ) {
            ++invalidReadCount_;
        }

        /*
         * Uma leitura ruim isolada não apaga o último estado
         * válido da HMI. Só após três leituras consecutivas.
         */
        if (
            invalidReadCount_ <
            3
        ) {
            return false;
        }

        available_ = false;
        charging_ = false;
        displayPercent_ = 0;
        voltage_ = 0.0f;

        return
            oldAvailable != available_ ||
            oldCharging != charging_ ||
            oldPercent != displayPercent_;
    };

    if (!probe()) {
        const bool changed =
            registerInvalid();

        Serial.printf(
            "[battery] I2C falhou streak=%u\n",
            static_cast<unsigned>(
                invalidReadCount_));

        return changed;
    }

    const uint16_t millivolts =
        gauge_.getVoltage();

    const uint16_t rawSoc =
        gauge_.getStateOfCharge();

    const bool valid =
        millivolts != 0xFFFFU &&
        rawSoc != 0xFFFFU &&
        rawSoc <= 100U &&
        millivolts >= 2800U &&
        millivolts <= 4400U;

    if (!valid) {
        const bool changed =
            registerInvalid();

        Serial.printf(
            "[battery] leitura invalida "
            "voltage=%u mV soc=%u streak=%u\n",
            static_cast<unsigned>(
                millivolts),
            static_cast<unsigned>(
                rawSoc),
            static_cast<unsigned>(
                invalidReadCount_));

        return changed;
    }

    invalidReadCount_ = 0;

    voltage_ =
        static_cast<float>(
            millivolts) /
        1000.0f;

    available_ = true;

    displayPercent_ =
        quantizePercent(
            static_cast<uint8_t>(
                rawSoc));

    charging_ =
        gauge_.getIsCharging();

    const bool changed =
        oldAvailable != available_ ||
        oldCharging != charging_ ||
        oldPercent != displayPercent_;

    const int16_t currentMa =
        gauge_.getCurrent();

    const uint16_t remainingMah =
        gauge_.getRemainingCapacity();

    const uint16_t fullMah =
        gauge_.getFullChargeCapacity();

    Serial.printf(
        "[battery] %.3f V rawSOC=%u display=%u%% "
        "current=%d mA remaining=%u mAh full=%u mAh "
        "charging=%d changed=%d\n",
        voltage_,
        static_cast<unsigned>(
            rawSoc),
        static_cast<unsigned>(
            displayPercent_),
        static_cast<int>(
            currentMa),
        static_cast<unsigned>(
            remainingMah),
        static_cast<unsigned>(
            fullMah),
        charging_ ? 1 : 0,
        changed ? 1 : 0);

    return changed;
}



uint8_t BatteryService::estimatePercent(
    float voltage) {

    if (
        voltage >=
        CURVE[0].volts
    ) {
        return
            CURVE[0].percent;
    }

    constexpr size_t COUNT =
        sizeof(CURVE) /
        sizeof(CURVE[0]);

    if (
        voltage <=
        CURVE[COUNT - 1].volts
    ) {
        return
            CURVE[COUNT - 1].percent;
    }

    for (
        size_t i = 1;
        i < COUNT;
        ++i
    ) {
        if (
            voltage >=
            CURVE[i].volts
        ) {
            const VoltagePoint& high =
                CURVE[i - 1];

            const VoltagePoint& low =
                CURVE[i];

            const float span =
                high.volts -
                low.volts;

            const float position =
                span > 0.0f
                    ? (
                          voltage -
                          low.volts
                      ) /
                          span
                    : 0.0f;

            const float estimated =
                static_cast<float>(
                    low.percent) +
                position *
                    static_cast<float>(
                        high.percent -
                        low.percent);

            return
                static_cast<uint8_t>(
                    std::max(
                        0.0f,
                        std::min(
                            100.0f,
                            std::round(
                                estimated))));
        }
    }

    return 0;
}


uint8_t BatteryService::quantizePercent(
    uint8_t percent) {

    const uint8_t step =
        Config::
            BATTERY_DISPLAY_STEP_PERCENT;

    if (step <= 1) {
        return percent;
    }

    const uint16_t rounded =
        (
            (
                static_cast<uint16_t>(
                    percent) +
                step / 2U
            ) /
            step
        ) *
        step;

    return
        static_cast<uint8_t>(
            std::min<uint16_t>(
                100U,
                rounded));
}
