#pragma once

#include <Arduino.h>

class GpsTimeService {
public:
    bool begin();

    // Retorna true uma única vez quando uma hora UTC válida
    // foi obtida. O epoch fica disponível em epoch().
    bool maintain();

    void stop();

    bool active() const {
        return active_;
    }

    bool synchronized() const {
        return synchronized_;
    }

    uint32_t epoch() const {
        return epoch_;
    }

private:
    HardwareSerial gpsSerial_{2};

    bool active_ = false;
    bool synchronized_ = false;
    bool railEnabled_ = false;

    uint32_t epoch_ = 0;
    uint32_t attemptStartedMs_ = 0;
    uint32_t baudStartedMs_ = 0;
    uint32_t nextAttemptMs_ = 0;
    uint32_t charsAtCurrentBaud_ = 0;

    uint8_t baudIndex_ = 0;

    char line_[160] = {0};
    size_t lineLength_ = 0;

    bool enableRail(bool enabled);
    bool readPcaRegister(
        uint8_t reg,
        uint8_t& value);
    bool writePcaRegister(
        uint8_t reg,
        uint8_t value);

    void startBaud(uint8_t index);
    bool consumeChar(char c);
    bool parseRmc(
        const char* line,
        uint32_t& epochOut) const;

    static bool validChecksum(
        const char* line);

    static int hexNibble(char c);

    static uint32_t epochFromUtc(
        int year,
        int month,
        int day,
        int hour,
        int minute,
        int second);

    static int64_t daysFromCivil(
        int year,
        unsigned month,
        unsigned day);
};
