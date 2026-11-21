#pragma once
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <cmath>
#include <algorithm>
#include "WString.h"
#include "Stream.h"
#define ARDUINO 10819
#define PROGMEM
#define memcpy_P memcpy
typedef uint8_t byte;
uint32_t millis();
uint32_t micros();
void delay(uint32_t ms);
void yield();
uint32_t esp_random();
template <typename T, typename A, typename B> T constrain(T v, A lo, B hi) { return v < (T)lo ? (T)lo : (v > (T)hi ? (T)hi : v); }
class HostSerial : public Stream {
public:
    void begin(unsigned long) {}
    size_t write(uint8_t c) override;
    size_t write(const uint8_t* b, size_t n) override;
    int available() override;
    int read() override;
    std::string input; size_t pos = 0; bool quiet = false;
};
extern HostSerial Serial;
struct EspClass { uint64_t getEfuseMac() { return 0x0000C0FFEE123456ULL; } uint32_t getFreeHeap() { return 200000; } void restart() {} };
extern EspClass ESP;
class IPAddress {
public:
    uint8_t b[4] = {0, 0, 0, 0};
    IPAddress() {}
    IPAddress(uint8_t a, uint8_t c, uint8_t d, uint8_t e) { b[0] = a; b[1] = c; b[2] = d; b[3] = e; }
    bool operator==(const IPAddress& o) const { return memcmp(b, o.b, 4) == 0; }
    bool operator!=(const IPAddress& o) const { return !(*this == o); }
    String toString() const { char s[20]; snprintf(s, sizeof s, "%u.%u.%u.%u", b[0], b[1], b[2], b[3]); return String(s); }
};
