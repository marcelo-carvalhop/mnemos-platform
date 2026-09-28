#include "touch_input.h"

#include <Wire.h>

#include "config.h"

namespace {

volatile bool gTouchIrqPending = true;
bool gTouchInterruptAttached = false;

void IRAM_ATTR onGt911Interrupt() {
    gTouchIrqPending = true;
}

}  // namespace


uint8_t TouchInput::detectAddress() {
    uint8_t detected = 0;

    Wire.beginTransmission(
        Config::TOUCH_I2C_ADDRESS_ALT);

    if (Wire.endTransmission() == 0) {
        detected =
            Config::TOUCH_I2C_ADDRESS_ALT;
    }

    Wire.beginTransmission(
        Config::TOUCH_I2C_ADDRESS_PRIMARY);

    if (Wire.endTransmission() == 0) {
        detected =
            Config::TOUCH_I2C_ADDRESS_PRIMARY;
    }

    return detected;
}


bool TouchInput::begin() {
    online_ = false;
    pressed_ = false;
    irqEnabled_ = false;
    address_ = 0;
    gTouchIrqPending = true;

    if (gTouchInterruptAttached) {
        detachInterrupt(
            digitalPinToInterrupt(
                Config::TOUCH_IRQ_PIN));

        gTouchInterruptAttached =
            false;
    }

    // Mantem o comportamento de inicializacao ja validado
    // nessa placa antes de devolver GPIO47 ao GT911.
    pinMode(
        Config::TOUCH_IRQ_PIN,
        OUTPUT);

    digitalWrite(
        Config::TOUCH_IRQ_PIN,
        HIGH);

    delay(10);

    Wire.setClock(
        Config::TOUCH_I2C_FREQUENCY);

    address_ =
        detectAddress();

    if (address_ == 0) {
        Serial.printf(
            "[touch] GT911 nao encontrado em "
            "0x%02X/0x%02X "
            "(SDA=%d SCL=%d IRQ=%d)\n",
            Config::TOUCH_I2C_ADDRESS_PRIMARY,
            Config::TOUCH_I2C_ADDRESS_ALT,
            Config::SYSTEM_I2C_SDA,
            Config::SYSTEM_I2C_SCL,
            Config::TOUCH_IRQ_PIN);

        return false;
    }

    // A SensorLib 0.4.1 exige setPins() antes do begin()
    // quando o pino de interrupcao esta conectado.
    touch_.setPins(
        -1,
        Config::TOUCH_IRQ_PIN);

    if (!touch_.begin(
            Wire,
            address_,
            Config::SYSTEM_I2C_SDA,
            Config::SYSTEM_I2C_SCL)) {

        Serial.printf(
            "[touch] falha ao iniciar "
            "GT911 em 0x%02X\n",
            address_);

        address_ = 0;
        return false;
    }

    touch_.setMaxCoordinates(
        Config::DISPLAY_WIDTH,
        Config::DISPLAY_HEIGHT);

    touch_.setSwapXY(true);
    touch_.setMirrorXY(false, true);

    pinMode(
        Config::TOUCH_IRQ_PIN,
        INPUT);

    const bool irqModeOk =
        touch_.setInterruptMode(
            TouchDrvGT911::FALLING_EDGE);

    if (irqModeOk) {
        attachInterrupt(
            digitalPinToInterrupt(
                Config::TOUCH_IRQ_PIN),
            onGt911Interrupt,
            FALLING);

        gTouchInterruptAttached =
            true;

        irqEnabled_ = true;
    }

    online_ = true;

    Serial.printf(
        "[touch] GT911 online "
        "addr=0x%02X SDA=%d SCL=%d IRQ=%d "
        "mode=%s fallback=%ums\n",
        address_,
        Config::SYSTEM_I2C_SDA,
        Config::SYSTEM_I2C_SCL,
        Config::TOUCH_IRQ_PIN,
        irqEnabled_
            ? "FALLING_IRQ"
            : "POLLING",
        static_cast<unsigned>(
            Config::TOUCH_IRQ_FALLBACK_MS));

    return true;
}


bool TouchInput::poll(
    MnemosTouchPoint& point) {

    if (!online_) {
        return false;
    }

    const uint32_t now =
        millis();

    if (irqEnabled_) {
        const bool fallbackDue =
            now - lastPollMs_ >=
            Config::TOUCH_IRQ_FALLBACK_MS;

        if (
            !gTouchIrqPending &&
            !fallbackDue
        ) {
            return false;
        }

        gTouchIrqPending = false;
    } else {
        if (
            now - lastPollMs_ <
            Config::TOUCH_POLL_MS
        ) {
            return false;
        }
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

    const int16_t x =
        raw.x;

    const int16_t y =
        raw.y;

    point.rawX = x;
    point.rawY = y;

    if (portrait_) {
        point.x = y;
        point.y =
            Config::DISPLAY_WIDTH -
            x -
            1;
    } else {
        point.x = x;
        point.y = y;
    }

    return true;
}
