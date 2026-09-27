#pragma once

#include <Arduino.h>
#include "mnemos_contract_generated.h"

namespace Config {

constexpr long GMT_OFFSET_SECONDS = -3L * 3600L;
constexpr int DAYLIGHT_OFFSET_SECONDS = 0;
constexpr uint8_t DAY_CUTOFF_HOUR = MnemosContract::DEFAULT_DAY_CUTOFF_HOUR;

// Bancada: intervalos comprimidos para validar agenda/sessões sem esperar dias.
constexpr bool DEMO_INTERVALS = true;

constexpr uint8_t SESSION_MAX_CARDS = 10;
constexpr uint8_t PRACTICE_CARD_LIMIT = 5;
constexpr uint8_t MAX_DEVICE_CARDS = 128;
constexpr uint8_t MAX_CARD_OPTIONS = 4;
constexpr uint8_t MAX_CONSECUTIVE_SAME_DECK = 2;
constexpr uint8_t BASE_NEW_CARDS_PER_SESSION = 4;
constexpr uint8_t FORECAST_LOAD_THRESHOLD_7D = 20;
constexpr bool SEED_MANDARIN_TRAINING_DECK = true;

constexpr char APP_VERSION[] = "0.6.0-preview.6.4.4.8-touch";
constexpr uint8_t DEVICE_PROTOCOL_VERSION = 4;
constexpr uint16_t LOCAL_LINK_TIMEOUT_SECONDS = 300;
constexpr char DEVICE_MODEL[] = "LILYGO-T5-4.7-S3-TOUCH";

constexpr float RETENTION_TARGET = 0.90f;
constexpr float MIN_DIFFICULTY = 1.0f;
constexpr float MAX_DIFFICULTY = 10.0f;
constexpr float MIN_STABILITY_DAYS = 0.05f;
constexpr float MAX_STABILITY_DAYS = 36500.0f;

constexpr float DSR_W1 = -0.50f;
constexpr float DSR_W2 = 0.20f;
constexpr float DSR_W3 = 1.30f;
constexpr float DSR_W4 = 1.00f;
constexpr float DSR_W5 = 0.20f;
constexpr float DSR_W6 = 0.60f;
constexpr float DSR_W7 = 0.90f;
constexpr float CRAM_GAIN_FACTOR = 0.30f;
constexpr float CRAM_RECONSOLIDATION_MAX_DAYS = 3.0f;

// T5-4.7-S3 Touch: GT911 integrado.
constexpr int DISPLAY_WIDTH = 960;
constexpr int DISPLAY_HEIGHT = 540;
constexpr uint8_t TOUCH_I2C_ADDRESS_PRIMARY = 0x5D;
constexpr uint8_t TOUCH_I2C_ADDRESS_ALT = 0x14;
constexpr uint32_t TOUCH_I2C_FREQUENCY = 100000;
constexpr uint16_t TOUCH_POLL_MS = 20;
constexpr uint16_t TOUCH_IRQ_FALLBACK_MS = 80;
constexpr uint16_t TOUCH_ACTION_DEBOUNCE_MS = 400;
constexpr uint16_t TOUCH_RETRY_MS = 3000;

// T5-4.7-S3: slot microSD/TF onboard via SPI.
constexpr int SD_MISO_PIN = 16;
constexpr int SD_MOSI_PIN = 15;
constexpr int SD_SCK_PIN = 11;
constexpr int SD_CS_PIN = 42;
constexpr uint32_t SD_FREQUENCY_HZ = 20000000U;


// T5-4.7-S3: monitoramento integrado da bateria Li-Po.
constexpr int BATTERY_ADC_PIN = 14;
constexpr float BATTERY_DIVIDER_RATIO = 2.0f;
constexpr float BATTERY_PRESENT_MIN_V = 2.80f;
constexpr float BATTERY_MAX_V = 4.20f;
constexpr uint32_t BATTERY_SAMPLE_INTERVAL_MS = 60000U;
constexpr uint8_t BATTERY_DISPLAY_STEP_PERCENT = 5;

// RTC PCF8563 e GT911 compartilham o barramento I2C nativo.
constexpr int SYSTEM_I2C_SDA = 18;
constexpr int SYSTEM_I2C_SCL = 17;
constexpr int TOUCH_IRQ_PIN = 47;
constexpr bool TOUCH_ENABLED = true;
constexpr int WAKE_BUTTON_PIN = 21;

// Touch e RTC permanecem ativos independentemente do rail auxiliar do EPD.
constexpr bool KEEP_EPD_AUX_POWER_WHILE_AWAKE = false;

// HTTPS de produção: inserir CA raiz/chain. HTTP continua permitido no lab/LAN.
constexpr char BACKEND_ROOT_CA[] = "";

}  // namespace Config
