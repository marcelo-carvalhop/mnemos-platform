#include "gps_time_service.h"

#include <Wire.h>

#include <cstdlib>
#include <cstring>

#include "config.h"

namespace {

constexpr uint8_t PCA9535_ADDRESS = 0x20;
constexpr uint8_t PCA9535_OUTPUT0 = 0x02;
constexpr uint8_t PCA9535_CONFIG0 = 0x06;

constexpr uint8_t GPS_RAIL_BIT = 0x01;

constexpr uint32_t GPS_BAUDS[2] = {
    38400U,
    9600U,
};

constexpr uint32_t BAUD_PROBE_MS =
    8000U;

constexpr uint32_t TOTAL_ATTEMPT_MS =
    120000U;

constexpr uint32_t RETRY_INTERVAL_MS =
    5U * 60U * 1000U;

constexpr uint32_t MIN_VALID_EPOCH =
    1700000000U;

}  // namespace


bool GpsTimeService::readPcaRegister(
    uint8_t reg,
    uint8_t& value) {

    Wire.beginTransmission(
        PCA9535_ADDRESS);

    Wire.write(reg);

    if (
        Wire.endTransmission(false) !=
        0
    ) {
        return false;
    }

    if (
        Wire.requestFrom(
            static_cast<int>(
                PCA9535_ADDRESS),
            1) != 1
    ) {
        return false;
    }

    value =
        static_cast<uint8_t>(
            Wire.read());

    return true;
}


bool GpsTimeService::writePcaRegister(
    uint8_t reg,
    uint8_t value) {

    Wire.beginTransmission(
        PCA9535_ADDRESS);

    Wire.write(reg);
    Wire.write(value);

    return
        Wire.endTransmission() ==
        0;
}


bool GpsTimeService::enableRail(
    bool enabled) {

    uint8_t output0 = 0;
    uint8_t config0 = 0xFF;

    if (
        !readPcaRegister(
            PCA9535_OUTPUT0,
            output0) ||
        !readPcaRegister(
            PCA9535_CONFIG0,
            config0)
    ) {
        Serial.println(
            "[gps] PCA9535 indisponível");

        return false;
    }

    if (enabled) {
        output0 |=
            GPS_RAIL_BIT;

        if (
            !writePcaRegister(
                PCA9535_OUTPUT0,
                output0)
        ) {
            return false;
        }

        config0 &=
            static_cast<uint8_t>(
                ~GPS_RAIL_BIT);

        if (
            !writePcaRegister(
                PCA9535_CONFIG0,
                config0)
        ) {
            return false;
        }

        railEnabled_ = true;
    } else {
        output0 &=
            static_cast<uint8_t>(
                ~GPS_RAIL_BIT);

        if (
            !writePcaRegister(
                PCA9535_OUTPUT0,
                output0)
        ) {
            return false;
        }

        railEnabled_ = false;
    }

    return true;
}


void GpsTimeService::startBaud(
    uint8_t index) {

    baudIndex_ =
        index > 1
            ? 1
            : index;

    gpsSerial_.end();

    gpsSerial_.begin(
        GPS_BAUDS[baudIndex_],
        SERIAL_8N1,
        Config::GPS_RX_PIN,
        Config::GPS_TX_PIN);

    gpsSerial_.setTimeout(10);

    baudStartedMs_ =
        millis();

    charsAtCurrentBaud_ = 0;
    lineLength_ = 0;

    Serial.printf(
        "[gps] UART baud=%lu RX=%d TX=%d\n",
        static_cast<unsigned long>(
            GPS_BAUDS[baudIndex_]),
        Config::GPS_RX_PIN,
        Config::GPS_TX_PIN);
}


bool GpsTimeService::begin() {
    if (
        active_ ||
        synchronized_
    ) {
        return true;
    }

    const uint32_t nowMs =
        millis();

    if (
        nextAttemptMs_ != 0 &&
        static_cast<int32_t>(
            nowMs -
            nextAttemptMs_) < 0
    ) {
        return false;
    }

    if (!enableRail(true)) {
        nextAttemptMs_ =
            nowMs +
            RETRY_INTERVAL_MS;

        return false;
    }

    delay(80);

    active_ = true;
    synchronized_ = false;
    epoch_ = 0;

    attemptStartedMs_ =
        millis();

    startBaud(0);

    Serial.println(
        "[gps] aquisição UTC iniciada");

    return true;
}


