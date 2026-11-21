#pragma once

#include "Arduino.h"

namespace test_support {

// false simula um dispositivo que não responde com ACK.
inline bool i2cAck = true;

}  // namespace test_support

struct TwoWire {
    void beginTransmission(uint8_t) {}

    uint8_t endTransmission(bool = true) {
        return test_support::i2cAck ? 0 : 2;
    }
};

inline TwoWire Wire;
