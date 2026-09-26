#include "battery_service.h"

#include <algorithm>
#include <cmath>

#include "config.h"
#include "epd_driver.h"

namespace {

struct VoltagePoint {
    float volts;
    uint8_t percent;
};

// Aproximação de estado de carga para uma célula Li-Po em repouso.
// A leitura real varia com carga, temperatura, idade e corrente instantânea;
// por isso a HMI quantiza o resultado em passos de 5%.
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

}  // namespace

bool BatteryService::begin() {
    pinMode(Config::BATTERY_ADC_PIN, INPUT);
    analogReadResolution(12);
    analogSetPinAttenuation(Config::BATTERY_ADC_PIN, ADC_11db);

    initialized_ = true;
    const bool changed = sample(true);

    if (available_) {
        Serial.printf("[battery] %.2f V, %u%% (GPIO%d)\n",
                      voltage_,
                      static_cast<unsigned>(displayPercent_),
                      Config::BATTERY_ADC_PIN);
    } else {
        Serial.printf("[battery] sem bateria detectada em GPIO%d\n",
                      Config::BATTERY_ADC_PIN);
    }

    return changed || initialized_;
}

bool BatteryService::update() {
    if (!initialized_) return begin();
    return sample(false);
}

bool BatteryService::sample(bool force) {
    const uint32_t now = millis();
    if (!force && lastSampleMs_ != 0 &&
        now - lastSampleMs_ < Config::BATTERY_SAMPLE_INTERVAL_MS) {
        return false;
    }
    lastSampleMs_ = now;

    const bool oldAvailable = available_;
    const uint8_t oldPercent = displayPercent_;

    voltage_ = readVoltage();
    available_ = voltage_ >= Config::BATTERY_PRESENT_MIN_V &&
                 voltage_ <= Config::BATTERY_MAX_V + 0.15f;

    if (available_) {
        displayPercent_ = quantizePercent(estimatePercent(voltage_));
    } else {
        displayPercent_ = 0;
    }

    const bool changed = oldAvailable != available_ ||
                         (available_ && oldPercent != displayPercent_);

    if (changed && !force) {
        if (available_) {
            Serial.printf("[battery] %.2f V -> %u%%\n",
                          voltage_,
                          static_cast<unsigned>(displayPercent_));
        } else {
            Serial.println("[battery] bateria nao detectada");
        }
    }

    return changed;
}

float BatteryService::readVoltage() {
    // A LILYGO documenta que POWER_EN precisa estar ativo durante a leitura.
    // Hoje o Mnemos mantém esse rail ligado enquanto acordado; este caminho
    // também preserva funcionamento caso essa política mude futuramente.
    bool temporaryPower = false;
    if (!Config::KEEP_EPD_AUX_POWER_WHILE_AWAKE) {
        epd_poweron();
        temporaryPower = true;
    }

    delay(10);

    constexpr uint8_t SAMPLE_COUNT = 8;
    uint32_t sumMillivolts = 0;
    for (uint8_t i = 0; i < SAMPLE_COUNT; ++i) {
        sumMillivolts += analogReadMilliVolts(Config::BATTERY_ADC_PIN);
        delay(2);
    }

    if (temporaryPower) {
        epd_poweroff();
    }

    const float adcMillivolts =
        static_cast<float>(sumMillivolts) / static_cast<float>(SAMPLE_COUNT);

    return (adcMillivolts / 1000.0f) * Config::BATTERY_DIVIDER_RATIO;
}

uint8_t BatteryService::estimatePercent(float voltage) {
    if (voltage >= CURVE[0].volts) return CURVE[0].percent;

    constexpr size_t COUNT = sizeof(CURVE) / sizeof(CURVE[0]);
    if (voltage <= CURVE[COUNT - 1].volts) return CURVE[COUNT - 1].percent;

    for (size_t i = 1; i < COUNT; ++i) {
        if (voltage >= CURVE[i].volts) {
            const VoltagePoint& high = CURVE[i - 1];
            const VoltagePoint& low = CURVE[i];

            const float span = high.volts - low.volts;
            const float position = span > 0.0f
                ? (voltage - low.volts) / span
                : 0.0f;

            const float estimated =
                static_cast<float>(low.percent) +
                position * static_cast<float>(high.percent - low.percent);

            return static_cast<uint8_t>(
                std::max(0.0f, std::min(100.0f, std::round(estimated))));
        }
    }

    return 0;
}

uint8_t BatteryService::quantizePercent(uint8_t percent) {
    const uint8_t step = Config::BATTERY_DISPLAY_STEP_PERCENT;
    if (step <= 1) return percent;

    const uint16_t rounded =
        ((static_cast<uint16_t>(percent) + step / 2U) / step) * step;

    return static_cast<uint8_t>(std::min<uint16_t>(100U, rounded));
}
