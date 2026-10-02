#pragma once

#include <Arduino.h>
#include <Preferences.h>
#include <SensorPCF8563.hpp>
#include "config.h"

class TimeService {
public:
    void begin();
    uint32_t now();

    bool trusted() const { return trusted_; }
    bool rtcOnline() const { return rtcOnline_; }
    bool ntpSynchronized() const { return ntpSynchronized_; }

    int32_t utcOffsetSeconds() const {
        return utcOffsetSeconds_;
    }

    int32_t daylightOffsetSeconds() const {
        return daylightOffsetSeconds_;
    }

    bool setTimezoneOffsetSeconds(
        int32_t utcOffsetSeconds,
        int32_t daylightOffsetSeconds = 0);

    void setFromEpoch(uint32_t epochSeconds);

    void setFromGpsEpoch(uint32_t epochSeconds);    void checkpoint();

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
    uint32_t ntpAttemptStartedMillis_ = 0;
    bool ntpPending_ = false;

    int32_t utcOffsetSeconds_ =
        Config::GMT_OFFSET_SECONDS;

    int32_t daylightOffsetSeconds_ =
        Config::DAYLIGHT_OFFSET_SECONDS;

    bool tryNtp(uint32_t waitMs);  // legado; fora do fluxo normal
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
