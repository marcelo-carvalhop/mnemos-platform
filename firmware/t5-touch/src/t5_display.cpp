#include "t5_display.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>

#include "config.h"
#include "hmi_layout.h"
#include "epd_driver.h"

#include <qrcode.h>

namespace {

constexpr uint8_t BLACK = 0x00;
constexpr uint8_t DARK_GRAY = 0x55;
constexpr uint8_t MID_GRAY = 0x99;
constexpr uint8_t LIGHT_GRAY = 0xDD;
constexpr uint8_t WHITE = 0xFF;

constexpr int32_t PORTRAIT_WIDTH =
    HmiLayout::PORTRAIT_WIDTH;
constexpr int32_t PORTRAIT_HEIGHT =
    HmiLayout::PORTRAIT_HEIGHT;
constexpr int32_t LANDSCAPE_WIDTH =
    HmiLayout::LANDSCAPE_WIDTH;
constexpr int32_t LANDSCAPE_HEIGHT =
    HmiLayout::LANDSCAPE_HEIGHT;

constexpr int32_t MARGIN =
    HmiLayout::MARGIN;

String shortText(
    const String& value,
    size_t maxBytes) {

    if (value.length() <= maxBytes) {
        return value;
    }

    if (maxBytes <= 3) {
        return "...";
    }

    return
        value.substring(
            0,
            maxBytes - 3) +
        "...";
}

}  // namespace

bool T5Display::begin() {
    constexpr size_t LOGICAL_BYTES =
        static_cast<size_t>(
            EPD_WIDTH) *
        static_cast<size_t>(
            EPD_HEIGHT);

    constexpr size_t PHYSICAL_BYTES =
        static_cast<size_t>(
            EPD_WIDTH) *
        static_cast<size_t>(
            EPD_HEIGHT) /
        2U;

    framebuffer_ =
        static_cast<uint8_t*>(
            ps_malloc(LOGICAL_BYTES));

    physicalFramebuffer_ =
        static_cast<uint8_t*>(
            ps_malloc(PHYSICAL_BYTES));

    if (
        !framebuffer_ ||
        !physicalFramebuffer_
    ) {
        Serial.println(
            "[display] falha ao alocar "
            "canvas/framebuffer na PSRAM");
        return false;
    }

    std::memset(
        framebuffer_,
        WHITE,
        LOGICAL_BYTES);

    std::memset(
        physicalFramebuffer_,
        WHITE,
        PHYSICAL_BYTES);

    epd_init();

    orientation_ =
        DisplayOrientation::Portrait;

    ensurePower();
    epd_clear();

    Serial.printf(
        "[display] T5 EPD pronto %dx%d; "
        "canvas=%u bytes physical=%u bytes\n",
        EPD_WIDTH,
        EPD_HEIGHT,
        static_cast<unsigned>(
            LOGICAL_BYTES),
        static_cast<unsigned>(
            PHYSICAL_BYTES));

    return true;
}

void T5Display::setBatteryStatus(
    bool available,
    uint8_t percent) {

    batteryAvailable_ =
        available;

    batteryPercent_ =
        std::min<uint8_t>(
            100,
            percent);
}

void T5Display::setOrientation(
    DisplayOrientation orientation) {

    orientation_ =
        orientation;

    Serial.printf(
        "[display] orientation=%s "
        "logical=%dx%d "
        "(software rotation)\n",
        portrait()
            ? "portrait"
            : "landscape",
        static_cast<int>(
            logicalWidth()),
        static_cast<int>(
            logicalHeight()));
}

int32_t T5Display::logicalWidth() const {
    return
        portrait()
            ? PORTRAIT_WIDTH
            : LANDSCAPE_WIDTH;
}

int32_t T5Display::logicalHeight() const {
    return
        portrait()
            ? PORTRAIT_HEIGHT
            : LANDSCAPE_HEIGHT;
}

int32_t T5Display::systemBarHeight() const {
    return
        HmiLayout::systemBarHeight(
            portrait());
}

int32_t T5Display::actionTop() const {
    return
        HmiLayout::actionTop(
            portrait());
}

void T5Display::ensurePower() {
    if (powerOn_) {
        return;
    }

    epd_poweron();
    powerOn_ = true;
}

void T5Display::clearBuffer() {
    if (!framebuffer_) {
        return;
    }

    const size_t bytes =
        static_cast<size_t>(
            logicalWidth()) *
        static_cast<size_t>(
            logicalHeight());

    std::memset(
        framebuffer_,
        WHITE,
        bytes);
}

void T5Display::putPixel(
    int32_t x,
    int32_t y,
    uint8_t color) {

    if (
        !framebuffer_ ||
        x < 0 ||
        y < 0 ||
        x >= logicalWidth() ||
        y >= logicalHeight()
    ) {
        return;
    }

    framebuffer_[
        static_cast<size_t>(y) *
        static_cast<size_t>(
            logicalWidth()) +
        static_cast<size_t>(x)
    ] = color;
}

void T5Display::fillRect(
    int32_t x,
    int32_t y,
    int32_t w,
    int32_t h,
    uint8_t color) {

    if (
        !framebuffer_ ||
        w <= 0 ||
        h <= 0
    ) {
        return;
    }

    const int32_t x0 =
        std::max<int32_t>(
            0,
            x);

    const int32_t y0 =
        std::max<int32_t>(
            0,
            y);

    const int32_t x1 =
        std::min<int32_t>(
            logicalWidth(),
            x + w);

    const int32_t y1 =
        std::min<int32_t>(
            logicalHeight(),
            y + h);

    for (
        int32_t py = y0;
        py < y1;
        ++py
    ) {
        uint8_t* row =
            framebuffer_ +
            static_cast<size_t>(py) *
            static_cast<size_t>(
                logicalWidth());

        for (
            int32_t px = x0;
            px < x1;
            ++px
        ) {
            row[px] =
                color;
        }
    }
}

void T5Display::drawLine(
    int32_t x0,
    int32_t y0,
    int32_t x1,
    int32_t y1,
    uint8_t color) {

    int32_t dx =
        std::abs(
            x1 - x0);

    int32_t stepX =
        x0 < x1
            ? 1
            : -1;

    int32_t dy =
        -std::abs(
            y1 - y0);

    int32_t stepY =
        y0 < y1
            ? 1
            : -1;

    int32_t error =
        dx + dy;

    while (true) {
        putPixel(
            x0,
            y0,
            color);

        if (
            x0 == x1 &&
            y0 == y1
        ) {
            break;
        }

        const int32_t twice =
            2 * error;

        if (twice >= dy) {
            error += dy;
            x0 += stepX;
        }

        if (twice <= dx) {
            error += dx;
            y0 += stepY;
        }
    }
}

void T5Display::drawRect(
    int32_t x,
    int32_t y,
    int32_t w,
    int32_t h,
    uint8_t color) {

    if (
        w <= 0 ||
        h <= 0
    ) {
        return;
    }

    drawLine(
        x,
        y,
        x + w - 1,
        y,
        color);

    drawLine(
        x,
        y + h - 1,
        x + w - 1,
        y + h - 1,
        color);

    drawLine(
        x,
        y,
        x,
        y + h - 1,
        color);

    drawLine(
        x + w - 1,
        y,
        x + w - 1,
        y + h - 1,
        color);
}

void T5Display::drawText(
    const String& text,
    int32_t x,
    int32_t baselineY,
    MnemosFontRole role,
    uint8_t color,
    uint8_t scale) {

    mnemosFontDrawText(
        text,
        x,
        baselineY,
        framebuffer_,
        logicalWidth(),
        logicalHeight(),
        role,
        color,
        scale);
}

int32_t T5Display::textWidth(
    const String& text,
    MnemosFontRole role) const {

    return
        mnemosFontTextWidth(
            text,
            role);
}

int32_t T5Display::centeredTextOriginX(
    const String& text,
    int32_t centerX,
    MnemosFontRole role,
    uint8_t scale) const {

    const uint8_t safeScale =
        scale == 0
            ? 1
            : scale;

    int32_t left = 0;
    int32_t right = 0;

    const bool hasInk =
        mnemosFontTextBounds(
            text,
            role,
            left,
            right);

    if (!hasInk) {
        left = 0;
        right =
            textWidth(
                text,
                role);
    }

    const int32_t visualCenter =
        (
            left +
            right
        ) *
        safeScale /
        2;

    return
        centerX -
        visualCenter;
}

void T5Display::drawCenteredText(
    const String& text,
    int32_t centerX,
    int32_t baselineY,
    MnemosFontRole role,
    uint8_t color,
    uint8_t scale) {

    drawText(
        text,
        centeredTextOriginX(
            text,
            centerX,
            role,
            scale),
        baselineY,
        role,
        color,
        scale);
}

