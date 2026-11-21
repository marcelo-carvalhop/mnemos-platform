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

const char* trustName(
    BatteryGaugeTrust trust) {

    switch (trust) {
        case BatteryGaugeTrust::ProfileTrusted:
            return "TRUSTED";

        case BatteryGaugeTrust::ProfileUntrusted:
            return "UNTRUSTED";

        default:
            return "ABSENT";
    }
}

const char* securityName(
    uint8_t sec) {

    switch (sec) {
        case Bq27220OperationStatusSecSealed:
            return "SEALED";

        case Bq27220OperationStatusSecUnsealed:
            return "UNSEALED";

        case Bq27220OperationStatusSecFull:
            return "FULL";

        default:
            return "UNKNOWN";
    }
}

}  // namespace


bool BatteryService::probe() const {
    Wire.beginTransmission(
        BQ27220_ADDRESS);

    return
        Wire.endTransmission() ==
        0;
}


bool BatteryService::externalPowerPresent() const {
    return
        externalPower_ != nullptr &&
        externalPower_();
}



bool BatteryService::begin(
    ExternalPowerProbe externalPower) {

    externalPower_ = externalPower;
    initialized_ = true;

    trust_ = BatteryGaugeTrust::Absent;
    profileChecked_ = false;
    available_ = false;
    charging_ = false;
    critical_ = false;
    invalidReadCount_ = 0;
    criticalSamples_ = 0;
    estimateValid_ = false;
    trackedPercent_ = 0;
    displayPercent_ = 0;
    voltage_ = 0.0f;
    lastSampleMs_ = 0;

    if (!identify()) {
        return false;
    }

    /*
     * No boot, o primeiro acesso pode falhar.
     * Fazemos até três leituras curtas antes de declarar
     * o gauge indisponível.
     */
    for (
        uint8_t attempt = 0;
        attempt < 3 &&
        !available_;
        ++attempt
    ) {
        if (attempt > 0) {
            delay(25);
        }

        sample(true);
    }

    return available_;
}



bool BatteryService::identify() {
    trust_ = BatteryGaugeTrust::Absent;
    profileChecked_ = false;

    if (!probe()) {
        Serial.println(
            "[battery] BQ27220 0x55 indisponivel");
        return false;
    }

    // DEVICE_NUMBER é um subcomando só de leitura, aceito em SEALED.
    const uint16_t deviceNumber =
        gauge_.getDeviceNumber();

    if (
        deviceNumber !=
        BQ27220_DEVICE_ID
    ) {
        Serial.printf(
            "[battery] identity=FAIL "
            "device=0x%04X expected=0x%04X\n",
            static_cast<unsigned>(
                deviceNumber),
            static_cast<unsigned>(
                BQ27220_DEVICE_ID));

        return false;
    }

    Serial.printf(
        "[battery] identity=OK device=0x%04X\n",
        static_cast<unsigned>(
            deviceNumber));

    trust_ =
        BatteryGaugeTrust::ProfileUntrusted;

    return true;
}



