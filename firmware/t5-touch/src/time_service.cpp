#include "time_service.h"

#include <WiFi.h>
#include <Wire.h>
#include <time.h>
#include <sys/time.h>
#include <esp_sntp.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "config.h"

namespace {

constexpr uint8_t PCF8563_ADDRESS =
    0x51;

constexpr uint8_t PCF8563_SECONDS_REGISTER =
    0x02;

constexpr uint8_t PCF8563_VOLTAGE_LOW_MASK =
    0x80;

constexpr uint32_t MIN_VALID_EPOCH =
    1700000000U;

constexpr uint32_t RTC_BUILD_TOLERANCE_SECONDS =
    6U * 3600U;

constexpr uint32_t NTP_RETRY_INTERVAL_MS =
    5U * 60U * 1000U;

constexpr uint32_t NTP_WAIT_MS =
    4000U;

int monthFromName(
    const char* month) {

    static const char* MONTHS[] = {
        "Jan", "Feb", "Mar", "Apr",
        "May", "Jun", "Jul", "Aug",
        "Sep", "Oct", "Nov", "Dec"
    };

    for (int i = 0; i < 12; ++i) {
        if (
            std::strncmp(
                month,
                MONTHS[i],
                3) == 0
        ) {
            return i;
        }
    }

    return 0;
}

}  // namespace


uint32_t TimeService::compileEpoch() const {
    char month[4] = {0};

    int day = 1;
    int year = 2026;
    int hour = 0;
    int minute = 0;
    int second = 0;

    std::sscanf(
        __DATE__,
        "%3s %d %d",
        month,
        &day,
        &year);

    std::sscanf(
        __TIME__,
        "%d:%d:%d",
        &hour,
        &minute,
        &second);

    tm value{};

    value.tm_year =
        year - 1900;

    value.tm_mon =
        monthFromName(month);

    value.tm_mday =
        day;

    value.tm_hour =
        hour;

    value.tm_min =
        minute;

    value.tm_sec =
        second;

    // __DATE__/__TIME__ sao gerados no fuso do host de build.
    // O projeto usa GMT_OFFSET_SECONDS como fuso local do terminal,
    // portanto convertemos explicitamente esses campos locais para UTC.
    setenv("TZ", "UTC0", 1);
    tzset();

    const time_t localAsUtc =
        mktime(&value);

    if (localAsUtc <= 0) {
        return 1767225600U;
    }

    const int64_t epoch =
        static_cast<int64_t>(
            localAsUtc) -
        static_cast<int64_t>(
            utcOffsetSeconds_) -
        static_cast<int64_t>(
            daylightOffsetSeconds_);

    return
        epoch > 0
            ? static_cast<uint32_t>(epoch)
            : 1767225600U;
}


bool TimeService::setTimezoneOffsetSeconds(
    int32_t utcOffsetSeconds,
    int32_t daylightOffsetSeconds) {

    if (
        utcOffsetSeconds <
            -12L * 3600L ||
        utcOffsetSeconds >
            14L * 3600L ||
        daylightOffsetSeconds <
            -2L * 3600L ||
        daylightOffsetSeconds >
            2L * 3600L
    ) {
        return false;
    }

    if (
        utcOffsetSeconds_ ==
            utcOffsetSeconds &&
        daylightOffsetSeconds_ ==
            daylightOffsetSeconds
    ) {
        return true;
    }

    const uint32_t current =
        now();

    utcOffsetSeconds_ =
        utcOffsetSeconds;

    daylightOffsetSeconds_ =
        daylightOffsetSeconds;

    preferences_.putInt(
        "tzOffset",
        utcOffsetSeconds_);

    preferences_.putInt(
        "dstOffset",
        daylightOffsetSeconds_);

    if (
        current >=
        MIN_VALID_EPOCH
    ) {
        writeRtc(current);
    }

    Serial.printf(
        "[clock] timezone atualizado utc=%+ld dst=%+ld\\n",
        static_cast<long>(
            utcOffsetSeconds_),
        static_cast<long>(
            daylightOffsetSeconds_));

    return true;
}