int32_t T5Display::centeredTextBaselineY(
    const String& text,
    int32_t centerY,
    MnemosFontRole role,
    uint8_t scale) const {

    const uint8_t safeScale =
        scale == 0
            ? 1
            : scale;

    int32_t left = 0;
    int32_t top = 0;
    int32_t right = 0;
    int32_t bottom = 0;

    const bool hasInk =
        mnemosFontVisualBounds(
            text,
            role,
            left,
            top,
            right,
            bottom);

    if (!hasInk) {
        return centerY;
    }

    const int32_t visualCenterY =
        (
            top +
            bottom
        ) *
        safeScale /
        2;

    return
        centerY -
        visualCenterY;
}

int32_t T5Display::rightAlignedTextOriginX(
    const String& text,
    int32_t rightEdge,
    MnemosFontRole role,
    uint8_t scale) const {

    const uint8_t safeScale =
        scale == 0
            ? 1
            : scale;

    int32_t left = 0;
    int32_t right = 0;

    if (
        !mnemosFontTextBounds(
            text,
            role,
            left,
            right)
    ) {
        right =
            textWidth(
                text,
                role);
    }

    return
        rightEdge -
        right *
            safeScale;
}

String T5Display::fitTextToWidth(
    const String& text,
    int32_t maxWidth,
    MnemosFontRole role) const {

    if (maxWidth <= 0) {
        return "";
    }

    if (
        textWidth(
            text,
            role) <=
        maxWidth
    ) {
        return text;
    }

    const String suffix =
        "...";

    const int32_t suffixWidth =
        textWidth(
            suffix,
            role);

    if (suffixWidth > maxWidth) {
        return "";
    }

    String out =
        text;

    while (
        out.length() > 0 &&
        textWidth(
            out,
            role) +
                suffixWidth >
            maxWidth
    ) {
        int32_t index =
            static_cast<int32_t>(
                out.length()) -
            1;

        while (
            index > 0 &&
            (
                static_cast<uint8_t>(
                    out[
                        static_cast<
                            unsigned int>(
                            index)]) &
                0xC0U
            ) ==
                0x80U
        ) {
            --index;
        }

        out.remove(
            static_cast<
                unsigned int>(
                index));
    }

    return
        out +
        suffix;
}

void T5Display::drawCenteredTextInRect(
    const String& text,
    int32_t x,
    int32_t y,
    int32_t w,
    int32_t h,
    MnemosFontRole role,
    uint8_t color,
    uint8_t scale) {

    drawText(
        text,
        centeredTextOriginX(
            text,
            x +
                w / 2,
            role,
            scale),
        centeredTextBaselineY(
            text,
            y +
                h / 2,
            role,
            scale),
        role,
        color,
        scale);
}

int32_t T5Display::drawWrapped(
    const String& text,
    int32_t x,
    int32_t y,
    int32_t maxWidth,
    int32_t lineHeight,
    uint8_t maxLines,
    MnemosFontRole role,
    uint8_t color) {

    String line;
    String word;
    uint8_t lines = 0;

    auto flushLine =
        [&]() {

        if (
            line.length() == 0 ||
            lines >= maxLines
        ) {
            return;
        }

        drawText(
            line,
            x,
            y +
                static_cast<int32_t>(
                    lines) *
                lineHeight,
            role,
            color);

        line = "";
        ++lines;
    };

    for (
        size_t i = 0;
        i <= text.length();
        ++i
    ) {
        const char c =
            i < text.length()
                ? text[i]
                : ' ';

        if (
            c != ' ' &&
            c != '\n'
        ) {
            word += c;
            continue;
        }

        if (word.length() > 0) {
            const String candidate =
                line.length() > 0
                    ? line +
                        " " +
                        word
                    : word;

            if (
                line.length() > 0 &&
                textWidth(
                    candidate,
                    role) >
                    maxWidth
            ) {
                flushLine();
            }

            if (
                lines >=
                maxLines
            ) {
                break;
            }

            if (
                line.length() > 0
            ) {
                line += ' ';
            }

            line += word;
            word = "";
        }

        if (c == '\n') {
            flushLine();
        }

        if (
            lines >=
            maxLines
        ) {
            break;
        }
    }

    if (
        line.length() > 0 &&
        lines < maxLines
    ) {
        flushLine();
    }

    return
        y +
        static_cast<int32_t>(
            lines) *
        lineHeight;
}

void T5Display::refreshFull() {
    if (
        !framebuffer_ ||
        !physicalFramebuffer_
    ) {
        return;
    }

    constexpr size_t PHYSICAL_BYTES =
        static_cast<size_t>(
            EPD_WIDTH) *
        static_cast<size_t>(
            EPD_HEIGHT) /
        2U;

    std::memset(
        physicalFramebuffer_,
        WHITE,
        PHYSICAL_BYTES);

    const int32_t width =
        logicalWidth();

    const int32_t height =
        logicalHeight();

    for (
        int32_t y = 0;
        y < height;
        ++y
    ) {
        const uint8_t* row =
            framebuffer_ +
            static_cast<size_t>(y) *
            static_cast<size_t>(
                width);

        for (
            int32_t x = 0;
            x < width;
            ++x
        ) {
            const uint8_t color =
                row[x];

            if (color == WHITE) {
                continue;
            }

            int32_t panelX =
                x;

            int32_t panelY =
                y;

            if (portrait()) {
                panelX =
                    EPD_WIDTH -
                    y -
                    1;

                panelY =
                    x;
            }

            epd_draw_pixel(
                panelX,
                panelY,
                color,
                physicalFramebuffer_);
        }
    }

    ensurePower();

    epd_clear();

    epd_draw_grayscale_image(
        epd_full_screen(),
        physicalFramebuffer_);

    if (
        !Config::
            KEEP_EPD_AUX_POWER_WHILE_AWAKE
    ) {
        epd_poweroff();
        powerOn_ = false;
    }
}

void T5Display::drawHomeIcon(
    int32_t x,
    int32_t y) {

    drawLine(x + 2, y + 16, x + 18, y + 2, BLACK);
    drawLine(x + 18, y + 2, x + 34, y + 16, BLACK);
    drawRect(x + 7, y + 15, 23, 21, BLACK);
    drawRect(x + 16, y + 24, 7, 12, DARK_GRAY);
}

void T5Display::drawMenuIcon(
    int32_t x,
    int32_t y) {

    for (
        int32_t i = 0;
        i < 3;
        ++i
    ) {
        drawLine(
            x,
            y + i * 10,
            x + 28,
            y + i * 10,
            BLACK);
    }
}

void T5Display::drawRotateIcon(
    int32_t x,
    int32_t y) {

    drawRect(
        x + 5,
        y + 5,
        28,
        28,
        DARK_GRAY);

    drawLine(
        x + 4,
        y + 5,
        x + 15,
        y,
        BLACK);

    drawLine(
        x + 4,
        y + 5,
        x + 9,
        y + 16,
        BLACK);
}

void T5Display::drawAbortIcon(
    int32_t x,
    int32_t y) {

    drawLine(
        x + 5,
        y + 5,
        x + 33,
        y + 33,
        BLACK);

    drawLine(
        x + 33,
        y + 5,
        x + 5,
        y + 33,
        BLACK);
}