void BatteryService::evaluateProfile() {
    BQ27220OperationStatus status = {};

    uint16_t designMah = 0;
    uint16_t fullMah = 0;
    uint16_t remainingMah = 0;

    const bool readOk =
        gauge_.getOperationStatus(
            &status) &&
        gauge_.readRegU16(
            CommandDesignCapacity,
            designMah) &&
        gauge_.readRegU16(
            CommandFullChargeCapacity,
            fullMah) &&
        gauge_.readRegU16(
            CommandRemainingCapacity,
            remainingMah);

    const char* reason = nullptr;

    if (!readOk) {
        reason = "read-failed";
    } else if (status.reg.CFGUPDATE) {
        reason = "cfgupdate";
    } else if (!status.reg.INITCOMP) {
        reason = "initcomp-pending";
    } else {
        /*
         * Este firmware nunca escreve a Data Memory: com
         * INITCOMP=1 o veredito sobre as capacidades vale
         * até o próximo boot.
         */
        profileChecked_ = true;

        if (
            designMah !=
            Config::BATTERY_DESIGN_CAPACITY_MAH
        ) {
            reason = "design-capacity";
        } else if (
            fullMah > designMah ||
            fullMah < designMah / 2U
        ) {
            reason = "full-charge-capacity";
        } else if (
            remainingMah > fullMah
        ) {
            reason = "remaining-capacity";
        }
    }

    trust_ =
        reason == nullptr
            ? BatteryGaugeTrust::ProfileTrusted
            : BatteryGaugeTrust::ProfileUntrusted;

    Serial.printf(
        "[battery] security=%s SEC=%u INITCOMP=%u CFGUPDATE=%u "
        "design=%u mAh full=%u mAh remaining=%u mAh "
        "expected=%u mAh profile=%s reason=%s percent=%s "
        "data-memory=UNTOUCHED\n",
        securityName(
            status.reg.SEC),
        static_cast<unsigned>(
            status.reg.SEC),
        status.reg.INITCOMP ? 1U : 0U,
        status.reg.CFGUPDATE ? 1U : 0U,
        static_cast<unsigned>(
            designMah),
        static_cast<unsigned>(
            fullMah),
        static_cast<unsigned>(
            remainingMah),
        static_cast<unsigned>(
            Config::BATTERY_DESIGN_CAPACITY_MAH),
        trustName(
            trust_),
        reason != nullptr
            ? reason
            : "ok",
        trust_ ==
                BatteryGaugeTrust::ProfileTrusted
            ? "gauge"
            : "voltage");
}



