#pragma once

#include <Arduino.h>

namespace Config {

constexpr long GMT_OFFSET_SECONDS = -3L * 3600L;
constexpr int DAYLIGHT_OFFSET_SECONDS = 0;

// true comprime os intervalos para facilitar testes de bancada.
constexpr bool DEMO_INTERVALS = true;

constexpr uint8_t SESSION_MAX_CARDS = 10;
constexpr uint8_t PRACTICE_CARD_LIMIT = 5;
constexpr uint8_t MAX_DEVICE_CARDS = 48;
constexpr uint16_t TOUCH_PRESSURE_MIN = 200;
constexpr uint32_t TOUCH_DEBOUNCE_MS = 180;

constexpr char APP_VERSION[] = "0.4.0";
constexpr uint8_t DEVICE_PROTOCOL_VERSION = 3;
constexpr uint16_t PAIRING_TIMEOUT_SECONDS = 300;
constexpr char DEVICE_MODEL[] = "ESP32-2432S028";

// Produção HTTPS: grave aqui a CA raiz/chain que valida o backend. O firmware
// recusa HTTPS sem uma CA em vez de usar setInsecure(). HTTP permanece
// disponível para laboratório/LAN durante o protótipo.
constexpr char BACKEND_ROOT_CA[] = "";

}  // namespace Config