void T5Display::drawSystemBar(
    const String& title,
    bool showMenu,
    bool showAbort,
    const String& rightMeta,
    bool showHome,
    bool showContext) {

    const int32_t barH =
        systemBarHeight();

    drawLine(
        0,
        barH - 1,
        logicalWidth() - 1,
        barH - 1,
        MID_GRAY);

    const int32_t iconY =
        portrait()
            ? 24
            : 16;

    if (showHome) {
        drawHomeIcon(
            24,
            iconY + 1);
    }

    if (showMenu) {
        drawMenuIcon(
            showHome
                ? 88
                : 32,
            portrait()
                ? 31
                : 23);
    }

    drawCenteredTextInRect(
        "MNEMOS",
        0,
        0,
        logicalWidth(),
        barH - 1,
        MnemosFontRole::Title22,
        BLACK);

    const int32_t rotateX =
        portrait()
            ? 401
            : 821;

    const int32_t abortX =
        portrait()
            ? 480
            : 900;

    drawRotateIcon(
        rotateX,
        iconY);

    if (showAbort) {
        drawAbortIcon(
            abortX,
            iconY);
    }

    if (!showContext) {
        return;
    }

    String statusMeta =
        rightMeta;

    if (batteryAvailable_) {
        if (statusMeta.length() > 0) {
            statusMeta += " · ";
        }

        statusMeta +=
            String(
                batteryPercent_) +
            "%";
    }

    const int32_t rowY =
        barH +
        (
            portrait()
                ? 8
                : 6
        );

    const int32_t rowH =
        portrait()
            ? 48
            : 42;

    const int32_t metaW =
        statusMeta.length() > 0
            ? (
                  portrait()
                      ? 160
                      : 220
              )
            : 0;

    const int32_t gap =
        metaW > 0
            ? 24
            : 0;

    const int32_t titleW =
        logicalWidth() -
        2 * MARGIN -
        metaW -
        gap;

    if (
        title.length() > 0 &&
        titleW > 0
    ) {
        const String fittedTitle =
            fitTextToWidth(
                title,
                titleW,
                MnemosFontRole::Title22);

        drawText(
            fittedTitle,
            MARGIN,
            centeredTextBaselineY(
                fittedTitle,
                rowY +
                    rowH / 2,
                MnemosFontRole::Title22),
            MnemosFontRole::Title22,
            BLACK);
    }

    if (
        statusMeta.length() > 0 &&
        metaW > 0
    ) {
        const String fittedMeta =
            fitTextToWidth(
                statusMeta,
                metaW,
                MnemosFontRole::Meta14);

        drawText(
            fittedMeta,
            rightAlignedTextOriginX(
                fittedMeta,
                logicalWidth() -
                    MARGIN,
                MnemosFontRole::Meta14),
            centeredTextBaselineY(
                fittedMeta,
                rowY +
                    rowH / 2,
                MnemosFontRole::Meta14),
            MnemosFontRole::Meta14,
            DARK_GRAY);
    }
}




void T5Display::drawContextStrip(
    const String& title,
    const String& meta) {

    drawText(
        shortText(
            title,
            portrait()
                ? 32
                : 56),
        MARGIN,
        HmiLayout::navTitleBaseline(
            portrait()),
        MnemosFontRole::Title22,
        BLACK);

    String status =
        meta;

    if (batteryAvailable_) {
        if (status.length() > 0) {
            status += " · ";
        }

        status +=
            String(
                batteryPercent_) +
            "%";
    }

    if (status.length() > 0) {
        drawText(
            shortText(
                status,
                portrait()
                    ? 34
                    : 72),
            MARGIN,
            HmiLayout::navMetaBaseline(
                portrait()),
            MnemosFontRole::Meta14,
            DARK_GRAY);
    }

    drawLine(
        MARGIN,
        HmiLayout::navContextBottom(
            portrait()) -
            1,
        logicalWidth() -
            MARGIN,
        HmiLayout::navContextBottom(
            portrait()) -
            1,
        LIGHT_GRAY);
}


void T5Display::drawPrimaryButton(
    const String& label) {

    const HmiLayout::Rect zone =
        HmiLayout::actionZone(
            portrait());

    const HmiLayout::Rect button =
        HmiLayout::actionVisualRect(
            portrait());

    drawLine(
        0,
        zone.y,
        logicalWidth() - 1,
        zone.y,
        MID_GRAY);

    fillRect(
        button.x,
        button.y,
        button.w,
        button.h,
        LIGHT_GRAY);

    drawRect(
        button.x,
        button.y,
        button.w,
        button.h,
        DARK_GRAY);

    const MnemosFontRole role =
        portrait()
            ? MnemosFontRole::Title22
            : MnemosFontRole::Body18;

    drawCenteredTextInRect(
        label,
        button.x,
        button.y,
        button.w,
        button.h,
        role,
        BLACK);
}




void T5Display::drawPrimarySplit(
    const String& left,
    const String& right,
    bool emphasizeLeft) {

    const HmiLayout::Rect zone =
        HmiLayout::actionZone(
            portrait());

    const HmiLayout::Rect visual =
        HmiLayout::actionVisualRect(
            portrait());

    drawLine(
        0,
        zone.y,
        logicalWidth() - 1,
        zone.y,
        MID_GRAY);

    const int32_t gap = 24;

    const int32_t w =
        (
            visual.w -
            gap
        ) /
        2;

    const int32_t rightX =
        visual.x +
        w +
        gap;

    fillRect(
        visual.x,
        visual.y,
        w,
        visual.h,
        emphasizeLeft
            ? WHITE
            : LIGHT_GRAY);

    drawRect(
        visual.x,
        visual.y,
        w,
        visual.h,
        DARK_GRAY);

    if (emphasizeLeft) {
        drawRect(
            visual.x + 4,
            visual.y + 4,
            w - 8,
            visual.h - 8,
            BLACK);
    }

    fillRect(
        rightX,
        visual.y,
        w,
        visual.h,
        LIGHT_GRAY);

    drawRect(
        rightX,
        visual.y,
        w,
        visual.h,
        DARK_GRAY);

    const MnemosFontRole role =
        portrait()
            ? MnemosFontRole::Body18
            : MnemosFontRole::Meta14;

    drawCenteredTextInRect(
        fitTextToWidth(
            left,
            w - 20,
            role),
        visual.x,
        visual.y,
        w,
        visual.h,
        role,
        BLACK);

    drawCenteredTextInRect(
        fitTextToWidth(
            right,
            w - 20,
            role),
        rightX,
        visual.y,
        w,
        visual.h,
        role,
        BLACK);
}




void T5Display::drawPrimaryTriple(
    const String& left,
    const String& middle,
    const String& right) {

    const HmiLayout::Rect zone =
        HmiLayout::actionZone(
            portrait());

    const HmiLayout::Rect visual =
        HmiLayout::actionVisualRect(
            portrait());

    drawLine(
        0,
        zone.y,
        logicalWidth() - 1,
        zone.y,
        MID_GRAY);

    const int32_t gap =
        portrait()
            ? 12
            : 16;

    const int32_t w =
        (
            visual.w -
            2 * gap
        ) /
        3;

    const String labels[3] = {
        left,
        middle,
        right
    };

    for (
        uint8_t i = 0;
        i < 3;
        ++i
    ) {
        const int32_t bx =
            visual.x +
            i *
                (
                    w +
                    gap
                );

        fillRect(
            bx,
            visual.y,
            w,
            visual.h,
            LIGHT_GRAY);

        drawRect(
            bx,
            visual.y,
            w,
            visual.h,
            DARK_GRAY);

        const String fitted =
            fitTextToWidth(
                labels[i],
                w - 16,
                MnemosFontRole::Meta14);

        drawCenteredTextInRect(
            fitted,
            bx,
            visual.y,
            w,
            visual.h,
            MnemosFontRole::Meta14,
            BLACK);
    }
}




void T5Display::drawChoiceCard(
    uint8_t number,
    const String& label,
    int32_t x,
    int32_t y,
    int32_t w,
    int32_t h,
    bool selected,
    char marker) {

    fillRect(
        x,
        y,
        w,
        h,
        selected
            ? BLACK
            : LIGHT_GRAY);

    drawRect(
        x,
        y,
        w,
        h,
        selected
            ? BLACK
            : DARK_GRAY);

    if (selected) {
        drawRect(
            x + 4,
            y + 4,
            w - 8,
            h - 8,
            WHITE);
    }

    const uint8_t textColor =
        selected
            ? WHITE
            : BLACK;

    String prefix;

    if (marker != '\0') {
        prefix += marker;
        prefix += " ";
    }

    if (number > 0) {
        prefix += String(number);
        prefix += "  ";
    }

    const String content =
        fitTextToWidth(
            prefix +
                label,
            std::max<int32_t>(
                0,
                w - 44),
            MnemosFontRole::Body18);

    drawText(
        content,
        x + 22,
        centeredTextBaselineY(
            content,
            y +
                h / 2,
            MnemosFontRole::Body18),
        MnemosFontRole::Body18,
        textColor);
}


void T5Display::drawAgendaBar(
    const String& label,
    uint16_t value,
    uint16_t maximum,
    int32_t x,
    int32_t y,
    int32_t w) {

    const int32_t labelW =
        portrait()
            ? 110
            : 120;

    const int32_t valueW =
        34;

    const int32_t barX =
        x +
        labelW;

    const int32_t barW =
        w -
        labelW -
        valueW;

    const int32_t trackY =
        y + 4;

    const int32_t trackH =
        20;

    const int32_t centerY =
        trackY +
        trackH / 2;

    drawText(
        fitTextToWidth(
            label,
            labelW - 10,
            MnemosFontRole::Meta14),
        x,
        centeredTextBaselineY(
            label,
            centerY,
            MnemosFontRole::Meta14),
        MnemosFontRole::Meta14,
        DARK_GRAY);

    fillRect(
        barX,
        trackY,
        barW,
        trackH,
        LIGHT_GRAY);

    if (
        maximum > 0 &&
        value > 0
    ) {
        const int32_t fill =
            std::max<int32_t>(
                2,
                static_cast<int32_t>(
                    value) *
                    barW /
                    maximum);

        fillRect(
            barX,
            trackY,
            fill,
            trackH,
            BLACK);
    }

    const String valueText =
        String(value);

    drawText(
        valueText,
        barX +
            barW +
            12,
        centeredTextBaselineY(
            valueText,
            centerY,
            MnemosFontRole::Meta14),
        MnemosFontRole::Meta14,
        BLACK);
}


