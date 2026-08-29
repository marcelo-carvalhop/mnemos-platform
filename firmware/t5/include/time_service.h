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
    void setFromEpoch(uint32_t epochSeconds);
    void checkpoint();

private:
    Preferences preferences_;
    SensorPCF8563 rtc_;
    bool trusted_ = false;
    bool rtcOnline_ = false;
    uint32_t fallbackBaseEpoch_ = 0;
    uint32_t fallbackBaseMillis_ = 0;
    uint32_t lastCheckpointMillis_ = 0;

    bool tryNtp();
    uint32_t compileEpoch() const;
    uint32_t rtcEpoch();
    void writeRtc(uint32_t epochSeconds);
    void seedSystemClock(uint32_t epochSeconds);
};
