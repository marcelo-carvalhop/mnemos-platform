#pragma once

#include <Arduino.h>

#include "bq27220.h"
#include "config.h"

class BatteryService {
public:
    bool begin();

    // Mede apenas quando o intervalo configurado venceu.
    // Retorna true quando o estado destinado à HMI mudou.
    bool update();

    bool available() const { return available_; }
    uint8_t percent() const { return displayPercent_; }
    float voltage() const { return voltage_; }
    bool charging() const { return charging_; }

    bool low() const {
        return
            available_ &&
            displayPercent_ <=
                Config::BATTERY_LOW_PERCENT;
    }

    bool critical() const {
        return
            available_ &&
            displayPercent_ <=
                Config::BATTERY_CRITICAL_PERCENT;
    }

private:
    bool probe() const;
    bool sample(bool force);

    static uint8_t estimatePercent(float voltage);
    static uint8_t quantizePercent(uint8_t percent);

    BQ27220 gauge_;

    bool initialized_ = false;
    bool available_ = false;
    bool charging_ = false;
    uint8_t invalidReadCount_ = 0;

    uint8_t displayPercent_ = 0;

    float voltage_ = 0.0f;

    uint32_t lastSampleMs_ = 0;
};
