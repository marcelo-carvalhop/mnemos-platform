#pragma once

#include <Arduino.h>
#include <Wire.h>

class CardKbInput {
public:
    CardKbInput();

    bool begin();
    bool online() const { return online_; }
    bool probe();
    uint8_t pollKey();

    static bool printable(uint8_t key);
    static bool isEnter(uint8_t key) { return key == 0x0D || key == '\n'; }
    static bool isBackspace(uint8_t key) { return key == 0x08 || key == 0x7F; }

private:
    bool configureBus(int sda, int scl);
    bool addressResponds(uint8_t address);
    bool scanAndSelect(int sda, int scl);

    TwoWire wire_;
    bool busStarted_ = false;
    bool online_ = false;
    int activeSda_ = -1;
    int activeScl_ = -1;
    uint32_t lastPollMs_ = 0;
};