int GpsTimeService::hexNibble(
    char c) {

    if (
        c >= '0' &&
        c <= '9'
    ) {
        return
            c - '0';
    }

    if (
        c >= 'A' &&
        c <= 'F'
    ) {
        return
            10 +
            c - 'A';
    }

    if (
        c >= 'a' &&
        c <= 'f'
    ) {
        return
            10 +
            c - 'a';
    }

    return -1;
}


bool GpsTimeService::validChecksum(
    const char* line) {

    if (
        line == nullptr ||
        line[0] != '$'
    ) {
        return false;
    }

    const char* star =
        std::strchr(
            line,
            '*');

    if (
        star == nullptr ||
        star[1] == '\0' ||
        star[2] == '\0'
    ) {
        return false;
    }

    uint8_t checksum = 0;

    for (
        const char* p =
            line + 1;
        p < star;
        ++p
    ) {
        checksum ^=
            static_cast<uint8_t>(
                *p);
    }

    const int hi =
        hexNibble(
            star[1]);

    const int lo =
        hexNibble(
            star[2]);

    if (
        hi < 0 ||
        lo < 0
    ) {
        return false;
    }

    const uint8_t expected =
        static_cast<uint8_t>(
            (
                hi << 4
            ) |
            lo);

    return
        checksum ==
        expected;
}


int64_t GpsTimeService::daysFromCivil(
    int year,
    unsigned month,
    unsigned day) {

    year -=
        month <= 2;

    const int era =
        (
            year >= 0
                ? year
                : year - 399
        ) /
        400;

    const unsigned yoe =
        static_cast<unsigned>(
            year -
            era * 400);

    const unsigned doy =
        (
            153U *
            (
                month +
                (
                    month > 2
                        ? static_cast<unsigned>(-3)
                        : 9U
                )
            ) +
            2U
        ) /
        5U +
        day -
        1U;

    const unsigned doe =
        yoe *
            365U +
        yoe /
            4U -
        yoe /
            100U +
        doy;

    return
        static_cast<int64_t>(
            era) *
            146097LL +
        static_cast<int64_t>(
            doe) -
        719468LL;
}


uint32_t GpsTimeService::epochFromUtc(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second) {

    if (
        year < 2024 ||
        year > 2099 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 60
    ) {
        return 0;
    }

    const int64_t days =
        daysFromCivil(
            year,
            static_cast<unsigned>(
                month),
            static_cast<unsigned>(
                day));

    const int64_t epoch =
        days *
            86400LL +
        static_cast<int64_t>(
            hour) *
            3600LL +
        static_cast<int64_t>(
            minute) *
            60LL +
        static_cast<int64_t>(
            second);

    if (
        epoch <
            static_cast<int64_t>(
                MIN_VALID_EPOCH) ||
        epoch >
            4102444799LL
    ) {
        return 0;
    }

    return
        static_cast<uint32_t>(
            epoch);
}


