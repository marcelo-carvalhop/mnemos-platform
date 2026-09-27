#pragma once

#include <Arduino.h>
#include <cstring>

enum class WifiKeyboardPage : uint8_t {
    Lower = 0,
    Upper = 1,
    Symbols = 2,
};

inline const char* wifiKeyboardChars(
    WifiKeyboardPage page) {

    switch (page) {
        case WifiKeyboardPage::Upper:
            return "1234567890QWERTYUIOPASDFGHJKLZXCVBNM";

        case WifiKeyboardPage::Symbols:
            // 36 printable symbols; space is a dedicated control.
            return "!@#$%^&*()-_=+[]{}\\|;:'\",.<>/?`~";

        case WifiKeyboardPage::Lower:
        default:
            return "1234567890qwertyuiopasdfghjklzxcvbnm";
    }
}

inline size_t wifiKeyboardCharCount(
    WifiKeyboardPage page) {

    return strlen(
        wifiKeyboardChars(page));
}

inline char wifiKeyboardCharAt(
    WifiKeyboardPage page,
    size_t index) {

    const char* chars =
        wifiKeyboardChars(page);

    const size_t count =
        strlen(chars);

    return
        index < count
            ? chars[index]
            : '\0';
}

inline const char* wifiKeyboardPageLabel(
    WifiKeyboardPage page) {

    switch (page) {
        case WifiKeyboardPage::Upper:
            return "ABC";
        case WifiKeyboardPage::Symbols:
            return "#+=";
        case WifiKeyboardPage::Lower:
        default:
            return "abc";
    }
}
