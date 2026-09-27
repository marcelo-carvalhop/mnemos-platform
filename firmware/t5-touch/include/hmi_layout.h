#pragma once

#include <Arduino.h>

namespace HmiLayout {

struct Rect {
    int16_t x;
    int16_t y;
    int16_t w;
    int16_t h;
};

constexpr int16_t MARGIN = 48;

constexpr int16_t PORTRAIT_WIDTH = 540;
constexpr int16_t PORTRAIT_HEIGHT = 960;
constexpr int16_t LANDSCAPE_WIDTH = 960;
constexpr int16_t LANDSCAPE_HEIGHT = 540;

inline int16_t logicalWidth(bool portrait) {
    return portrait
        ? PORTRAIT_WIDTH
        : LANDSCAPE_WIDTH;
}

inline int16_t logicalHeight(bool portrait) {
    return portrait
        ? PORTRAIT_HEIGHT
        : LANDSCAPE_HEIGHT;
}

inline int16_t systemBarHeight(bool portrait) {
    return portrait
        ? 88
        : 72;
}

inline int16_t actionTop(bool portrait) {
    return portrait
        ? 824
        : 468;
}

inline int16_t actionHeight(bool portrait) {
    return portrait
        ? 136
        : 72;
}

inline Rect actionZone(bool portrait) {
    return {
        MARGIN,
        actionTop(portrait),
        static_cast<int16_t>(
            logicalWidth(portrait) -
            2 * MARGIN),
        actionHeight(portrait)
    };
}

inline Rect actionVisualRect(bool portrait) {
    const Rect zone =
        actionZone(portrait);

    const int16_t verticalInset =
        portrait
            ? 12
            : 14;

    return {
        zone.x,
        static_cast<int16_t>(
            zone.y +
            verticalInset),
        zone.w,
        static_cast<int16_t>(
            zone.h -
            2 * verticalInset)
    };
}

// Navigation context strip --------------------------------------------

inline int16_t navTitleBaseline(bool portrait) {
    return portrait ? 120 : 99;
}

inline int16_t navMetaBaseline(bool portrait) {
    return portrait ? 149 : 122;
}

inline int16_t navContextBottom(bool portrait) {
    return portrait ? 168 : 136;
}

inline int16_t navContentTop(bool portrait) {
    return portrait ? 184 : 150;
}

inline Rect deckAllCard(bool portrait) {
    if (portrait) {
        return {
            MARGIN,
            184,
            static_cast<int16_t>(
                PORTRAIT_WIDTH -
                2 * MARGIN),
            82
        };
    }

    return {
        MARGIN,
        150,
        408,
        82
    };
}

inline Rect deckCard(
    bool portrait,
    uint8_t index) {

    if (portrait) {
        return {
            MARGIN,
            static_cast<int16_t>(
                282 +
                index * 98),
            static_cast<int16_t>(
                PORTRAIT_WIDTH -
                2 * MARGIN),
            82
        };
    }

    const uint8_t slot =
        static_cast<uint8_t>(
            index + 1);

    return {
        static_cast<int16_t>(
            MARGIN +
            (
                slot % 2
            ) *
                456),
        static_cast<int16_t>(
            150 +
            (
                slot / 2
            ) *
                96),
        408,
        82
    };
}

inline Rect connectionCard(
    bool portrait,
    uint8_t index) {

    if (portrait) {
        return {
            MARGIN,
            static_cast<int16_t>(
                286 +
                index * 120),
            static_cast<int16_t>(
                PORTRAIT_WIDTH -
                2 * MARGIN),
            100
        };
    }

    constexpr int16_t GAP = 18;
    constexpr int16_t CARD_W =
        (
            LANDSCAPE_WIDTH -
            2 * MARGIN -
            2 * GAP
        ) /
        3;

    return {
        static_cast<int16_t>(
            MARGIN +
            index *
                (
                    CARD_W +
                    GAP
                )),
        230,
        CARD_W,
        116
    };
}

inline Rect storageFileCard(
    bool portrait,
    uint8_t index) {

    if (portrait) {
        return {
            MARGIN,
            static_cast<int16_t>(
                264 +
                index * 94),
            static_cast<int16_t>(
                PORTRAIT_WIDTH -
                2 * MARGIN),
            80
        };
    }

    return {
        static_cast<int16_t>(
            MARGIN +
            (
                index % 2
            ) *
                456),
        static_cast<int16_t>(
            200 +
            (
                index / 2
            ) *
                86),
        408,
        74
    };
}

// Home ---------------------------------------------------------------

inline int16_t homePortraitStartY() {
    return 210;
}

inline int16_t homePortraitRowHeight() {
    return 78;
}

inline int16_t homePortraitBaseline(uint8_t index) {
    return
        homePortraitStartY() +
        static_cast<int16_t>(
            index) *
        homePortraitRowHeight();
}

inline Rect homeLandscapeCard(uint8_t index) {
    constexpr int16_t CARD_W = 408;
    constexpr int16_t CARD_H = 68;
    constexpr int16_t COLUMN_GAP = 48;
    constexpr int16_t START_Y = 150;
    constexpr int16_t ROW_STEP = 78;

    const int16_t col =
        static_cast<int16_t>(
            index % 2);

    const int16_t row =
        static_cast<int16_t>(
            index / 2);

    return {
        static_cast<int16_t>(
            MARGIN +
            col *
                (
                    CARD_W +
                    COLUMN_GAP
                )),
        static_cast<int16_t>(
            START_Y +
            row *
                ROW_STEP),
        CARD_W,
        CARD_H
    };
}


// Menu ---------------------------------------------------------------

inline Rect menuCard(
    bool portrait,
    uint8_t index) {

    if (portrait) {
        return {
            MARGIN,
            static_cast<int16_t>(
                184 +
                index * 100),
            static_cast<int16_t>(
                PORTRAIT_WIDTH -
                2 * MARGIN),
            84
        };
    }

    constexpr int16_t GAP = 18;
    constexpr int16_t CARD_H = 112;
    constexpr int16_t CARD_W =
        (
            LANDSCAPE_WIDTH -
            2 * MARGIN -
            2 * GAP
        ) /
        3;

    const int16_t col =
        static_cast<int16_t>(
            index % 3);

    const int16_t row =
        static_cast<int16_t>(
            index / 3);

    return {
        static_cast<int16_t>(
            MARGIN +
            col *
                (
                    CARD_W +
                    GAP
                )),
        static_cast<int16_t>(
            150 +
            row * 132),
        CARD_W,
        CARD_H
    };
}


}  // namespace HmiLayout
