#pragma once

#include <Arduino.h>

namespace Config {

constexpr long GMT_OFFSET_SECONDS = -3L * 3600L;
constexpr int DAYLIGHT_OFFSET_SECONDS = 0;

// true comprime intervalos para testes de bancada. Deve ser false em release de campo.
constexpr bool DEMO_INTERVALS = true;

constexpr uint8_t SESSION_MAX_CARDS = 10;
constexpr uint8_t PRACTICE_CARD_LIMIT = 5;
constexpr uint8_t MAX_DEVICE_CARDS = 48;
constexpr uint8_t MAX_CARD_OPTIONS = 4;
constexpr uint8_t MAX_CONSECUTIVE_SAME_DECK = 2;
constexpr uint8_t BASE_NEW_CARDS_PER_SESSION = 4;
constexpr uint8_t FORECAST_LOAD_THRESHOLD_7D = 20;

constexpr uint16_t TOUCH_PRESSURE_MIN = 200;
constexpr uint32_t TOUCH_DEBOUNCE_MS = 180;

constexpr char APP_VERSION[] = "0.5.0-preview.3";
constexpr uint8_t DEVICE_PROTOCOL_VERSION = 4;
constexpr uint16_t LOCAL_LINK_TIMEOUT_SECONDS = 300;
constexpr char DEVICE_MODEL[] = "ESP32-2432S028";

constexpr float RETENTION_TARGET = 0.90f;
constexpr float MIN_DIFFICULTY = 1.0f;
constexpr float MAX_DIFFICULTY = 10.0f;
constexpr float MIN_STABILITY_DAYS = 0.05f;
constexpr float MAX_STABILITY_DAYS = 36500.0f;

// Coeficientes determinísticos provisórios do modelo D/S/R. A estrutura segue
// a especificação metodológica; os valores são parâmetros de MVP e permanecem
// centralizados para calibração posterior sem alterar o contrato de dados.
constexpr float DSR_W1 = -0.50f;
constexpr float DSR_W2 = 0.20f;
constexpr float DSR_W3 = 1.30f;
constexpr float DSR_W4 = 1.00f;
constexpr float DSR_W5 = 0.20f;
constexpr float DSR_W6 = 0.60f;
constexpr float DSR_W7 = 0.90f;
constexpr float CRAM_GAIN_FACTOR = 0.30f;
constexpr float CRAM_RECONSOLIDATION_MAX_DAYS = 3.0f;

// Produção HTTPS: grave aqui a CA raiz/chain que valida o backend. O firmware
// recusa HTTPS sem uma CA em vez de usar setInsecure(). HTTP permanece
// disponível para laboratório/LAN durante o protótipo.
constexpr char BACKEND_ROOT_CA[] = "";

}  // namespace Config