bool GpsTimeService::parseRmc(
    const char* line,
    uint32_t& epochOut) const {

    epochOut = 0;

    if (
        line == nullptr ||
        (
            std::strncmp(
                line,
                "$GNRMC,",
                7) != 0 &&
            std::strncmp(
                line,
                "$GPRMC,",
                7) != 0
        ) ||
        !validChecksum(line)
    ) {
        return false;
    }

    char copy[160];

    std::strncpy(
        copy,
        line,
        sizeof(copy) - 1);

    copy[
        sizeof(copy) - 1
    ] = '\0';

    char* star =
        std::strchr(
            copy,
            '*');

    if (star) {
        *star = '\0';
    }

    const size_t MAX_FIELDS = 16;
    char* fields[MAX_FIELDS] = {nullptr};
    size_t fieldCount = 0;

    char* save = nullptr;

    char* token =
        strtok_r(
            copy,
            ",",
            &save);

    while (
        token != nullptr &&
        fieldCount <
            MAX_FIELDS
    ) {
        fields[fieldCount++] =
            token;

        token =
            strtok_r(
                nullptr,
                ",",
                &save);
    }

    /*
     * RMC:
     * 0 talker
     * 1 hhmmss.sss
     * 2 A/V
     * ...
     * 9 ddmmyy
     */
    if (
        fieldCount <= 9 ||
        fields[1] == nullptr ||
        fields[2] == nullptr ||
        fields[9] == nullptr ||
        fields[2][0] != 'A'
    ) {
        return false;
    }

    if (
        std::strlen(
            fields[1]) < 6 ||
        std::strlen(
            fields[9]) < 6
    ) {
        return false;
    }

    const int hour =
        (
            fields[1][0] - '0'
        ) *
            10 +
        (
            fields[1][1] - '0'
        );

    const int minute =
        (
            fields[1][2] - '0'
        ) *
            10 +
        (
            fields[1][3] - '0'
        );

    const int second =
        (
            fields[1][4] - '0'
        ) *
            10 +
        (
            fields[1][5] - '0'
        );

    const int day =
        (
            fields[9][0] - '0'
        ) *
            10 +
        (
            fields[9][1] - '0'
        );

    const int month =
        (
            fields[9][2] - '0'
        ) *
            10 +
        (
            fields[9][3] - '0'
        );

    const int year =
        2000 +
        (
            fields[9][4] - '0'
        ) *
            10 +
        (
            fields[9][5] - '0'
        );

    epochOut =
        epochFromUtc(
            year,
            month,
            day,
            hour,
            minute,
            second);

    return
        epochOut >=
        MIN_VALID_EPOCH;
}


bool GpsTimeService::consumeChar(
    char c) {

    if (c == '\r') {
        return false;
    }

    if (c == '\n') {
        if (lineLength_ == 0) {
            return false;
        }

        line_[
            lineLength_
        ] = '\0';

        uint32_t candidate = 0;

        const bool valid =
            parseRmc(
                line_,
                candidate);

        lineLength_ = 0;

        if (valid) {
            epoch_ =
                candidate;

            return true;
        }

        return false;
    }

    if (
        lineLength_ >=
        sizeof(line_) - 1
    ) {
        lineLength_ = 0;

        return false;
    }

    line_[
        lineLength_++
    ] = c;

    return false;
}


bool GpsTimeService::maintain() {
    if (synchronized_) {
        return false;
    }

    if (!active_) {
        begin();

        return false;
    }

    while (
        gpsSerial_.available() >
        0
    ) {
        const int value =
            gpsSerial_.read();

        if (value < 0) {
            break;
        }

        ++charsAtCurrentBaud_;

        if (
            consumeChar(
                static_cast<char>(
                    value))
        ) {
            synchronized_ = true;

            Serial.printf(
                "[gps] UTC válido epoch=%lu baud=%lu\n",
                static_cast<unsigned long>(
                    epoch_),
                static_cast<unsigned long>(
                    GPS_BAUDS[
                        baudIndex_]));

            stop();

            return true;
        }
    }

    const uint32_t nowMs =
        millis();

    if (
        charsAtCurrentBaud_ == 0 &&
        nowMs -
            baudStartedMs_ >=
        BAUD_PROBE_MS &&
        baudIndex_ == 0
    ) {
        Serial.println(
            "[gps] sem NMEA em 38400; tentando 9600");

        startBaud(1);

        return false;
    }

    if (
        nowMs -
            attemptStartedMs_ >=
        TOTAL_ATTEMPT_MS
    ) {
        Serial.println(
            "[gps] timeout sem UTC válido");

        stop();

        nextAttemptMs_ =
            nowMs +
            RETRY_INTERVAL_MS;
    }

    return false;
}


void GpsTimeService::stop() {
    gpsSerial_.end();

    if (railEnabled_) {
        enableRail(false);
    }

    active_ = false;
}
