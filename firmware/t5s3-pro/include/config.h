#pragma once

#include <Arduino.h>
#include "mnemos_contract_generated.h"

namespace Config {

constexpr long GMT_OFFSET_SECONDS = -3L * 3600L;
constexpr int DAYLIGHT_OFFSET_SECONDS = 0;
constexpr uint8_t DAY_CUTOFF_HOUR = MnemosContract::DEFAULT_DAY_CUTOFF_HOUR;

// Bancada: intervalos comprimidos para validar agenda/sessões sem esperar dias.
#if defined(MNEMOS_DEMO_INTERVALS)
constexpr bool DEMO_INTERVALS = true;
#else
constexpr bool DEMO_INTERVALS = false;
#endif

constexpr uint8_t SESSION_MAX_CARDS = 10;
constexpr uint8_t PRACTICE_CARD_LIMIT = 5;
constexpr uint8_t MAX_DEVICE_CARDS = 128;

// O array em RAM e catalogo leve. Conteudo textual completo fica no SD.
constexpr bool SD_FIRST_LIBRARY = true;
constexpr uint8_t MAX_CARD_OPTIONS = 4;
constexpr uint8_t MAX_CONSECUTIVE_SAME_DECK = 2;
constexpr uint8_t BASE_NEW_CARDS_PER_SESSION = 4;
constexpr uint8_t FORECAST_LOAD_THRESHOLD_7D = 20;
constexpr bool SEED_MANDARIN_TRAINING_DECK = false;

#if defined(MNEMOS_OTA_TEST_SOURCE)
constexpr char APP_VERSION[] = "0.8.1-preview.1-t5s3-pro";
constexpr uint32_t OTA_GENERATION = 70402U;
#else
constexpr char APP_VERSION[] = "0.8.1-preview.1-t5s3-pro";
constexpr uint32_t OTA_GENERATION = 70403U;
#endif
constexpr uint8_t DEVICE_PROTOCOL_VERSION = 4;
constexpr uint16_t LOCAL_LINK_TIMEOUT_SECONDS = 300;
constexpr char DEVICE_MODEL[] = "LILYGO-T5S3-PRO-H752-01";

constexpr uint32_t OTA_MAX_IMAGE_BYTES = 0x600000U;
constexpr uint8_t OTA_MIN_BATTERY_PERCENT = 20;
constexpr char OTA_LOCAL_MANIFEST_PATH[] = "/mnemos/update/manifest.json";
constexpr char OTA_APPLIED_MANIFEST_PATH[] = "/mnemos/update/manifest.applied.json";
constexpr char OTA_LOCAL_IMAGE_PATH[] = "/mnemos/update/firmware.bin";

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
constexpr uint32_t TOUCH_I2C_FREQUENCY = 100000U;
constexpr uint16_t TOUCH_POLL_MS = 12;
constexpr uint16_t TOUCH_IRQ_FALLBACK_MS = 80;
constexpr uint16_t TOUCH_ACTION_DEBOUNCE_MS = 400;
constexpr uint16_t TOUCH_RETRY_MS = 3000;

// Rede cooperativa: descoberta/conexão não bloqueiam a HMI.
constexpr uint32_t WIFI_CONNECT_TIMEOUT_MS = 12000U;
constexpr uint32_t WIFI_RECONNECT_TIMEOUT_MS = 8000U;
constexpr uint32_t WIFI_RECONNECT_INITIAL_BACKOFF_MS = 30000U;
constexpr uint32_t WIFI_RECONNECT_MAX_BACKOFF_MS = 300000U;

// SNTP é observado sem espera bloqueante.
constexpr uint32_t NTP_SYNC_TIMEOUT_MS = 10000U;

// CA HTTPS opcional no LittleFS.
constexpr char BACKEND_CA_FILE[] = "/backend_ca.pem";

// T5-4.7-S3: slot microSD/TF onboard via SPI.
constexpr int SD_MISO_PIN = 21;
constexpr int SD_MOSI_PIN = 13;
constexpr int SD_SCK_PIN = 14;
constexpr int SD_CS_PIN = 12;
constexpr int LORA_CS_PIN = 46;
constexpr uint32_t SD_FREQUENCY_HZ = 4000000U;


// T5-4.7-S3: monitoramento integrado da bateria Li-Po.
constexpr int BATTERY_ADC_PIN = 14;
constexpr float BATTERY_DIVIDER_RATIO = 2.0f;
constexpr float BATTERY_PRESENT_MIN_V = 2.80f;
constexpr float BATTERY_MAX_V = 4.20f;
constexpr uint32_t BATTERY_SAMPLE_INTERVAL_MS = 60000U;
constexpr uint8_t BATTERY_DISPLAY_STEP_PERCENT = 5;

constexpr uint8_t BATTERY_LOW_PERCENT = 15;
constexpr uint8_t BATTERY_CRITICAL_PERCENT = 5;

// Política de energia da T5 Touch atual.
#if defined(MNEMOS_BENCH_BUILD)
constexpr bool BENCH_BUILD = true;
#if defined(MNEMOS_OTA_TEST_SOURCE)
constexpr char BUILD_FLAVOR[] = "bench-ota-source";
constexpr bool OTA_AUTO_APPLY_ENABLED = true;
#elif defined(MNEMOS_OTA_TEST_TARGET)
constexpr char BUILD_FLAVOR[] = "bench-ota-target";
constexpr bool OTA_AUTO_APPLY_ENABLED = false;
#else
constexpr char BUILD_FLAVOR[] = "bench";
constexpr bool OTA_AUTO_APPLY_ENABLED = false;
#endif
constexpr bool LIGHT_SLEEP_ENABLED = false;
constexpr bool DEEP_SLEEP_ENABLED = false;
#else
constexpr bool BENCH_BUILD = false;
constexpr char BUILD_FLAVOR[] = "product";
constexpr bool LIGHT_SLEEP_ENABLED = true;
constexpr bool DEEP_SLEEP_ENABLED = true;
constexpr bool OTA_AUTO_APPLY_ENABLED = true;
#endif
constexpr uint32_t LIGHT_SLEEP_IDLE_MS =
    2U * 60U * 1000U;
constexpr uint32_t DEEP_SLEEP_IDLE_MS =
    20U * 60U * 1000U;
constexpr uint32_t LIGHT_SLEEP_MAX_TIMER_MS =
    20U * 60U * 1000U;
constexpr uint32_t DEEP_SLEEP_MAINTENANCE_SECONDS =
    6U * 60U * 60U;

// RTC PCF8563 e GT911 compartilham o barramento I2C nativo.
constexpr int SYSTEM_I2C_SDA = 39;
constexpr int SYSTEM_I2C_SCL = 40;
constexpr int TOUCH_IRQ_PIN = 3;

constexpr int TOUCH_RST_PIN = 9;

constexpr float TOUCH_X_SCALE = 0.98966699f;
constexpr float TOUCH_X_OFFSET = -2.9501555f;
constexpr float TOUCH_Y_SCALE = 0.97850569f;
constexpr float TOUCH_Y_OFFSET = 14.23129124f;

constexpr bool TOUCH_ENABLED = true;
constexpr int WAKE_BUTTON_PIN = 0;

// Touch e RTC permanecem ativos independentemente do rail auxiliar do EPD.

// T5S3 Pro H752-01: PT4103B23F backlight em GPIO11.

// T5S3 Pro H752-01 GNSS.
constexpr int GPS_RX_PIN = 44;
constexpr int GPS_TX_PIN = 43;

constexpr int BACKLIGHT_PIN = 11;
constexpr uint8_t BACKLIGHT_PWM_CHANNEL = 7;
constexpr uint16_t BACKLIGHT_PWM_FREQUENCY_HZ = 1000U;
constexpr uint8_t BACKLIGHT_DEFAULT_LEVEL = 0;

// Após N redraws normais, faz um full-clear GC16 antes
// de compor a próxima tela.
constexpr uint16_t EPD_AUTO_DEEP_CLEAN_INTERVAL = 5;

// Energia do terminal. Também vale no build bench.
constexpr uint32_t AUTO_POWER_OFF_IDLE_MS = 10U * 60U * 1000U;
constexpr uint32_t WIFI_RADIO_IDLE_OFF_MS = 3U * 60U * 1000U;
constexpr uint32_t BOOT_POWER_OFF_HOLD_MS = 1200U;

// BOOT físico (GPIO0): única fonte de wake do power-off.
// RST atua no EN e permanece reservado para reset físico.
constexpr int POWER_OFF_WAKE_PIN = 0;

constexpr bool KEEP_EPD_AUX_POWER_WHILE_AWAKE = false;

// HTTPS de produção: inserir CA raiz/chain. HTTP continua permitido no lab/LAN.
constexpr char BACKEND_ROOT_CA[] = "";

}  // namespace Config