bool TimeService::tryNtp(
    uint32_t waitMs) {

    if (
        WiFi.status() !=
        WL_CONNECTED
    ) {
        return false;
    }

    lastNtpAttemptMillis_ =
        millis();

    // Se o relogio ja foi semeado pelo RTC, simplesmente testar
    // time(nullptr) daria um falso positivo. Zeramos temporariamente
    // o clock do sistema, aguardamos uma resposta SNTP real e, em caso
    // de falha, restauramos a fonte anterior.
    time_t previous = 0;
    time(&previous);

    const uint32_t started =
        millis();

    timeval zero{};
    settimeofday(
        &zero,
        nullptr);

    configTime(
        0,
        0,
        "pool.ntp.org",
        "time.google.com",
        "time.cloudflare.com");

    time_t current = 0;

    while (
        millis() -
            started <
        waitMs
    ) {
        time(&current);

        if (
            current >
            static_cast<time_t>(
                MIN_VALID_EPOCH)
        ) {
            Serial.printf(
                "[clock] NTP sincronizado: %ld\n",
                static_cast<long>(
                    current));

            return true;
        }

        delay(200);
    }

    if (
        previous >
        static_cast<time_t>(
            MIN_VALID_EPOCH)
    ) {
        const uint32_t elapsed =
            (
                millis() -
                started
            ) /
            1000U;

        seedSystemClock(
            static_cast<uint32_t>(
                previous) +
            elapsed);
    }

    Serial.println(
        "[clock] NTP indisponivel; "
        "fonte anterior preservada");

    return false;
}


bool TimeService::rtcClockIntegrityOk() {
    if (!rtcOnline_) {
        return false;
    }

    Wire.beginTransmission(
        PCF8563_ADDRESS);

    Wire.write(
        PCF8563_SECONDS_REGISTER);

    if (
        Wire.endTransmission(false) !=
        0
    ) {
        return false;
    }

    if (
        Wire.requestFrom(
            static_cast<int>(
                PCF8563_ADDRESS),
            1) != 1
    ) {
        return false;
    }

    const uint8_t seconds =
        Wire.read();

    const bool voltageLow =
        (
            seconds &
            PCF8563_VOLTAGE_LOW_MASK
        ) != 0;

    if (voltageLow) {
        Serial.println(
            "[clock] PCF8563 sinaliza "
            "voltage-low; data RTC ignorada");
    }

    return !voltageLow;
}


uint32_t TimeService::rtcEpoch() {
    if (!rtcOnline_) {
        return 0;
    }

    tm value{};

    rtc_.getDateTime(
        &value);

    const int year =
        value.tm_year +
        1900;

    if (
        year < 2024 ||
        year > 2099
    ) {
        return 0;
    }

    // O RTC armazena hora local. Interpretamos os campos como UTC
    // temporariamente e removemos o offset local para obter epoch UTC.
    setenv("TZ", "UTC0", 1);
    tzset();

    const time_t localAsUtc =
        mktime(&value);

    if (localAsUtc <= 0) {
        return 0;
    }

    const int64_t epoch =
        static_cast<int64_t>(
            localAsUtc) -
        static_cast<int64_t>(
            utcOffsetSeconds_) -
        static_cast<int64_t>(
            daylightOffsetSeconds_);

    return
        epoch >
            static_cast<int64_t>(
                MIN_VALID_EPOCH)
            ? static_cast<uint32_t>(
                  epoch)
            : 0U;
}


bool TimeService::rtcCandidatePlausible(
    uint32_t candidate,
    uint32_t buildEpoch,
    uint32_t savedEpoch) const {

    if (
        candidate <
        MIN_VALID_EPOCH
    ) {
        return false;
    }

    if (
        buildEpoch >
            RTC_BUILD_TOLERANCE_SECONDS &&
        candidate +
            RTC_BUILD_TOLERANCE_SECONDS <
            buildEpoch
    ) {
        return false;
    }

    if (
        savedEpoch >
            MIN_VALID_EPOCH &&
        candidate +
            RTC_BUILD_TOLERANCE_SECONDS <
            savedEpoch
    ) {
        return false;
    }

    return true;
}


