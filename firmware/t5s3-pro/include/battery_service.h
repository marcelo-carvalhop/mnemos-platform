#pragma once

#include <Arduino.h>

#include "bq27220.h"
#include "config.h"

enum class BatteryGaugeTrust : uint8_t {
    // Sem resposta em 0x55 ou Device Number diferente de 0x0220.
    Absent = 0,
    // Gauge responde, mas o perfil não corresponde à célula de 1500 mAh:
    // SOC e capacidades não são usados; a carga é estimada pela tensão.
    ProfileUntrusted,
    // Perfil coerente com a célula oficial: o SOC do gauge é usado.
    ProfileTrusted,
};

class BatteryService {
public:
    using ExternalPowerProbe = bool (*)();

    // O BQ27220 é tratado como sensor read-only: este serviço nunca
    // envia chaves de segurança, RESET, CFGUPDATE nem escreve Data Memory.
    bool begin(ExternalPowerProbe externalPower);

    // Mede apenas quando o intervalo configurado venceu.
    // Retorna true quando o estado destinado à HMI mudou.
    bool update();

    bool available() const { return available_; }
    uint8_t percent() const { return displayPercent_; }
    float voltage() const { return voltage_; }
    bool charging() const { return charging_; }
    BatteryGaugeTrust trust() const { return trust_; }

    bool low() const {
        return
            available_ &&
            displayPercent_ <=
                Config::BATTERY_LOW_PERCENT;
    }

    // Só sem alimentação externa, e nunca derivado do SOC
    // de um perfil não validado.
    bool critical() const {
        return critical_;
    }

private:
    bool probe() const;
    bool identify();
    void evaluateProfile();
    bool sample(bool force);
    bool externalPowerPresent() const;

    void trackEstimate(
        uint8_t estimate,
        bool rising);

    void updateCritical(
        bool supplied,
        bool gaugeSoc,
        float compensatedVoltage);

    static uint8_t estimatePercent(float voltage);
    static uint8_t quantizePercent(uint8_t percent);

    BQ27220 gauge_;
    ExternalPowerProbe externalPower_ = nullptr;

    BatteryGaugeTrust trust_ = BatteryGaugeTrust::Absent;
    bool profileChecked_ = false;

    bool initialized_ = false;
    bool available_ = false;
    bool charging_ = false;
    bool critical_ = false;
    uint8_t invalidReadCount_ = 0;
    uint8_t criticalSamples_ = 0;

    bool estimateValid_ = false;
    float filteredVoltage_ = 0.0f;
    uint8_t trackedPercent_ = 0;
    uint8_t displayPercent_ = 0;

    float voltage_ = 0.0f;

    uint32_t lastSampleMs_ = 0;
};
