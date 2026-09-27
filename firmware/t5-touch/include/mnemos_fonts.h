#pragma once

#include <Arduino.h>

enum class MnemosFontRole : uint8_t {
    Meta14 = 0,
    Body18 = 1,
    Title22 = 2,
};

int32_t mnemosFontTextWidth(
    const String& text,
    MnemosFontRole role);

bool mnemosFontTextBounds(
    const String& text,
    MnemosFontRole role,
    int32_t& left,
    int32_t& right);

bool mnemosFontVisualBounds(
    const String& text,
    MnemosFontRole role,
    int32_t& left,
    int32_t& top,
    int32_t& right,
    int32_t& bottom);

void mnemosFontDrawText(
    const String& text,
    int32_t x,
    int32_t baselineY,
    uint8_t* framebuffer,
    int32_t canvasWidth,
    int32_t canvasHeight,
    MnemosFontRole role,
    uint8_t color = 0x00,
    uint8_t scale = 1);
