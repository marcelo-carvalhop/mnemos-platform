#pragma once

#include <Arduino.h>
#include <Preferences.h>
#include <SPI.h>
#include <TFT_eSPI.h>
#include <XPT2046_Touchscreen.h>
#include "models.h"

struct TouchPoint {
    int16_t x = 0;
    int16_t y = 0;
};

enum class UiAction : uint8_t {
    None = 0,
    Start,
    OpenSync,
    OpenConnection,
    SyncBackend,
    SyncBluetooth,
    ConfigureNetwork,
    ToggleWifi,
    Back,
    CancelPairing,
    CancelBluetooth,
    ConfidenceDontKnow,
    ConfidenceMaybe,
    ConfidenceCertain,
    Reveal,
    RateAgain,
    RateHard,
    RateGood,
    RateEasy,
    Home,
};

class CydDisplay {
public:
    CydDisplay();

    void begin();
    UiAction pollAction();

    void showBoot(const String& message);
    void showHome(uint16_t due, size_t total, bool trustedClock, bool canResume);
    void showSyncMenu(size_t total, uint16_t pendingReviews, bool wifiConnected);
    void showConnectionMenu(bool wifiEnabled, bool wifiConnected, const String& ssid, size_t knownNetworks);
    void showBluetoothSync(const String& deviceId, bool connected);
    void showPairing(const String& qrPayload, const String& ssid, const String& password);
    void showQuestion(const CardDefinition& card,
                      uint8_t position,
                      uint8_t total,
                      Confidence confidence);
    void showAnswer(const CardDefinition& card,
                    uint8_t position,
                    uint8_t total);
    void showSummary(const SessionStats& stats, uint16_t remainingDue);

private:
    struct Calibration {
        int32_t x0 = 200;
        int32_t x1 = 3800;
        int32_t y0 = 200;
        int32_t y1 = 3800;
        bool swapAxes = false;
        bool valid = false;
    };

    struct Button {
        int16_t x = 0;
        int16_t y = 0;
        int16_t w = 0;
        int16_t h = 0;
        UiAction action = UiAction::None;

        Button() = default;
        Button(int16_t xValue,
               int16_t yValue,
               int16_t widthValue,
               int16_t heightValue,
               UiAction actionValue)
            : x(xValue), y(yValue), w(widthValue), h(heightValue), action(actionValue) {}
    };

    static constexpr int16_t WIDTH = 240;
    static constexpr int16_t HEIGHT = 320;
    static constexpr uint8_t MAX_BUTTONS = 8;

    TFT_eSPI tft_;
    XPT2046_Touchscreen touch_;
    Preferences preferences_;
    Calibration calibration_;

    Button buttons_[MAX_BUTTONS];
    uint8_t buttonCount_ = 0;
    bool touchWasDown_ = false;
    uint32_t lastTouchMs_ = 0;

    void calibrateTouch();
    TS_Point collectCalibrationPoint(int16_t x, int16_t y, const char* label);
    bool readMappedTouch(TouchPoint& point);
    int16_t mapAxis(int32_t value, int32_t from0, int32_t from1, int16_t toMax) const;

    void clear(uint16_t color = 0xF79D);
    void clearButtons();
    void drawHeader(const String& title, const String& rightText = "");
    void drawButton(int16_t x, int16_t y, int16_t w, int16_t h,
                    const String& label, UiAction action,
                    bool selected = false, bool enabled = true);
    int16_t drawWrappedText(const String& text,
                            int16_t x, int16_t y, int16_t maxWidth,
                            uint8_t font, uint16_t color,
                            int16_t lineHeight, uint8_t maxLines = 10);
    void drawCentered(const String& text, int16_t y, uint8_t font, uint16_t color);
};
