#include "time_service.h"

#include <WiFi.h>
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
    int day = 1;
    int year = 2026;
    int hour = 0;
    int minute = 0;
    int second = 0;

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
    time_t result = mktime(&value);
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


void TimeService::begin() {
    preferences_.begin("mnemos-clock", false);

    trusted_ = tryNtp();
    if (trusted_) {
        checkpoint();
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

    timeval tv{};
    tv.tv_sec = static_cast<time_t>(epochSeconds);
    tv.tv_usec = 0;
    settimeofday(&tv, nullptr);

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
