#include "touch_input.h"

#include <Wire.h>
#include <cmath>

#include "config.h"
#include "hmi_layout.h"

namespace {

int16_t clampCoordinate(
    int value,
    int minimum,
    int maximum) {

    if (value < minimum) {
        return static_cast<int16_t>(minimum);
    }

    if (value > maximum) {
        return static_cast<int16_t>(maximum);
    }

    return static_cast<int16_t>(value);
}

}  // namespace


uint8_t TouchInput::detectAddress() {
    const uint8_t candidates[] = {
        Config::TOUCH_I2C_ADDRESS_PRIMARY,
        Config::TOUCH_I2C_ADDRESS_ALT
    };

    for (const uint8_t address : candidates) {
        Wire.beginTransmission(address);

        if (Wire.endTransmission() == 0) {
            return address;
        }
    }

    return 0;
}



void TouchInput::transform(
    int16_t rawX,
    int16_t rawY,
    int16_t& logicalX,
    int16_t& logicalY) const {

    /*
     * H752-01 em retrato físico:
     *
     * rawX -> eixo curto (X)
     * rawY -> eixo longo (Y)
     *
     * Não há swap XY aqui.
     */
    const int mappedX =
        static_cast<int>(
            lroundf(
                static_cast<float>(rawX) *
                    Config::TOUCH_X_SCALE +
                Config::TOUCH_X_OFFSET));

    const int mappedY =
        static_cast<int>(
            lroundf(
                static_cast<float>(rawY) *
                    Config::TOUCH_Y_SCALE +
                Config::TOUCH_Y_OFFSET));

    logicalX =
        clampCoordinate(
            mappedX,
            0,
            HmiLayout::PORTRAIT_WIDTH - 1);

    logicalY =
        clampCoordinate(
            mappedY,
            0,
            HmiLayout::PORTRAIT_HEIGHT - 1);
}



bool TouchInput::begin() {
    online_ = false;
    pressed_ = false;
    address_ = 0;
    lastPollMs_ = 0;

    Wire.setClock(
        Config::TOUCH_I2C_FREQUENCY);

    address_ =
        detectAddress();

    if (address_ == 0) {
        Serial.printf(
            "[touch] GT911 nao encontrado "
            "0x%02X/0x%02X SDA=%d SCL=%d\n",
            Config::TOUCH_I2C_ADDRESS_PRIMARY,
            Config::TOUCH_I2C_ADDRESS_ALT,
            Config::SYSTEM_I2C_SDA,
            Config::SYSTEM_I2C_SCL);

        return false;
    }

    /*
     * O H752-01 possui reset e IRQ ligados:
     * RST=GPIO9, IRQ=GPIO3.
     */
    touch_.setPins(
        Config::TOUCH_RST_PIN,
        Config::TOUCH_IRQ_PIN);

    if (
        !touch_.begin(
            Wire,
            address_,
            Config::SYSTEM_I2C_SDA,
            Config::SYSTEM_I2C_SCL)
    ) {
        Serial.printf(
            "[touch] falha ao iniciar GT911 "
            "addr=0x%02X\n",
            address_);

        address_ = 0;
        return false;
    }

    /*
     * Não instalamos attachInterrupt().
     * epdiy board v7 já instala o serviço global de ISR.
     *
     * O GT911 fica em LOW_LEVEL_QUERY e é consultado
     * a cada TOUCH_POLL_MS. Para uma HMI baseada em tap,
     * isso é mais simples e elimina a disputa de ISR.
     */
    touch_.setInterruptMode(
        TouchDrvGT911::LOW_LEVEL_QUERY);

    pinMode(
        Config::TOUCH_IRQ_PIN,
        INPUT);

    online_ = true;

    Serial.printf(
        "[touch] GT911 online addr=0x%02X "
        "RST=%d IRQ=%d polling=%ums portrait-fixed\n",
        address_,
        Config::TOUCH_RST_PIN,
        Config::TOUCH_IRQ_PIN,
        static_cast<unsigned>(
            Config::TOUCH_POLL_MS));

    return true;
}


bool TouchInput::poll(
    MnemosTouchPoint& point) {

    if (!online_) {
        return false;
    }

    const uint32_t now =
        millis();

    if (
        now - lastPollMs_ <
        Config::TOUCH_POLL_MS
    ) {
        return false;
    }

    lastPollMs_ = now;

    const auto& points =
        touch_.getTouchPoints();

    if (!points.hasPoints()) {
        pressed_ = false;
        return false;
    }

    if (pressed_) {
        return false;
    }

    pressed_ = true;

    const auto& raw =
        points.getPoint(0);

    point.rawX = raw.x;
    point.rawY = raw.y;

    transform(
        point.rawX,
        point.rawY,
        point.x,
        point.y);

    return true;
}
