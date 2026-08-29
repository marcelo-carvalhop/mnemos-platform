#pragma once

#include <Arduino.h>
#include "models.h"

class T5Display {
public:
    bool begin();
    bool ready() const { return framebuffer_ != nullptr; }

    void setBatteryStatus(bool available, uint8_t percent);

    void showBoot(const String& message);
    void showKeyboardMissing();
    void showHome(uint16_t due, uint16_t newCards, size_t total, bool trustedClock,
                  bool canResume, const String& nextReview);
    void showMainMenu();
    void showAgenda(uint16_t dueNow, uint16_t laterToday, uint16_t tomorrow,
                    uint16_t next7Days, const String& nextReview);
    void showSyncMenu(size_t total, uint16_t pendingReviews, bool wifiConnected);
    void showConnectionMenu(bool wifiEnabled, bool wifiConnected, const String& ssid, size_t knownNetworks);
    void showLocalLink(const String& qrPayload, const String& ssid, const String& password, bool provisioning);
    void showQuestion(const CardDefinition& card, uint8_t position, uint8_t total);
    void showSelfAssessment(const CardDefinition& card, uint8_t position, uint8_t total);
    void showObjectiveFeedback(const CardDefinition& card, uint8_t position, uint8_t total,
                               int8_t selectedOptionIndex, Outcome outcome);
    void showEffort(uint8_t position, uint8_t total);
    void showSummary(const SessionStats& stats, uint16_t remainingDue, uint16_t remainingNew,
                     const String& nextReview);

private:
    uint8_t* framebuffer_ = nullptr;
    bool powerOn_ = false;
    bool batteryAvailable_ = false;
    uint8_t batteryPercent_ = 0;

    void clearBuffer();
    void ensurePower();
    void refreshFull();
    void drawText(const String& text, int32_t x, int32_t y, uint8_t* target = nullptr);
    int32_t drawWrapped(const String& text, int32_t x, int32_t y,
                        uint16_t maxWidthPx, uint16_t lineHeight,
                        uint8_t maxLines, uint8_t* target = nullptr);
    void drawHeader(const String& title, const String& rightText = "");
    void drawFooter(const String& hint);
    void drawChoice(uint8_t number, const String& label, int32_t y);
    void drawQr(const String& payload, int32_t originX, int32_t originY, int scale);
};
