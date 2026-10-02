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

    // Mantido para compatibilidade com o restante da aplicação.
    // O T5S3 Pro opera exclusivamente em retrato.
    void setPortrait(bool) {}

    bool online() const { return online_; }
    bool irqEnabled() const { return false; }
    uint8_t address() const { return address_; }

private:
    uint8_t detectAddress();

    void transform(
        int16_t rawX,
        int16_t rawY,
        int16_t& logicalX,
        int16_t& logicalY) const;

    TouchDrvGT911 touch_;

    bool online_ = false;
    bool pressed_ = false;

    uint8_t address_ = 0;

    uint32_t lastPollMs_ = 0;
};
