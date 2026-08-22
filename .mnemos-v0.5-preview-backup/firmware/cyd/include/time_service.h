#pragma once

#include <Arduino.h>
#include <Preferences.h>

class TimeService {
public:
    void begin();
    uint32_t now();
    bool trusted() const { return trusted_; }
    void setFromEpoch(uint32_t epochSeconds);
    void checkpoint();

private:
    uint32_t compileEpoch() const;
    bool tryNtp();

    Preferences preferences_;
    bool trusted_ = false;
    uint32_t fallbackBaseEpoch_ = 0;
    uint32_t fallbackBaseMillis_ = 0;
    uint32_t lastCheckpointMillis_ = 0;
};