void TimeService::writeRtc(
    uint32_t epochSeconds) {

    if (
        !rtcOnline_ ||
        epochSeconds <
            MIN_VALID_EPOCH
    ) {
        return;
    }

    time_t shifted =
        static_cast<time_t>(
            epochSeconds) +
        utcOffsetSeconds_ +
        daylightOffsetSeconds_;

    tm value{};

    gmtime_r(
        &shifted,
        &value);

    rtc_.setDateTime(
        static_cast<uint16_t>(
            value.tm_year +
            1900),
        static_cast<uint8_t>(
            value.tm_mon +
            1),
        static_cast<uint8_t>(
            value.tm_mday),
        static_cast<uint8_t>(
            value.tm_hour),
        static_cast<uint8_t>(
            value.tm_min),
        static_cast<uint8_t>(
            value.tm_sec));
}


void TimeService::seedSystemClock(
    uint32_t epochSeconds) {

    timeval tv{};

    tv.tv_sec =
        static_cast<time_t>(
            epochSeconds);

    tv.tv_usec = 0;

    settimeofday(
        &tv,
        nullptr);
}


void TimeService::logLocalTime(
    const char* source,
    uint32_t epochSeconds) const {

    time_t shifted =
        static_cast<time_t>(
            epochSeconds) +
        utcOffsetSeconds_ +
        daylightOffsetSeconds_;

    tm value{};

    gmtime_r(
        &shifted,
        &value);

    char buffer[40];

    std::snprintf(
        buffer,
        sizeof(buffer),
        "%04d-%02d-%02d %02d:%02d:%02d",
        value.tm_year + 1900,
        value.tm_mon + 1,
        value.tm_mday,
        value.tm_hour,
        value.tm_min,
        value.tm_sec);

    Serial.printf(
        "[clock] fonte=%s local=%s epoch=%lu\n",
        source,
        buffer,
        static_cast<unsigned long>(
            epochSeconds));
}


void TimeService::begin() {
    preferences_.begin(
        "mnemos-clock",
        false);

    utcOffsetSeconds_ =
        preferences_.getInt(
            "tzOffset",
            Config::
                GMT_OFFSET_SECONDS);

    daylightOffsetSeconds_ =
        preferences_.getInt(
            "dstOffset",
            Config::
                DAYLIGHT_OFFSET_SECONDS);

    if (
        utcOffsetSeconds_ <
            -12L * 3600L ||
        utcOffsetSeconds_ >
            14L * 3600L
    ) {
        utcOffsetSeconds_ =
            Config::
                GMT_OFFSET_SECONDS;
    }

    if (
        daylightOffsetSeconds_ <
            -2L * 3600L ||
        daylightOffsetSeconds_ >
            2L * 3600L
    ) {
        daylightOffsetSeconds_ =
            Config::
                DAYLIGHT_OFFSET_SECONDS;
    }

    Serial.printf(
        "[clock] timezone UTC%+ld s dst=%+ld s\n",
        static_cast<long>(
            utcOffsetSeconds_),
        static_cast<long>(
            daylightOffsetSeconds_));

    Wire.begin(
        Config::SYSTEM_I2C_SDA,
        Config::SYSTEM_I2C_SCL);

    rtc_.begin(Wire);

    Wire.beginTransmission(
        PCF8563_ADDRESS);

    rtcOnline_ =
        Wire.endTransmission() ==
        0;

    Serial.printf(
        "[clock] RTC PCF8563 %s em SDA=%d SCL=%d\n",
        rtcOnline_
            ? "online"
            : "indisponivel",
        Config::SYSTEM_I2C_SDA,
        Config::SYSTEM_I2C_SCL);

    const uint32_t build =
        compileEpoch();

    const uint32_t saved =
        preferences_.getULong(
            "lastEpoch",
            0U);

    const bool rtcIntegrity =
        rtcClockIntegrityOk();

    const uint32_t fromRtc =
        rtcIntegrity
            ? rtcEpoch()
            : 0U;

    if (
        rtcCandidatePlausible(
            fromRtc,
            build,
            saved)
    ) {
        seedSystemClock(
            fromRtc);

        trusted_ = true;
        ntpSynchronized_ = false;

        preferences_.putULong(
            "lastEpoch",
            fromRtc);

        lastCheckpointMillis_ =
            millis();

        logLocalTime(
            "RTC",
            fromRtc);
    } else {
        if (fromRtc > 0) {
            Serial.printf(
                "[clock] RTC rejeitado: rtc=%lu build=%lu saved=%lu\n",
                static_cast<unsigned long>(fromRtc),
                static_cast<unsigned long>(build),
                static_cast<unsigned long>(saved));
        }

        fallbackBaseEpoch_ =
            std::max(
                build,
                saved > 0
                    ? saved + 60U
                    : 0U);

        fallbackBaseMillis_ =
            millis();

        lastCheckpointMillis_ =
            millis();

        trusted_ = false;
        ntpSynchronized_ = false;

        seedSystemClock(
            fallbackBaseEpoch_);

        logLocalTime(
            "BUILD/FALLBACK",
            fallbackBaseEpoch_);
    }

    ntpPending_ = false;
    lastNtpAttemptMillis_ = 0;

    Serial.println(
        "[clock] boot sem espera por NTP");
}



