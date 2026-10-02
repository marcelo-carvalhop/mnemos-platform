#pragma once

#include <Arduino.h>
#include <Preferences.h>

class BacklightService {
public:
    bool begin();

    void cycle();
    void setLevel(uint8_t level);

    void suspend();
    void resume();

    uint8_t level() const {
        return level_;
    }

    uint8_t duty() const;

    const char* label() const;

private:
    static constexpr uint8_t LEVEL_COUNT = 4;

    Preferences preferences_;

    uint8_t level_ = 0;
    bool initialized_ = false;

    void apply();
};