void T5Display::drawCenteredHanzi(
    const String& text,
    int32_t centerX,
    int32_t baselineY,
    uint8_t scale) {

    drawCenteredText(
        text,
        centerX,
        baselineY,
        MnemosFontRole::Title22,
        BLACK,
        scale);
}


void T5Display::drawQr(
    const String& payload,
    int32_t originX,
    int32_t originY,
    int scale) {

    constexpr uint8_t QR_VERSION =
        8;

    const uint16_t size =
        qrcode_getBufferSize(
            QR_VERSION);

    std::unique_ptr<uint8_t[]> data(
        new uint8_t[size]);

    QRCode qr;

    if (
        qrcode_initText(
            &qr,
            data.get(),
            QR_VERSION,
            ECC_LOW,
            payload.c_str())
        != 0
    ) {
        drawText(
            "Falha ao gerar QR",
            originX,
            originY + 40,
            MnemosFontRole::Body18,
            BLACK);

        return;
    }

    const int quiet =
        2;

    const int pixels =
        (
            qr.size +
            quiet * 2
        ) *
        scale;

    fillRect(
        originX,
        originY,
        pixels,
        pixels,
        WHITE);

    drawRect(
        originX,
        originY,
        pixels,
        pixels,
        MID_GRAY);

    for (
        uint8_t yy = 0;
        yy < qr.size;
        ++yy
    ) {
        for (
            uint8_t xx = 0;
            xx < qr.size;
            ++xx
        ) {
            if (
                !qrcode_getModule(
                    &qr,
                    xx,
                    yy)
            ) {
                continue;
            }

            fillRect(
                originX +
                    (
                        xx +
                        quiet
                    ) *
                    scale,
                originY +
                    (
                        yy +
                        quiet
                    ) *
                    scale,
                scale,
                scale,
                BLACK);
        }
    }
}

void T5Display::showBoot(
    const String& message) {

    clearBuffer();

    if (portrait()) {
        drawCenteredTextInRect(
            "MNEMOS",
            MARGIN,
            275,
            logicalWidth() -
                2 * MARGIN,
            120,
            MnemosFontRole::Title22,
            BLACK,
            2);

        drawCenteredTextInRect(
            "estudo sem distrações",
            MARGIN,
            400,
            logicalWidth() -
                2 * MARGIN,
            58,
            MnemosFontRole::Body18,
            DARK_GRAY);

        drawCenteredTextInRect(
            fitTextToWidth(
                message,
                logicalWidth() -
                    2 * MARGIN,
                MnemosFontRole::Meta14),
            MARGIN,
            478,
            logicalWidth() -
                2 * MARGIN,
            70,
            MnemosFontRole::Meta14,
            DARK_GRAY);
    } else {
        drawCenteredTextInRect(
            "MNEMOS",
            MARGIN,
            150,
            logicalWidth() -
                2 * MARGIN,
            120,
            MnemosFontRole::Title22,
            BLACK,
            2);

        drawCenteredTextInRect(
            "estudo sem distrações",
            MARGIN,
            270,
            logicalWidth() -
                2 * MARGIN,
            54,
            MnemosFontRole::Body18,
            DARK_GRAY);

        drawCenteredTextInRect(
            fitTextToWidth(
                message,
                logicalWidth() -
                    2 * MARGIN,
                MnemosFontRole::Meta14),
            MARGIN,
            336,
            logicalWidth() -
                2 * MARGIN,
            54,
            MnemosFontRole::Meta14,
            DARK_GRAY);
    }

    refreshFull();
}



void T5Display::showTouchFeedback(
    int32_t x,
    int32_t y,
    int32_t w,
    int32_t h) {

    if (w <= 0 || h <= 0) {
        return;
    }

    Rect_t area{};

    if (portrait()) {
        area.x = EPD_WIDTH - (y + h);
        area.y = x;
        area.width = h;
        area.height = w;
    } else {
        area.x = x;
        area.y = y;
        area.width = w;
        area.height = h;
    }

    if (area.x < 0) {
        area.width += area.x;
        area.x = 0;
    }

    if (area.y < 0) {
        area.height += area.y;
        area.y = 0;
    }

    if (area.x + area.width > EPD_WIDTH) {
        area.width = EPD_WIDTH - area.x;
    }

    if (area.y + area.height > EPD_HEIGHT) {
        area.height = EPD_HEIGHT - area.y;
    }

    if (area.width <= 0 || area.height <= 0) {
        return;
    }

    ensurePower();
    epd_push_pixels(area, 20, 0);
}

void T5Display::showTouchMissing() {
    clearBuffer();

    drawSystemBar(
        "TOUCH",
        false,
        false,
        "entrada indisponível");

    drawWrapped(
        "GT911 não encontrado. "
        "O terminal continuará tentando restabelecer "
        "o controlador de toque.",
        MARGIN,
        portrait()
            ? 200
            : 150,
        logicalWidth() -
            2 * MARGIN,
        34,
        5,
        MnemosFontRole::Body18,
        BLACK);

    drawText(
        "I2C SDA 18 · SCL 17 · IRQ 47",
        MARGIN,
        portrait()
            ? 430
            : 330,
        MnemosFontRole::Meta14,
        DARK_GRAY);

    refreshFull();
}

void T5Display::showHome(
    const WeeklyPlanDay* days,
    uint8_t dayCount,
    bool trustedClock,
    bool canResume) {

    clearBuffer();

    drawSystemBar(
        "",
        true,
        false,
        "",
        false,
        false);

    drawContextStrip(
        "Agenda semanal",
        trustedClock
            ? ""
            : "hora aproximada");

    const uint8_t count =
        std::min<uint8_t>(
            dayCount,
            7);

    if (portrait()) {
        for (
            uint8_t i = 0;
            i < count;
            ++i
        ) {
            const int32_t y =
                HmiLayout::
                    homePortraitBaseline(i);

            if (days[i].today) {
                fillRect(
                    MARGIN,
                    y - 28,
                    logicalWidth() -
                        2 * MARGIN,
                    66,
                    LIGHT_GRAY);
            }

            drawText(
                days[i].label,
                MARGIN + 12,
                y,
                MnemosFontRole::Body18,
                BLACK);

            drawText(
                String(
                    days[i].cards),
                190,
                y,
                MnemosFontRole::Title22,
                BLACK);

            drawText(
                days[i].cards > 0
                    ? shortText(
                          days[i].decks,
                          24)
                    : "Livre",
                250,
                y,
                MnemosFontRole::Meta14,
                days[i].cards > 0
                    ? DARK_GRAY
                    : MID_GRAY);
        }
    } else {
        for (
            uint8_t i = 0;
            i < count;
            ++i
        ) {
            const HmiLayout::Rect card =
                HmiLayout::
                    homeLandscapeCard(i);

            fillRect(
                card.x,
                card.y,
                card.w,
                card.h,
                days[i].today
                    ? LIGHT_GRAY
                    : WHITE);

            drawRect(
                card.x,
                card.y,
                card.w,
                card.h,
                MID_GRAY);

            // Same card geometry as 6.4.1, with more coherent baselines.
            const int32_t primaryBaseline =
                card.y + 29;

            drawText(
                days[i].label,
                card.x + 16,
                primaryBaseline,
                MnemosFontRole::Body18,
                BLACK);

            drawText(
                String(
                    days[i].cards),
                card.x + 150,
                primaryBaseline + 2,
                MnemosFontRole::Title22,
                BLACK);

            drawText(
                days[i].cards > 0
                    ? shortText(
                          days[i].decks,
                          22)
                    : "Livre",
                card.x + 205,
                primaryBaseline,
                MnemosFontRole::Meta14,
                days[i].cards > 0
                    ? DARK_GRAY
                    : MID_GRAY);
        }
    }

    drawPrimaryButton(
        canResume
            ? "Retomar sessão"
            : "Estudar agora");

    refreshFull();
}