bool BatteryService::update() {
    if (!initialized_) {
        return begin(
            externalPower_);
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

    const auto changed =
        [&]() -> bool {
        return
            oldAvailable != available_ ||
            oldCharging != charging_ ||
            oldPercent != displayPercent_;
    };

    if (
        trust_ ==
            BatteryGaugeTrust::Absent &&
        !identify()
    ) {
        return false;
    }

    if (!profileChecked_) {
        evaluateProfile();
    }

    uint16_t millivolts = 0;

    const bool voltageOk =
        gauge_.readRegU16(
            CommandVoltage,
            millivolts) &&
        millivolts >=
            Config::BATTERY_VALID_MIN_MV &&
        millivolts <=
            Config::BATTERY_VALID_MAX_MV;

    if (!voltageOk) {
        if (
            invalidReadCount_ <
            255
        ) {
            ++invalidReadCount_;
        }

        Serial.printf(
            "[battery] leitura invalida "
            "voltage=%u mV streak=%u\n",
            static_cast<unsigned>(
                millivolts),
            static_cast<unsigned>(
                invalidReadCount_));

        /*
         * Uma leitura ruim isolada não apaga o último estado
         * válido da HMI. Após três leituras consecutivas o
         * gauge volta a ser identificado do zero.
         */
        if (
            invalidReadCount_ <
            3
        ) {
            return false;
        }

        trust_ = BatteryGaugeTrust::Absent;
        profileChecked_ = false;
        available_ = false;
        charging_ = false;
        critical_ = false;
        criticalSamples_ = 0;
        estimateValid_ = false;
        displayPercent_ = 0;
        voltage_ = 0.0f;

        return changed();
    }

    invalidReadCount_ = 0;
    available_ = true;

    voltage_ =
        static_cast<float>(
            millivolts) /
        1000.0f;

    uint16_t rawCurrent = 0;

    const bool currentOk =
        gauge_.readRegU16(
            CommandCurrent,
            rawCurrent);

    // Convenção TI: Current() > 0 carregando, < 0 descarregando.
    const int16_t currentMa =
        currentOk
            ? static_cast<int16_t>(
                  rawCurrent)
            : 0;

    const float irDrop =
        std::max(
            -Config::BATTERY_MAX_IR_COMPENSATION_V,
            std::min(
                Config::BATTERY_MAX_IR_COMPENSATION_V,
                static_cast<float>(
                    currentMa) /
                    1000.0f *
                    Config::BATTERY_INTERNAL_RESISTANCE_OHM));

    const float compensatedVoltage =
        voltage_ -
        irDrop;

    filteredVoltage_ =
        estimateValid_
            ? filteredVoltage_ +
                  Config::BATTERY_VOLTAGE_FILTER_ALPHA *
                      (
                          compensatedVoltage -
                          filteredVoltage_
                      )
            : compensatedVoltage;

    const uint8_t estimate =
        estimatePercent(
            filteredVoltage_);

    uint16_t rawSoc = 0xFFFFU;

    const bool socOk =
        gauge_.readRegU16(
            CommandStateOfCharge,
            rawSoc) &&
        rawSoc <= 100U;

    const bool gaugeSoc =
        trust_ ==
            BatteryGaugeTrust::ProfileTrusted &&
        socOk;

    const bool externalPower =
        externalPowerPresent();

    charging_ =
        currentOk &&
        currentMa >=
            Config::BATTERY_CHARGING_MIN_MA;

    const bool supplied =
        externalPower ||
        charging_;

    if (gaugeSoc) {
        trackedPercent_ =
            static_cast<uint8_t>(
                rawSoc);
    } else if (!estimateValid_) {
        trackedPercent_ =
            estimate;
    } else {
        trackEstimate(
            estimate,
            supplied);
    }

    estimateValid_ = true;

    displayPercent_ =
        quantizePercent(
            trackedPercent_);

    updateCritical(
        supplied,
        gaugeSoc,
        compensatedVoltage);

    Serial.printf(
        "[battery] trust=%s source=%s %.3f V %d mA "
        "comp=%.3f V filt=%.3f V estimate=%u%% gauge-soc=%d "
        "display=%u%% vbus=%d charging=%d critical=%d changed=%d\n",
        trustName(
            trust_),
        gaugeSoc
            ? "gauge"
            : "voltage",
        voltage_,
        static_cast<int>(
            currentMa),
        compensatedVoltage,
        filteredVoltage_,
        static_cast<unsigned>(
            estimate),
        socOk
            ? static_cast<int>(
                  rawSoc)
            : -1,
        static_cast<unsigned>(
            displayPercent_),
        externalPower ? 1 : 0,
        charging_ ? 1 : 0,
        critical_ ? 1 : 0,
        changed() ? 1 : 0);

    return changed();
}



void BatteryService::trackEstimate(
    uint8_t estimate,
    bool charging) {

    /*
     * Em bateria a carga estimada só cai e, carregando, só sobe.
     * O sentido oposto exige diferença acima da histerese, para que
     * a recuperação de tensão após um pico de consumo (Wi-Fi,
     * refresh do EPD) não faça o indicador oscilar.
     */
    const uint8_t band =
        Config::
            BATTERY_ESTIMATE_HYSTERESIS_PERCENT;

    const bool follow =
        charging
            ? estimate >= trackedPercent_ ||
                  trackedPercent_ - estimate >= band
            : estimate <= trackedPercent_ ||
                  estimate - trackedPercent_ >= band;

    if (follow) {
        trackedPercent_ =
            estimate;
    }
}



void BatteryService::updateCritical(
    bool supplied,
    bool gaugeSoc,
    float compensatedVoltage) {

    /*
     * Usa a tensão compensada da amostra, não a filtrada: o filtro
     * atrasaria o corte justamente no joelho final da descarga.
     * Picos isolados são rejeitados pelas amostras consecutivas.
     */
    const bool belowLimit =
        !supplied &&
        (
            compensatedVoltage <=
                Config::BATTERY_CRITICAL_V ||
            (
                gaugeSoc &&
                trackedPercent_ <=
                    Config::BATTERY_CRITICAL_PERCENT
            )
        );

    if (!belowLimit) {
        criticalSamples_ = 0;
    } else if (
        criticalSamples_ <
        255
    ) {
        ++criticalSamples_;
    }

    critical_ =
        criticalSamples_ >=
        Config::BATTERY_CRITICAL_SAMPLES;
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
