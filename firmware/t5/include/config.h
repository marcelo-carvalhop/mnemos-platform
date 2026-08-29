#pragma once

#include <Arduino.h>
#include "mnemos_contract_generated.h"

namespace Config {

constexpr long GMT_OFFSET_SECONDS = -3L * 3600L;
constexpr int DAYLIGHT_OFFSET_SECONDS = 0;
constexpr uint8_t DAY_CUTOFF_HOUR = MnemosContract::DEFAULT_DAY_CUTOFF_HOUR;

// Bancada: intervalos comprimidos para validar agenda/sessões sem esperar dias.

constexpr uint8_t SESSION_MAX_CARDS = 10;
constexpr uint8_t PRACTICE_CARD_LIMIT = 5;
constexpr uint8_t MAX_DEVICE_CARDS = 48;
constexpr uint8_t MAX_CARD_OPTIONS = MnemosContract::MULTIPLE_CHOICE_OPTIONS;
constexpr uint8_t MAX_CONSECUTIVE_SAME_DECK = 2;
constexpr uint8_t BASE_NEW_CARDS_PER_SESSION = 4;
constexpr uint8_t FORECAST_LOAD_THRESHOLD_7D = 20;

constexpr char APP_VERSION[] = "0.6.0-preview.2";
constexpr uint8_t DEVICE_PROTOCOL_VERSION = 4;
constexpr uint16_t LOCAL_LINK_TIMEOUT_SECONDS = 300;
constexpr char DEVICE_MODEL[] = "LILYGO-T5-4.7-S3-CARDKB";

constexpr float RETENTION_TARGET = MnemosContract::DESIRED_RETENTION;
constexpr float MIN_DIFFICULTY = 1.0f;
constexpr float MAX_DIFFICULTY = 10.0f;

// CardKB v1.1: I2C dedicado, sem conflitar com o barramento do RTC/touch.
constexpr int CARDKB_SDA = 16;
constexpr int CARDKB_SCL = 15;
constexpr uint8_t CARDKB_I2C_ADDRESS = 0x5F;
constexpr uint32_t CARDKB_I2C_FREQUENCY = 100000;
constexpr uint16_t CARDKB_POLL_MS = 8;
constexpr size_t MAX_TYPED_RESPONSE_CHARS = 320;
constexpr uint16_t EINK_TEXT_REFRESH_IDLE_MS = 260;

// T5-4.7-S3: monitoramento integrado da bateria Li-Po.
constexpr int BATTERY_ADC_PIN = 14;
constexpr float BATTERY_DIVIDER_RATIO = 2.0f;
constexpr float BATTERY_PRESENT_MIN_V = 2.80f;
constexpr float BATTERY_MAX_V = 4.20f;
constexpr uint32_t BATTERY_SAMPLE_INTERVAL_MS = 60000U;
constexpr uint8_t BATTERY_DISPLAY_STEP_PERCENT = 5;

// T5-4.7-S3: barramento nativo reservado ao RTC e ao futuro GT911 touch.
constexpr int SYSTEM_I2C_SDA = 18;
constexpr int SYSTEM_I2C_SCL = 17;
constexpr int FUTURE_TOUCH_IRQ = 47;
constexpr bool TOUCH_ENABLED = false;
constexpr int WAKE_BUTTON_PIN = 21;

// Se o CardKB estiver alimentado pelo conector auxiliar controlado junto com o
// EPD, o power rail precisa permanecer ligado enquanto o terminal estiver ativo.
constexpr bool KEEP_EPD_AUX_POWER_WHILE_AWAKE = true;

// HTTPS de produção: inserir CA raiz/chain. HTTP continua permitido no lab/LAN.
constexpr char BACKEND_ROOT_CA[] = "";

}  // namespace Config
