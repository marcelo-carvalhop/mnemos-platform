#pragma once

#include <Arduino.h>
#include <Preferences.h>
#include <SensorPCF8563.hpp>

class TimeService {
public:
    void begin();
    uint32_t now();

    bool trusted() const { return trusted_; }
    bool rtcOnline() const { return rtcOnline_; }
    bool ntpSynchronized() const { return ntpSynchronized_; }

    void setFromEpoch(uint32_t epochSeconds);
    void checkpoint();

    // Tenta NTP quando a rede passa a ficar disponivel depois do boot.
    // Retorna true apenas quando a fonte de tempo acabou de ser corrigida.
    bool maintain();

private:
    Preferences preferences_;
    SensorPCF8563 rtc_;

    bool trusted_ = false;
    bool rtcOnline_ = false;
    bool ntpSynchronized_ = false;

    uint32_t fallbackBaseEpoch_ = 0;
    uint32_t fallbackBaseMillis_ = 0;
    uint32_t lastCheckpointMillis_ = 0;
    uint32_t lastNtpAttemptMillis_ = 0;

    bool tryNtp(uint32_t waitMs);
    uint32_t compileEpoch() const;
    uint32_t rtcEpoch();
    bool rtcClockIntegrityOk();
    bool rtcCandidatePlausible(
        uint32_t candidate,
        uint32_t buildEpoch,
        uint32_t savedEpoch) const;

    void writeRtc(uint32_t epochSeconds);
    void seedSystemClock(uint32_t epochSeconds);
    void logLocalTime(
        const char* source,
        uint32_t epochSeconds) const;
};
