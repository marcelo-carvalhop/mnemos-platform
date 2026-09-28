#pragma once

#include "config.h"

namespace BoardConfig {

constexpr int RTC_TOUCH_SDA = Config::SYSTEM_I2C_SDA;
constexpr int RTC_TOUCH_SCL = Config::SYSTEM_I2C_SCL;
constexpr int TOUCH_IRQ = Config::TOUCH_IRQ_PIN;
constexpr int WAKE_BUTTON = Config::WAKE_BUTTON_PIN;

constexpr bool HAS_TOUCH = Config::TOUCH_ENABLED;
constexpr bool USE_SD = true;

}  // namespace BoardConfig