void T5Display::showMainMenu() {
    clearBuffer();

    drawSystemBar(
        "",
        true,
        false,
        "",
        true,
        false);

    drawContextStrip(
        "Menu");

    const String labels[5] = {
        "Decks",
        "Agenda",
        "Sincronização",
        "Conexão",
        "Armazenamento"
    };

    for (
        uint8_t i = 0;
        i < 5;
        ++i
    ) {
        const HmiLayout::Rect card =
            HmiLayout::menuCard(
                portrait(),
                i);

        fillRect(
            card.x,
            card.y,
            card.w,
            card.h,
            LIGHT_GRAY);

        drawRect(
            card.x,
            card.y,
            card.w,
            card.h,
            MID_GRAY);

        const MnemosFontRole role =
            portrait()
                ? MnemosFontRole::Title22
                : MnemosFontRole::Body18;

        const String label =
            portrait()
                ? labels[i]
                : shortText(
                      labels[i],
                      18);

        drawCenteredTextInRect(
            fitTextToWidth(
                label,
                card.w - 24,
                role),
            card.x,
            card.y,
            card.w,
            card.h,
            role,
            BLACK);
    }

    drawPrimaryButton(
        "Voltar à agenda");

    refreshFull();
}


void T5Display::showDecks(
    const DeckSummary* decks,
    size_t count,
    bool anySelected,
    bool canResume) {

    clearBuffer();

    drawSystemBar(
        "",
        true,
        false,
        "",
        true,
        false);

    drawContextStrip(
        "Decks",
        anySelected
            ? "filtro ativo"
            : "todos");

    const HmiLayout::Rect allCard =
        HmiLayout::deckAllCard(
            portrait());

    drawChoiceCard(
        0,
        "Todos os decks",
        allCard.x,
        allCard.y,
        allCard.w,
        allCard.h,
        !anySelected,
        '\0');

    const size_t visible =
        std::min<size_t>(
            count,
            5);

    for (
        size_t i = 0;
        i < visible;
        ++i
    ) {
        const HmiLayout::Rect card =
            HmiLayout::deckCard(
                portrait(),
                static_cast<uint8_t>(
                    i));

        drawChoiceCard(
            static_cast<uint8_t>(
                i + 1),
            decks[i].name +
                " · " +
                String(
                    decks[i].dueCount) +
                (
                    portrait()
                        ? " agora"
                        : ""
                ),
            card.x,
            card.y,
            card.w,
            card.h,
            decks[i].selected,
            '\0');
    }

    drawPrimaryButton(
        canResume
            ? "Retomar sessão"
            : anySelected
                ? "Estudar seleção"
                : "Estudar todos");

    refreshFull();
}


void T5Display::showAgenda(
    uint16_t dueNow,
    uint16_t laterToday,
    uint16_t tomorrow,
    uint16_t next7Days,
    const String& nextReview) {

    clearBuffer();

    drawSystemBar(
        "",
        true,
        false,
        "",
        true,
        false);

    drawContextStrip(
        "Agenda",
        shortText(
            nextReview,
            28));

    const uint16_t maximum =
        std::max<uint16_t>(
            1,
            std::max(
                std::max(
                    dueNow,
                    laterToday),
                std::max(
                    tomorrow,
                    next7Days)));

    if (portrait()) {
        drawAgendaBar(
            "Agora",
            dueNow,
            maximum,
            MARGIN,
            210,
            logicalWidth() -
                2 * MARGIN);

        drawAgendaBar(
            "Mais tarde",
            laterToday,
            maximum,
            MARGIN,
            312,
            logicalWidth() -
                2 * MARGIN);

        drawAgendaBar(
            "Amanhã",
            tomorrow,
            maximum,
            MARGIN,
            414,
            logicalWidth() -
                2 * MARGIN);

        drawAgendaBar(
            "Próx. 7 dias",
            next7Days,
            maximum,
            MARGIN,
            516,
            logicalWidth() -
                2 * MARGIN);
    } else {
        const String labels[4] = {
            "Agora",
            "Mais tarde",
            "Amanhã",
            "Próx. 7 dias"
        };

        const uint16_t values[4] = {
            dueNow,
            laterToday,
            tomorrow,
            next7Days
        };

        for (
            uint8_t i = 0;
            i < 4;
            ++i
        ) {
            const int32_t x =
                MARGIN +
                (
                    i % 2
                ) *
                    456;

            const int32_t y =
                150 +
                (
                    i / 2
                ) *
                    128;

            drawRect(
                x,
                y,
                408,
                112,
                MID_GRAY);

            drawAgendaBar(
                labels[i],
                values[i],
                maximum,
                x + 18,
                y + 42,
                372);
        }
    }

    drawPrimaryButton(
        "Voltar ao menu");

    refreshFull();
}

void T5Display::showSyncMenu(
    size_t total,
    uint16_t pendingReviews,
    bool wifiConnected) {

    clearBuffer();

    drawSystemBar(
        "Sincronização",
        true,
        false,
        wifiConnected
            ? "rede ativa"
            : "sem rede",
        true);

    drawText(
        String(total) +
            " cartões no terminal",
        MARGIN,
        portrait()
            ? 168
            : 124,
        MnemosFontRole::Body18,
        BLACK);

    drawText(
        String(
            pendingReviews) +
            " revisões aguardando envio",
        MARGIN,
        portrait()
            ? 212
            : 160,
        MnemosFontRole::Meta14,
        DARK_GRAY);

    if (portrait()) {
        drawChoiceCard(
            1,
            wifiConnected
                ? "Sincronizar com a conta"
                : "Conta indisponível sem rede",
            MARGIN,
            290,
            logicalWidth() -
                2 * MARGIN,
            112);

        drawChoiceCard(
            2,
            "Sincronizar com o celular",
            MARGIN,
            430,
            logicalWidth() -
                2 * MARGIN,
            112);
    } else {
        drawChoiceCard(
            1,
            wifiConnected
                ? "Sincronizar com a conta"
                : "Conta sem rede",
            MARGIN,
            220,
            408,
            130);

        drawChoiceCard(
            2,
            "Sincronizar com o celular",
            504,
            220,
            408,
            130);
    }

    drawPrimaryButton(
        "Voltar ao menu");

    refreshFull();
}

void T5Display::showConnectionMenu(
    bool wifiEnabled,
    bool wifiConnected,
    const String& ssid,
    size_t knownNetworks) {

    clearBuffer();

    const String state =
        wifiConnected
            ? "conectado"
            : wifiEnabled
                ? "sem conexão"
                : "Wi-Fi desligado";

    drawSystemBar(
        "",
        true,
        false,
        "",
        true,
        false);

    drawContextStrip(
        "Conexão",
        state);

    drawText(
        wifiConnected
            ? (
                  "Rede atual: " +
                  (
                      ssid.length()
                          ? ssid
                          : String(
                                "conectada")
                  )
              )
            : "Nenhuma rede ativa",
        MARGIN,
        portrait()
            ? 206
            : 170,
        MnemosFontRole::Body18,
        BLACK);

    drawText(
        String(
            knownNetworks) +
            " redes conhecidas",
        MARGIN,
        portrait()
            ? 236
            : 196,
        MnemosFontRole::Meta14,
        DARK_GRAY);

    const String labels[3] = {
        "Procurar redes",
        wifiEnabled
            ? "Desligar Wi-Fi"
            : "Ligar Wi-Fi",
        "Configurar pelo celular"
    };

    for (
        uint8_t i = 0;
        i < 3;
        ++i
    ) {
        const HmiLayout::Rect card =
            HmiLayout::connectionCard(
                portrait(),
                i);

        drawChoiceCard(
            i + 1,
            labels[i],
            card.x,
            card.y,
            card.w,
            card.h);
    }

    drawPrimaryButton(
        "Voltar ao menu");

    refreshFull();
}




void T5Display::showWifiScanning() {
    clearBuffer();

    drawSystemBar(
        "Redes Wi-Fi",
        false,
        false,
        "buscando",
        true);

    drawText(
        "Procurando redes próximas...",
        MARGIN,
        portrait() ? 250 : 190,
        MnemosFontRole::Title22,
        BLACK);

    drawWrapped(
        "A varredura pode levar alguns segundos. Redes já salvas serão identificadas automaticamente.",
        MARGIN,
        portrait() ? 320 : 250,
        logicalWidth() - 2 * MARGIN,
        32,
        4,
        MnemosFontRole::Body18,
        DARK_GRAY);

    refreshFull();
}


