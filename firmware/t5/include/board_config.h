#pragma once

#include "config.h"

namespace BoardConfig {

constexpr int CARDKB_SDA = Config::CARDKB_SDA;
constexpr int CARDKB_SCL = Config::CARDKB_SCL;
constexpr uint8_t CARDKB_ADDRESS = Config::CARDKB_I2C_ADDRESS;

constexpr int RTC_TOUCH_SDA = Config::SYSTEM_I2C_SDA;
constexpr int RTC_TOUCH_SCL = Config::SYSTEM_I2C_SCL;
constexpr int TOUCH_IRQ = Config::FUTURE_TOUCH_IRQ;
constexpr int WAKE_BUTTON = Config::WAKE_BUTTON_PIN;

constexpr bool HAS_TOUCH = Config::TOUCH_ENABLED;
constexpr bool USE_SD = false; // GPIO16/15 são reutilizados pelo CardKB.

}  // namespace BoardConfig
