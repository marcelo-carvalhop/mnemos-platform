#pragma once

// BQ27220 simulado para os testes do BatteryService no host.
// Expõe apenas a API somente-leitura usada pelo serviço.

#include "Arduino.h"
#include "../../lib/BQ27220/bq27220_def.h"

typedef enum {
    Bq27220OperationStatusSecSealed = 0b11,
    Bq27220OperationStatusSecUnsealed = 0b10,
    Bq27220OperationStatusSecFull = 0b01,
} Bq27220OperationStatusSec;

typedef union OperationStatus {
    struct __reg {
        bool CALMD : 1;
        uint8_t SEC : 2;
        bool EDV2 : 1;
        bool VDQ : 1;
        bool INITCOMP : 1;
        bool SMTH : 1;
        bool BTPINT : 1;
        uint8_t RSVD1 : 2;
        bool CFGUPDATE : 1;
        uint8_t RSVD0 : 5;
    } reg;
    uint16_t full;
} BQ27220OperationStatus;

namespace test_support {

struct GaugeSim {
    bool online = true;
    uint16_t deviceNumber = BQ27220_DEVICE_ID;
    // SEALED, INITCOMP=1, CFGUPDATE=0: estado lido na unidade H752-01.
    uint16_t operationStatus = 0x00A6;
    uint16_t millivolts = 3850;
    int16_t currentMa = -150;
    uint16_t soc = 22;
    uint16_t designMah = 3000;
    uint16_t fullMah = 3000;
    uint16_t remainingMah = 650;
};

inline GaugeSim gauge;

}  // namespace test_support

class BQ27220 {
public:
    uint16_t getDeviceNumber() {
        return test_support::gauge.online
            ? test_support::gauge.deviceNumber
            : 0xFFFFU;
    }

    bool getOperationStatus(BQ27220OperationStatus* status) {
        if (!test_support::gauge.online) {
            return false;
        }

        status->full = test_support::gauge.operationStatus;
        return true;
    }

    bool readRegU16(uint8_t reg, uint16_t& value) {
        const test_support::GaugeSim& gauge = test_support::gauge;

        if (!gauge.online) {
            return false;
        }

        switch (reg) {
            case CommandVoltage:
                value = gauge.millivolts;
                return true;

            case CommandCurrent:
                value = static_cast<uint16_t>(gauge.currentMa);
                return true;

            case CommandStateOfCharge:
                value = gauge.soc;
                return true;

            case CommandDesignCapacity:
                value = gauge.designMah;
                return true;

            case CommandFullChargeCapacity:
                value = gauge.fullMah;
                return true;

            case CommandRemainingCapacity:
                value = gauge.remainingMah;
                return true;

            default:
                return false;
        }
    }
};
