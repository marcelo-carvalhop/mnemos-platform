#pragma once

// Core Arduino mínimo para os testes no host (pio test -e native).
// Só cobre o que os módulos testados usam.

#include <cstdarg>
#include <cstddef>
#include <cstdint>
#include <cstdio>

#include "WString.h"

namespace test_support {

inline uint32_t millisValue = 0;

// Liga a saída serial dos módulos durante a depuração de um teste.
inline bool echoSerial = false;

}  // namespace test_support

inline uint32_t millis() {
    return test_support::millisValue;
}

inline void delay(uint32_t ms) {
    test_support::millisValue += ms;
}

inline void delayMicroseconds(uint32_t) {}

struct SerialStub {
    void println(const char* text) {
        if (test_support::echoSerial) {
            std::printf("%s\n", text);
        }
    }

    __attribute__((format(printf, 2, 3)))
    int printf(const char* format, ...) {
        if (!test_support::echoSerial) {
            return 0;
        }

        va_list args;
        va_start(args, format);
        const int written = std::vprintf(format, args);
        va_end(args);
        return written;
    }
};

inline SerialStub Serial;