void T5Display::showWifiNetworks(
    const String* ssids,
    const int32_t* rssis,
    const uint8_t* flags,
    size_t count) {

    clearBuffer();

    drawSystemBar(
        "Redes Wi-Fi",
        false,
        false,
        String(count) + " encontradas",
        true);

    if (count == 0) {
        drawText(
            "Nenhuma rede encontrada.",
            MARGIN,
            portrait() ? 230 : 180,
            MnemosFontRole::Title22,
            BLACK);

        drawWrapped(
            "Verifique se o Wi-Fi está disponível e tente novamente.",
            MARGIN,
            portrait() ? 290 : 240,
            logicalWidth() - 2 * MARGIN,
            31,
            3,
            MnemosFontRole::Body18,
            DARK_GRAY);
    } else if (portrait()) {
        const size_t visible =
            std::min<size_t>(count, 6);

        for (size_t i = 0; i < visible; ++i) {
            const int32_t y =
                142 +
                static_cast<int32_t>(i) * 100;

            fillRect(
                MARGIN,
                y,
                logicalWidth() - 2 * MARGIN,
                86,
                LIGHT_GRAY);

            drawRect(
                MARGIN,
                y,
                logicalWidth() - 2 * MARGIN,
                86,
                MID_GRAY);

            drawText(
                shortText(ssids[i], 25),
                MARGIN + 20,
                y + 35,
                MnemosFontRole::Body18,
                BLACK);

            String meta =
                String(rssis[i]) +
                " dBm · ";

            if (flags[i] & 0x02) {
                meta += "corporativa";
            } else if (flags[i] & 0x01) {
                meta += "aberta";
            } else {
                meta += "segura";
            }

            if (flags[i] & 0x04) {
                meta += " · salva";
            }

            drawText(
                meta,
                MARGIN + 20,
                y + 67,
                MnemosFontRole::Meta14,
                DARK_GRAY);
        }
    } else {
        const size_t visible =
            std::min<size_t>(count, 6);

        for (size_t i = 0; i < visible; ++i) {
            const int32_t x =
                MARGIN +
                (i % 2) * 456;
            const int32_t y =
                112 +
                (i / 2) * 110;

            fillRect(x, y, 408, 96, LIGHT_GRAY);
            drawRect(x, y, 408, 96, MID_GRAY);

            drawText(
                shortText(ssids[i], 22),
                x + 18,
                y + 38,
                MnemosFontRole::Body18,
                BLACK);

            String meta =
                String(rssis[i]) +
                " dBm · ";

            if (flags[i] & 0x02) {
                meta += "corporativa";
            } else if (flags[i] & 0x01) {
                meta += "aberta";
            } else {
                meta += "segura";
            }

            if (flags[i] & 0x04) {
                meta += " · salva";
            }

            drawText(
                shortText(meta, 28),
                x + 18,
                y + 70,
                MnemosFontRole::Meta14,
                DARK_GRAY);
        }
    }

    drawPrimaryButton(
        "Buscar novamente");

    refreshFull();
}


void T5Display::showWifiPassword(
    const String& ssid,
    size_t passwordLength,
    WifiKeyboardPage page,
    const String& hint) {

    clearBuffer();

    drawSystemBar(
        "Senha Wi-Fi",
        false,
        false,
        wifiKeyboardPageLabel(page),
        true);

    drawText(
        shortText(ssid, portrait() ? 28 : 42),
        MARGIN,
        portrait() ? 142 : 110,
        MnemosFontRole::Title22,
        BLACK);

    String masked;
    const size_t visibleChars =
        std::min<size_t>(passwordLength, 32);

    for (size_t i = 0; i < visibleChars; ++i) {
        masked += '*';
    }

    if (passwordLength > visibleChars) {
        masked = "..." + masked;
    }

    drawRect(
        MARGIN,
        portrait() ? 170 : 128,
        logicalWidth() - 2 * MARGIN,
        portrait() ? 76 : 54,
        MID_GRAY);

    drawText(
        masked.length() ? masked : "Senha (8 a 63 caracteres)",
        MARGIN + 18,
        portrait() ? 219 : 164,
        masked.length()
            ? MnemosFontRole::Body18
            : MnemosFontRole::Meta14,
        masked.length()
            ? BLACK
            : DARK_GRAY);

    if (hint.length()) {
        drawText(
            shortText(hint, portrait() ? 42 : 72),
            MARGIN,
            portrait() ? 278 : 198,
            MnemosFontRole::Meta14,
            DARK_GRAY);
    }

    const char* chars =
        wifiKeyboardChars(page);
    const size_t keyCount =
        wifiKeyboardCharCount(page);

    const int32_t cols =
        portrait() ? 6 : 9;
    const int32_t gap =
        portrait() ? 6 : 8;
    const int32_t totalW =
        logicalWidth() - 2 * MARGIN;
    const int32_t keyW =
        (totalW - (cols - 1) * gap) / cols;
    const int32_t keyH =
        portrait() ? 58 : 46;
    const int32_t startY =
        portrait() ? 300 : 212;

    const int32_t rows =
        static_cast<int32_t>(
            (keyCount + cols - 1) / cols);

    for (size_t i = 0; i < keyCount; ++i) {
        const int32_t col =
            static_cast<int32_t>(i % cols);
        const int32_t row =
            static_cast<int32_t>(i / cols);
        const int32_t x =
            MARGIN + col * (keyW + gap);
        const int32_t y =
            startY + row * (keyH + gap);

        fillRect(x, y, keyW, keyH, LIGHT_GRAY);
        drawRect(x, y, keyW, keyH, MID_GRAY);

        String label;
        label += chars[i];
        drawCenteredTextInRect(
            label,
            x,
            y,
            keyW,
            keyH,
            MnemosFontRole::Body18,
            BLACK);
    }

    const int32_t controlY =
        startY + rows * (keyH + gap) + 8;
    const int32_t controlH =
        portrait() ? 66 : 46;
    const int32_t controlGap = 8;
    const int32_t usable =
        totalW - 3 * controlGap;
    const int32_t w1 = usable * 18 / 100;
    const int32_t w2 = usable * 18 / 100;
    const int32_t w3 = usable * 34 / 100;
    const int32_t w4 = usable - w1 - w2 - w3;
    const int32_t widths[4] = {w1, w2, w3, w4};
    const String labels[4] = {
        page == WifiKeyboardPage::Upper ? "abc" : "ABC",
        page == WifiKeyboardPage::Symbols ? "abc" : "#+=",
        "Espaço",
        "Apagar"
    };

    int32_t x = MARGIN;
    for (uint8_t i = 0; i < 4; ++i) {
        fillRect(x, controlY, widths[i], controlH, LIGHT_GRAY);
        drawRect(x, controlY, widths[i], controlH, MID_GRAY);
        drawCenteredTextInRect(
            fitTextToWidth(
                labels[i],
                widths[i] - 10,
                MnemosFontRole::Meta14),
            x,
            controlY,
            widths[i],
            controlH,
            MnemosFontRole::Meta14,
            BLACK);
        x += widths[i] + controlGap;
    }

    drawPrimarySplit(
        "Cancelar",
        "Conectar");

    refreshFull();
}


void T5Display::showWifiMessage(
    const String& title,
    const String& message,
    const String& primaryLabel) {

    clearBuffer();

    drawSystemBar(
        title,
        false,
        false,
        "Wi-Fi",
        true);

    drawWrapped(
        message,
        MARGIN,
        portrait() ? 220 : 170,
        logicalWidth() - 2 * MARGIN,
        portrait() ? 36 : 32,
        portrait() ? 8 : 5,
        MnemosFontRole::Body18,
        BLACK);

    if (primaryLabel.length()) {
        drawPrimaryButton(primaryLabel);
    }

    refreshFull();
}


