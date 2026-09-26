#include "time_service.h"

#include <WiFi.h>
#include <Wire.h>
#include <time.h>
#include <sys/time.h>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <algorithm>

#include "config.h"

namespace {
int monthFromName(const char* month) {
    static const char* MONTHS[] = {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    };
    for (int i = 0; i < 12; ++i) {
        if (std::strncmp(month, MONTHS[i], 3) == 0) return i;
    }
    return 0;
}
}

uint32_t TimeService::compileEpoch() const {
    char month[4] = {0};
    int day = 1, year = 2026, hour = 0, minute = 0, second = 0;
    std::sscanf(__DATE__, "%3s %d %d", month, &day, &year);
    std::sscanf(__TIME__, "%d:%d:%d", &hour, &minute, &second);

    tm value{};
    value.tm_year = year - 1900;
    value.tm_mon = monthFromName(month);
    value.tm_mday = day;
    value.tm_hour = hour;
    value.tm_min = minute;
    value.tm_sec = second;

    setenv("TZ", "UTC0", 1);
    tzset();
    const time_t result = mktime(&value);
    return result > 0 ? static_cast<uint32_t>(result) : 1767225600U;
}

bool TimeService::tryNtp() {
    if (WiFi.status() != WL_CONNECTED) return false;

    configTime(Config::GMT_OFFSET_SECONDS,
               Config::DAYLIGHT_OFFSET_SECONDS,
               "pool.ntp.org", "time.google.com", "time.cloudflare.com");

    const uint32_t waitStarted = millis();
    time_t current = 0;
    while (millis() - waitStarted < 6000U) {
        time(&current);
        if (current > 1700000000) {
            Serial.printf("[clock] NTP sincronizado: %ld\n", static_cast<long>(current));
            return true;
        }
        delay(200);
    }
    return false;
}

uint32_t TimeService::rtcEpoch() {
    if (!rtcOnline_) return 0;

    tm value{};
    rtc_.getDateTime(&value);
    const int year = value.tm_year + 1900;
    if (year < 2024 || year > 2099) return 0;

    // O RTC armazena hora local. Convertemos como se fosse UTC e removemos o
    // deslocamento local para recuperar o epoch UTC usado por todo o motor.
    setenv("TZ", "UTC0", 1);
    tzset();
    const time_t localAsUtc = mktime(&value);
    if (localAsUtc <= 0) return 0;
    const int64_t epoch = static_cast<int64_t>(localAsUtc) -
                          static_cast<int64_t>(Config::GMT_OFFSET_SECONDS) -
                          static_cast<int64_t>(Config::DAYLIGHT_OFFSET_SECONDS);
    return epoch > 1700000000LL ? static_cast<uint32_t>(epoch) : 0U;
}

void TimeService::writeRtc(uint32_t epochSeconds) {
    if (!rtcOnline_ || epochSeconds < 1700000000U) return;

    time_t shifted = static_cast<time_t>(epochSeconds) +
                     Config::GMT_OFFSET_SECONDS + Config::DAYLIGHT_OFFSET_SECONDS;
    tm value{};
    gmtime_r(&shifted, &value);
    rtc_.setDateTime(static_cast<uint16_t>(value.tm_year + 1900),
                     static_cast<uint8_t>(value.tm_mon + 1),
                     static_cast<uint8_t>(value.tm_mday),
                     static_cast<uint8_t>(value.tm_hour),
                     static_cast<uint8_t>(value.tm_min),
                     static_cast<uint8_t>(value.tm_sec));
}

void TimeService::seedSystemClock(uint32_t epochSeconds) {
    timeval tv{};
    tv.tv_sec = static_cast<time_t>(epochSeconds);
    tv.tv_usec = 0;
    settimeofday(&tv, nullptr);
}

void TimeService::begin() {
    preferences_.begin("mnemos-clock", false);

    Wire.begin(Config::SYSTEM_I2C_SDA, Config::SYSTEM_I2C_SCL);
    rtc_.begin(Wire);
    Wire.beginTransmission(0x51);
    rtcOnline_ = Wire.endTransmission() == 0;
    Serial.printf("[clock] RTC PCF8563 %s em SDA=%d SCL=%d\n",
                  rtcOnline_ ? "online" : "indisponivel",
                  Config::SYSTEM_I2C_SDA,
                  Config::SYSTEM_I2C_SCL);

    trusted_ = tryNtp();
    if (trusted_) {
        const uint32_t current = static_cast<uint32_t>(time(nullptr));
        writeRtc(current);
        checkpoint();
        return;
    }

    const uint32_t fromRtc = rtcEpoch();
    if (fromRtc > 0) {
        seedSystemClock(fromRtc);
        trusted_ = true;
        preferences_.putULong("lastEpoch", fromRtc);
        lastCheckpointMillis_ = millis();
        Serial.printf("[clock] restaurado do RTC: %lu\n", static_cast<unsigned long>(fromRtc));
        return;
    }

    const uint32_t saved = preferences_.getULong("lastEpoch", 0U);
    fallbackBaseEpoch_ = std::max(compileEpoch(), saved > 0 ? saved + 60U : 0U);
    fallbackBaseMillis_ = millis();
    lastCheckpointMillis_ = millis();
    Serial.printf("[clock] modo aproximado iniciado em %lu\n",
                  static_cast<unsigned long>(fallbackBaseEpoch_));
}

uint32_t TimeService::now() {
    uint32_t value = 0;
    if (trusted_) {
        time_t current = 0;
        time(&current);
        value = static_cast<uint32_t>(current);
    } else {
        value = fallbackBaseEpoch_ + (millis() - fallbackBaseMillis_) / 1000U;
    }

    if (millis() - lastCheckpointMillis_ > 60000U) checkpoint();
    return value;
}

void TimeService::setFromEpoch(uint32_t epochSeconds) {
    if (epochSeconds < 1700000000U) return;

    fallbackBaseEpoch_ = epochSeconds;
    fallbackBaseMillis_ = millis();
    trusted_ = true;
    seedSystemClock(epochSeconds);
    writeRtc(epochSeconds);

    preferences_.putULong("lastEpoch", epochSeconds);
    lastCheckpointMillis_ = millis();
    Serial.printf("[clock] sincronizado pelo celular: %lu\n",
                  static_cast<unsigned long>(epochSeconds));
}

void TimeService::checkpoint() {
    const uint32_t value = trusted_
        ? static_cast<uint32_t>(time(nullptr))
        : fallbackBaseEpoch_ + (millis() - fallbackBaseMillis_) / 1000U;

    if (value > 0) preferences_.putULong("lastEpoch", value);
    lastCheckpointMillis_ = millis();
}