uint32_t TimeService::now() {
    uint32_t value = 0;

    if (trusted_) {
        time_t current = 0;
        time(&current);

        value =
            static_cast<uint32_t>(
                current);
    } else {
        value =
            fallbackBaseEpoch_ +
            (
                millis() -
                fallbackBaseMillis_
            ) /
                1000U;
    }

    if (
        millis() -
            lastCheckpointMillis_ >
        60000U
    ) {
        checkpoint();
    }

    return value;
}


bool TimeService::maintain() {
    if (ntpSynchronized_) {
        return false;
    }

    const uint32_t nowMs =
        millis();

    if (ntpPending_) {
        if (
            sntp_get_sync_status() ==
            SNTP_SYNC_STATUS_COMPLETED
        ) {
            const uint32_t current =
                static_cast<uint32_t>(
                    time(nullptr));

            if (
                current >=
                MIN_VALID_EPOCH
            ) {
                ntpPending_ = false;
                ntpSynchronized_ = true;
                trusted_ = true;

                fallbackBaseEpoch_ =
                    current;
                fallbackBaseMillis_ =
                    nowMs;

                writeRtc(current);

                preferences_.putULong(
                    "lastEpoch",
                    current);

                lastCheckpointMillis_ =
                    nowMs;

                logLocalTime(
                    "NTP",
                    current);

                return true;
            }
        }

        if (
            nowMs -
                ntpAttemptStartedMillis_ >=
            Config::NTP_SYNC_TIMEOUT_MS
        ) {
            ntpPending_ = false;

            Serial.println(
                "[clock] NTP timeout; relogio atual preservado");
        }

        return false;
    }

    if (
        WiFi.status() !=
        WL_CONNECTED
    ) {
        return false;
    }

    if (
        lastNtpAttemptMillis_ != 0 &&
        nowMs -
            lastNtpAttemptMillis_ <
            NTP_RETRY_INTERVAL_MS
    ) {
        return false;
    }

    lastNtpAttemptMillis_ =
        nowMs;

    ntpAttemptStartedMillis_ =
        nowMs;

    configTime(
        0,
        0,
        "pool.ntp.org",
        "time.google.com",
        "time.cloudflare.com");

    ntpPending_ = true;

    Serial.println(
        "[clock] NTP assincrono iniciado");

    return false;
}



void TimeService::setFromEpoch(
    uint32_t epochSeconds) {

    if (
        epochSeconds <
        MIN_VALID_EPOCH
    ) {
        return;
    }

    fallbackBaseEpoch_ =
        epochSeconds;

    fallbackBaseMillis_ =
        millis();

    trusted_ = true;

    seedSystemClock(
        epochSeconds);

    writeRtc(
        epochSeconds);

    preferences_.putULong(
        "lastEpoch",
        epochSeconds);

    lastCheckpointMillis_ =
        millis();

    logLocalTime(
        "PHONE",
        epochSeconds);
}


void TimeService::checkpoint() {
    const uint32_t value =
        trusted_
            ? static_cast<uint32_t>(
                  time(nullptr))
            : fallbackBaseEpoch_ +
                  (
                      millis() -
                      fallbackBaseMillis_
                  ) /
                      1000U;

    if (value > 0) {
        preferences_.putULong(
            "lastEpoch",
            value);
    }

    lastCheckpointMillis_ =
        millis();
}