void T5Display::showStorage(
    bool mounted,
    uint64_t cardSizeBytes,
    uint64_t usedBytes,
    const String* fileNames,
    const uint32_t* fileSizes,
    size_t fileCount,
    const String& status) {

    clearBuffer();

    drawSystemBar(
        "",
        false,
        false,
        "",
        true,
        false);

    drawContextStrip(
        "Armazenamento",
        mounted
            ? "microSD"
            : "sem cartão");

    if (!mounted) {
        drawText(
            "Nenhum cartão microSD montado.",
            MARGIN,
            portrait() ? 230 : 190,
            MnemosFontRole::Title22,
            BLACK);

        drawWrapped(
            "Insira um cartão FAT32. O Mnemos procura decks JSON em /mnemos/decks.",
            MARGIN,
            portrait() ? 300 : 250,
            logicalWidth() - 2 * MARGIN,
            34,
            5,
            MnemosFontRole::Body18,
            DARK_GRAY);

        if (status.length()) {
            drawText(
                shortText(
                    status,
                    52),
                MARGIN,
                portrait() ? 490 : 350,
                MnemosFontRole::Meta14,
                DARK_GRAY);
        }

        drawPrimaryButton(
            "Detectar cartão");

        refreshFull();
        return;
    }

    const uint64_t sizeMb =
        cardSizeBytes /
        1024ULL /
        1024ULL;

    const uint64_t usedMb =
        usedBytes /
        1024ULL /
        1024ULL;

    drawText(
        String(
            static_cast<unsigned long>(
                sizeMb)) +
            " MB · " +
            String(
                static_cast<unsigned long>(
                    usedMb)) +
            " MB usados",
        MARGIN,
        portrait() ? 198 : 158,
        MnemosFontRole::Meta14,
        BLACK);

    if (status.length()) {
        drawText(
            shortText(
                status,
                portrait()
                    ? 48
                    : 78),
            MARGIN,
            portrait() ? 226 : 184,
            MnemosFontRole::Meta14,
            DARK_GRAY);
    }

    if (fileCount == 0) {
        drawText(
            "Nenhum deck JSON em /mnemos/decks",
            MARGIN,
            portrait() ? 320 : 250,
            MnemosFontRole::Body18,
            BLACK);
    } else {
        const size_t visible =
            std::min<size_t>(
                fileCount,
                portrait()
                    ? 5
                    : 6);

        for (
            size_t i = 0;
            i < visible;
            ++i
        ) {
            const HmiLayout::Rect card =
                HmiLayout::storageFileCard(
                    portrait(),
                    static_cast<uint8_t>(
                        i));

            fillRect(
                card.x,
                card.y,
                card.w,
                card.h,
                LIGHT_GRAY);

            drawRect(
                card.x,
                card.y,
                card.w,
                card.h,
                MID_GRAY);

            drawText(
                shortText(
                    fileNames[i],
                    portrait()
                        ? 30
                        : 24),
                card.x + 16,
                card.y +
                    (
                        portrait()
                            ? 32
                            : 29
                    ),
                MnemosFontRole::Body18,
                BLACK);

            drawText(
                String(
                    fileSizes[i] /
                    1024U) +
                    (
                        portrait()
                            ? " KB · toque para importar"
                            : " KB · importar"
                    ),
                card.x + 16,
                card.y +
                    (
                        portrait()
                            ? 61
                            : 55
                    ),
                MnemosFontRole::Meta14,
                DARK_GRAY);
        }
    }

    drawPrimarySplit(
        "Atualizar",
        "Exportar");

    refreshFull();
}



void T5Display::showLocalLink(
    const String& qrPayload,
    const String& ssid,
    const String& password,
    bool provisioning) {

    clearBuffer();

    const int32_t qrScale =
        portrait()
            ? 6
            : 5;

    const int32_t qrX =
        portrait()
            ? 80
            : 70;

    const int32_t qrY =
        portrait()
            ? 100
            : 90;

    drawText(
        provisioning
            ? "Configurar terminal"
            : "Sincronizar celular",
        MARGIN,
        portrait()
            ? 60
            : 48,
        MnemosFontRole::Title22,
        BLACK);

    drawQr(
        qrPayload,
        qrX,
        qrY,
        qrScale);

    if (portrait()) {
        drawText(
            "Rede temporária",
            MARGIN,
            650,
            MnemosFontRole::Meta14,
            DARK_GRAY);

        drawText(
            ssid,
            MARGIN,
            688,
            MnemosFontRole::Body18,
            BLACK);

        drawText(
            "Senha",
            MARGIN,
            738,
            MnemosFontRole::Meta14,
            DARK_GRAY);

        drawText(
            password,
            MARGIN,
            776,
            MnemosFontRole::Body18,
            BLACK);
    } else {
        drawText(
            "Rede temporária",
            470,
            170,
            MnemosFontRole::Meta14,
            DARK_GRAY);

        drawText(
            ssid,
            470,
            210,
            MnemosFontRole::Body18,
            BLACK);

        drawText(
            "Senha",
            470,
            270,
            MnemosFontRole::Meta14,
            DARK_GRAY);

        drawText(
            password,
            470,
            310,
            MnemosFontRole::Body18,
            BLACK);
    }

    drawPrimaryButton(
        "Cancelar");

    refreshFull();
}

void T5Display::showQuestion(
    const CardDefinition& card,
    uint8_t position,
    uint8_t total) {

    clearBuffer();

    drawSystemBar(
        "Estudo",
        false,
        true,
        String(position + 1) +
            " de " +
            String(total),
        true);

    const bool mandarin =
        card.deckId ==
        "training-mandarin-100";

    const int32_t barH =
        systemBarHeight();

    const int32_t deckY =
        portrait()
            ? barH + 68
            : barH + 62;

    drawText(
        shortText(
            card.deck,
            portrait()
                ? 36
                : 30),
        MARGIN,
        deckY,
        MnemosFontRole::Meta14,
        DARK_GRAY);

    if (mandarin) {
        if (portrait()) {
            drawText(
                "Qual é a leitura e o significado?",
                MARGIN,
                245,
                MnemosFontRole::Body18,
                BLACK);

            drawCenteredHanzi(
                card.question,
                logicalWidth() / 2,
                510,
                4);
        } else {
            drawLine(
                468,
                150,
                468,
                438,
                LIGHT_GRAY);

            drawWrapped(
                "Qual é a leitura e o significado?",
                MARGIN,
                190,
                360,
                34,
                3,
                MnemosFontRole::Body18,
                BLACK);

            drawText(
                "Recupere primeiro; depois revele.",
                MARGIN,
                292,
                MnemosFontRole::Meta14,
                DARK_GRAY);

            drawCenteredHanzi(
                card.question,
                714,
                338,
                4);
        }

        drawPrimaryButton(
            "Ver resposta");

        refreshFull();
        return;
    }

    if (card.isObjective()) {
        if (portrait()) {
            drawWrapped(
                card.question,
                MARGIN,
                205,
                logicalWidth() -
                    2 * MARGIN,
                31,
                5,
                MnemosFontRole::Body18,
                BLACK);

            const uint8_t count =
                std::min<uint8_t>(
                    card.optionCount,
                    4);

            for (
                uint8_t i = 0;
                i < count;
                ++i
            ) {
                drawChoiceCard(
                    i + 1,
                    card.options[i],
                    MARGIN,
                    375 +
                        i * 96,
                    logicalWidth() -
                        2 * MARGIN,
                    86);
            }
        } else {
            drawWrapped(
                card.question,
                MARGIN,
                180,
                390,
                31,
                6,
                MnemosFontRole::Body18,
                BLACK);

            const uint8_t count =
                std::min<uint8_t>(
                    card.optionCount,
                    4);

            for (
                uint8_t i = 0;
                i < count;
                ++i
            ) {
                drawChoiceCard(
                    i + 1,
                    card.options[i],
                    504,
                    126 +
                        i * 80,
                    408,
                    72);
            }
        }
    } else {
        drawWrapped(
            card.question,
            MARGIN,
            portrait()
                ? 240
                : 190,
            portrait()
                ? logicalWidth() -
                      2 * MARGIN
                : 650,
            portrait()
                ? 34
                : 32,
            portrait()
                ? 8
                : 6,
            MnemosFontRole::Body18,
            BLACK);
    }

    drawPrimaryButton(
        "Ver resposta");

    refreshFull();
}



void T5Display::showSelfAssessment(
    const CardDefinition& card,
    uint8_t position,
    uint8_t total) {

    clearBuffer();

    drawSystemBar(
        "Conferir",
        false,
        true,
        String(position + 1) +
            " de " +
            String(total),
        true);

    const bool mandarin =
        card.deckId ==
        "training-mandarin-100";

    if (mandarin) {
        const int separator =
            card.answer.indexOf(
                " - ");

        const String pinyin =
            separator >= 0
                ? card.answer.substring(
                      0,
                      separator)
                : card.answer;

        const String meaning =
            separator >= 0
                ? card.answer.substring(
                      separator + 3)
                : "";

        if (portrait()) {
            drawCenteredHanzi(
                card.question,
                logicalWidth() / 2,
                315,
                3);

            drawText(
                "Pronúncia",
                MARGIN,
                420,
                MnemosFontRole::Meta14,
                DARK_GRAY);

            drawText(
                pinyin,
                MARGIN,
                468,
                MnemosFontRole::Title22,
                BLACK);

            drawText(
                "Significado",
                MARGIN,
                530,
                MnemosFontRole::Meta14,
                DARK_GRAY);

            drawWrapped(
                meaning,
                MARGIN,
                578,
                logicalWidth() -
                    2 * MARGIN,
                32,
                4,
                MnemosFontRole::Body18,
                BLACK);
        } else {
            drawLine(
                468,
                135,
                468,
                438,
                LIGHT_GRAY);

            drawCenteredHanzi(
                card.question,
                245,
                320,
                3);

            drawText(
                "Pronúncia",
                520,
                165,
                MnemosFontRole::Meta14,
                DARK_GRAY);

            drawText(
                pinyin,
                520,
                218,
                MnemosFontRole::Title22,
                BLACK);

            drawText(
                "Significado",
                520,
                282,
                MnemosFontRole::Meta14,
                DARK_GRAY);

            drawWrapped(
                meaning,
                520,
                330,
                385,
                31,
                3,
                MnemosFontRole::Body18,
                BLACK);
        }
    } else {
        if (portrait()) {
            drawText(
                "Pergunta",
                MARGIN,
                180,
                MnemosFontRole::Meta14,
                DARK_GRAY);

            drawWrapped(
                card.question,
                MARGIN,
                220,
                logicalWidth() -
                    2 * MARGIN,
                30,
                5,
                MnemosFontRole::Body18,
                DARK_GRAY);

            drawLine(
                MARGIN,
                410,
                logicalWidth() -
                    MARGIN,
                410,
                MID_GRAY);

            drawText(
                "Resposta de referência",
                MARGIN,
                460,
                MnemosFontRole::Meta14,
                DARK_GRAY);

            drawWrapped(
                card.answer,
                MARGIN,
                505,
                logicalWidth() -
                    2 * MARGIN,
                34,
                7,
                MnemosFontRole::Body18,
                BLACK);
        } else {
            drawText(
                "Pergunta",
                MARGIN,
                145,
                MnemosFontRole::Meta14,
                DARK_GRAY);

            drawWrapped(
                card.question,
                MARGIN,
                190,
                390,
                30,
                6,
                MnemosFontRole::Body18,
                DARK_GRAY);

            drawText(
                "Resposta de referência",
                504,
                145,
                MnemosFontRole::Meta14,
                DARK_GRAY);

            drawWrapped(
                card.answer,
                504,
                190,
                408,
                31,
                6,
                MnemosFontRole::Body18,
                BLACK);
        }
    }

    drawPrimarySplit(
        "Não recuperei",
        "Recuperei");

    refreshFull();
}


