#pragma once

#include <Arduino.h>

class BatteryService {
public:
    bool begin();

    // Mede apenas quando o intervalo configurado venceu.
    // Retorna true quando o estado destinado à HMI mudou.
    bool update();

    bool available() const { return available_; }
    uint8_t percent() const { return displayPercent_; }
    float voltage() const { return voltage_; }

private:
    bool sample(bool force);
    float readVoltage();
    static uint8_t estimatePercent(float voltage);
    static uint8_t quantizePercent(uint8_t percent);

    bool initialized_ = false;
    bool available_ = false;
    uint8_t displayPercent_ = 0;
    float voltage_ = 0.0f;
    uint32_t lastSampleMs_ = 0;
};
