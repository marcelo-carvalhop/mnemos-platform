#pragma once

#include <Arduino.h>
#include <TouchDrv.hpp>

struct MnemosTouchPoint {
    int16_t rawX = 0;
    int16_t rawY = 0;
    int16_t x = 0;
    int16_t y = 0;
};

class TouchInput {
public:
    bool begin();
    bool poll(MnemosTouchPoint& point);

    void setPortrait(bool portrait) {
        portrait_ = portrait;
    }

    bool online() const { return online_; }
    bool irqEnabled() const { return irqEnabled_; }
    uint8_t address() const { return address_; }

private:
    uint8_t detectAddress();

    TouchDrvGT911 touch_;
    bool online_ = false;
    bool pressed_ = false;
    bool irqEnabled_ = false;
    uint8_t address_ = 0;
    uint32_t lastPollMs_ = 0;
    bool portrait_ = false;
};