void T5Display::showObjectiveFeedback(
    const CardDefinition& card,
    uint8_t position,
    uint8_t total,
    int8_t selectedOptionIndex,
    Outcome outcome) {

    clearBuffer();

    drawSystemBar(
        "Resultado",
        false,
        true,
        String(position + 1) +
            " de " +
            String(total),
        true);

    drawText(
        outcome ==
                Outcome::Correct
            ? "Resposta correta"
            : "Resposta incorreta",
        MARGIN,
        portrait()
            ? 190
            : 138,
        MnemosFontRole::Title22,
        BLACK);

    if (portrait()) {
        drawText(
            "Sua escolha",
            MARGIN,
            270,
            MnemosFontRole::Meta14,
            DARK_GRAY);

        if (
            selectedOptionIndex >= 0 &&
            selectedOptionIndex <
                card.optionCount
        ) {
            drawChoiceCard(
                0,
                card.options[
                    selectedOptionIndex],
                MARGIN,
                300,
                logicalWidth() -
                    2 * MARGIN,
                120,
                false,
                selectedOptionIndex ==
                        card.correctOptionIndex
                    ? '#'
                    : 'X');
        }

        drawText(
            "Referência",
            MARGIN,
            490,
            MnemosFontRole::Meta14,
            DARK_GRAY);

        if (
            card.correctOptionIndex >= 0 &&
            card.correctOptionIndex <
                card.optionCount
        ) {
            drawChoiceCard(
                0,
                card.options[
                    card.correctOptionIndex],
                MARGIN,
                520,
                logicalWidth() -
                    2 * MARGIN,
                120,
                false,
                '#');
        }
    } else {
        drawText(
            "Sua escolha",
            MARGIN,
            205,
            MnemosFontRole::Meta14,
            DARK_GRAY);

        drawText(
            "Referência",
            504,
            205,
            MnemosFontRole::Meta14,
            DARK_GRAY);

        if (
            selectedOptionIndex >= 0 &&
            selectedOptionIndex <
                card.optionCount
        ) {
            drawChoiceCard(
                0,
                card.options[
                    selectedOptionIndex],
                MARGIN,
                235,
                408,
                130,
                false,
                selectedOptionIndex ==
                        card.correctOptionIndex
                    ? '#'
                    : 'X');
        }

        if (
            card.correctOptionIndex >= 0 &&
            card.correctOptionIndex <
                card.optionCount
        ) {
            drawChoiceCard(
                0,
                card.options[
                    card.correctOptionIndex],
                504,
                235,
                408,
                130,
                false,
                '#');
        }
    }

    drawPrimaryButton(
        "Continuar");

    refreshFull();
}

void T5Display::showEffort(
    uint8_t position,
    uint8_t total) {

    clearBuffer();

    drawSystemBar(
        "Esforço",
        false,
        true,
        String(position + 1) +
            " de " +
            String(total),
        true);

    drawWrapped(
        "Quanto esforço foi necessário "
        "para recuperar a resposta?",
        MARGIN,
        portrait()
            ? 250
            : 180,
        portrait()
            ? logicalWidth() -
                  2 * MARGIN
            : 720,
        portrait()
            ? 36
            : 32,
        4,
        MnemosFontRole::Title22,
        BLACK);

    drawText(
        "Avalie o processo de recuperação, não a importância do tema.",
        MARGIN,
        portrait()
            ? 430
            : 285,
        MnemosFontRole::Meta14,
        DARK_GRAY);

    drawPrimaryTriple(
        "Difícil",
        "Normal",
        "Fácil");

    refreshFull();
}

void T5Display::showSummary(
    const SessionStats& stats,
    uint16_t remainingDue,
    uint16_t remainingNew,
    const String& nextReview) {

    clearBuffer();

    drawSystemBar(
        stats.mode ==
                SessionMode::Practice
            ? "Prática concluída"
            : "Sessão concluída",
        false,
        false,
        "",
        true);

    if (portrait()) {
        drawText(
            String(
                stats.reviewed) +
                " cartões trabalhados",
            MARGIN,
            190,
            MnemosFontRole::Title22,
            BLACK);

        drawText(
            String(
                stats.correct) +
                " recuperados",
            MARGIN,
            260,
            MnemosFontRole::Body18,
            BLACK);

        drawText(
            String(
                stats.incorrect) +
                " para reforçar",
            MARGIN,
            315,
            MnemosFontRole::Body18,
            BLACK);

        drawText(
            "Próxima revisão",
            MARGIN,
            410,
            MnemosFontRole::Meta14,
            DARK_GRAY);

        drawText(
            nextReview.length()
                ? nextReview
                : "Sem revisão agendada",
            MARGIN,
            455,
            MnemosFontRole::Body18,
            BLACK);

        const uint16_t maximum =
            std::max<uint16_t>(
                1,
                std::max(
                    remainingDue,
                    remainingNew));

        drawAgendaBar(
            "Pendentes",
            remainingDue,
            maximum,
            MARGIN,
            560,
            logicalWidth() -
                2 * MARGIN);

        drawAgendaBar(
            "Novos",
            remainingNew,
            maximum,
            MARGIN,
            630,
            logicalWidth() -
                2 * MARGIN);
    } else {
        drawText(
            String(
                stats.reviewed) +
                " cartões trabalhados",
            MARGIN,
            150,
            MnemosFontRole::Title22,
            BLACK);

        drawText(
            String(
                stats.correct) +
                " recuperados",
            MARGIN,
            210,
            MnemosFontRole::Body18,
            BLACK);

        drawText(
            String(
                stats.incorrect) +
                " para reforçar",
            MARGIN,
            250,
            MnemosFontRole::Body18,
            BLACK);

        drawText(
            "Próxima revisão",
            504,
            150,
            MnemosFontRole::Meta14,
            DARK_GRAY);

        drawWrapped(
            nextReview.length()
                ? nextReview
                : "Sem revisão agendada",
            504,
            190,
            408,
            32,
            4,
            MnemosFontRole::Body18,
            BLACK);
    }

    drawPrimaryButton(
        "Continuar");

    refreshFull();
}

void T5Display::showAbortConfirm(
    uint16_t remainingInQueue) {

    clearBuffer();

    drawSystemBar(
        "Interromper sessão?",
        false,
        false);

    drawWrapped(
        "Os cartões já respondidos foram registrados. "
        "Os " +
            String(
                remainingInQueue) +
            " cartões restantes desta fila "
            "voltam a aguardar revisão.",
        MARGIN,
        portrait()
            ? 260
            : 175,
        logicalWidth() -
            2 * MARGIN,
        portrait()
            ? 38
            : 34,
        portrait()
            ? 8
            : 5,
        MnemosFontRole::Body18,
        BLACK);

    drawText(
        "A opção segura é continuar estudando.",
        MARGIN,
        portrait()
            ? 610
            : 350,
        MnemosFontRole::Meta14,
        DARK_GRAY);

    drawPrimarySplit(
        "Continuar estudando",
        "Interromper sessão",
        true);

    refreshFull();
}
