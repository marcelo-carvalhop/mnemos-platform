#include "t5_display.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>

#include "config.h"
#include "hmi_layout.h"
#include <epdiy.h>
#include <epd_highlevel.h>

#include <qrcode.h>

namespace {

constexpr uint8_t BLACK = 0x00;
constexpr uint8_t DARK_GRAY = 0x22;
constexpr uint8_t MID_GRAY = 0x55;
constexpr uint8_t LIGHT_GRAY = 0xAA;
constexpr uint8_t WHITE = 0xFF;

EpdiyHighlevelState gEpdState{};
bool gEpdReady = false;
uint32_t gRefreshCount = 0;
int gEpdTemperature = 20;

const char* refreshModeName(
    EpdDrawMode mode) {

    return
        mode == MODE_GC16
            ? "GC16"
            : "GL16";
}


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
            HmiLayout::PORTRAIT_WIDTH) *
        static_cast<size_t>(
            HmiLayout::PORTRAIT_HEIGHT);

    framebuffer_ =
        static_cast<uint8_t*>(
            ps_malloc(
                LOGICAL_BYTES));

    if (!framebuffer_) {
        Serial.println(
            "[display] falha ao alocar canvas logico");
        return false;
    }

    std::memset(
        framebuffer_,
        WHITE,
        LOGICAL_BYTES);

    Serial.println(
        "[display] inicializando H752-01 / ED047TC1");

    epd_init(
        &epd_board_v7,
        &ED047TC1,
        EPD_LUT_64K);

    epd_set_vcom(1560);

    /*
     * Não usamos a rotação interna do epdiy.
     * A conversão retrato->painel fica exclusivamente
     * em refreshFull().
     */
    epd_set_rotation(
        EPD_ROT_LANDSCAPE);

    gEpdState =
        epd_hl_init(
            EPD_BUILTIN_WAVEFORM);

    physicalFramebuffer_ =
        epd_hl_get_framebuffer(
            &gEpdState);

    if (!physicalFramebuffer_) {
        Serial.println(
            "[display] framebuffer epdiy indisponivel");
        return false;
    }

    gEpdReady = true;
    gRefreshCount = 0;
    gEpdTemperature = 20;

    orientation_ =
        DisplayOrientation::Portrait;

    /*
     * Um clear físico é feito somente no bring-up.
     * Trocas de tela posteriores usam o high-level
     * front/back do epdiy e não chamam epd_clear().
     */
    epd_poweron();
    epd_fullclear(
        &gEpdState,
        gEpdTemperature);
    epd_poweroff();

    powerOn_ = false;

    Serial.printf(
        "[display] T5S3 Pro pronto "
        "logical=%dx%d physical=%dx%d temp=%dC\n",
        HmiLayout::PORTRAIT_WIDTH,
        HmiLayout::PORTRAIT_HEIGHT,
        Config::DISPLAY_WIDTH,
        Config::DISPLAY_HEIGHT,
        gEpdTemperature);

    return true;
}



void T5Display::setBatteryStatus(
    bool available,
    uint8_t percent,
    bool charging) {

    batteryAvailable_ =
        available;

    batteryPercent_ =
        std::min<uint8_t>(
            100,
            percent);

    batteryCharging_ =
        available &&
        charging;
}


void T5Display::setNetworkStatus(
    bool enabled,
    bool connected) {

    networkEnabled_ =
        enabled;

    networkConnected_ =
        enabled &&
        connected;
}


void T5Display::deepClean() {
    if (!gEpdReady) {
        return;
    }

    Serial.println(
        "[display] deep-clean begin");

    ensurePower();

    constexpr int CLEAN_TIME = 12;

    /*
     * Sequência baseada no firmware de fábrica H752-01:
     * preto -> branco -> noop.
     */
    for (
        uint8_t i = 0;
        i < 10;
        ++i
    ) {
        epd_push_pixels(
            epd_full_screen(),
            CLEAN_TIME,
            0);
    }

    for (
        uint8_t i = 0;
        i < 10;
        ++i
    ) {
        epd_push_pixels(
            epd_full_screen(),
            CLEAN_TIME,
            1);
    }

    for (
        uint8_t i = 0;
        i < 2;
        ++i
    ) {
        epd_push_pixels(
            epd_full_screen(),
            CLEAN_TIME,
            2);
    }

    epd_fullclear(
        &gEpdState,
        gEpdTemperature);

    epd_poweroff();
    powerOn_ = false;

    gRefreshCount = 0;

    Serial.println(
        "[display] deep-clean end");
}



void T5Display::setOrientation(
    DisplayOrientation) {

    orientation_ =
        DisplayOrientation::Portrait;
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
        !gEpdReady ||
        !framebuffer_ ||
        !physicalFramebuffer_
    ) {
        Serial.println(
            "[display] refresh ignorado: estado invalido");
        return;
    }

    const uint32_t started =
        millis();

    const bool autoDeepClean =
        Config::EPD_AUTO_DEEP_CLEAN_INTERVAL > 0 &&
        gRefreshCount > 0 &&
        (
            gRefreshCount %
            Config::EPD_AUTO_DEEP_CLEAN_INTERVAL
        ) == 0;

    if (autoDeepClean) {
        Serial.printf(
            "[display] auto-deep-clean trigger refresh=%lu\n",
            static_cast<unsigned long>(
                gRefreshCount));

        /*
         * deepClean() executa exatamente a sequência física
         * preto -> branco -> noop -> GC16 e ressincroniza
         * o high-level framebuffer.
         */
        deepClean();
    }

    /*
     * Canvas lógico: 540 x 960, um byte por pixel.
     * Framebuffer epdiy: 960 x 540, 4 bpp.
     *
     * A orientação validada do produto é:
     *
     * physicalX = 959 - logicalY
     * physicalY = logicalX
     *
     * epd_draw_pixel() faz o empacotamento 4-bpp e
     * preserva exatamente os tokens 00/55/99/DD/FF.
     */
    epd_hl_set_all_white(
        &gEpdState);

    size_t inkPixels = 0;

    for (
        int32_t logicalY = 0;
        logicalY <
            HmiLayout::PORTRAIT_HEIGHT;
        ++logicalY
    ) {
        const uint8_t* row =
            framebuffer_ +
            static_cast<size_t>(
                logicalY) *
            static_cast<size_t>(
                HmiLayout::PORTRAIT_WIDTH);

        for (
            int32_t logicalX = 0;
            logicalX <
                HmiLayout::PORTRAIT_WIDTH;
            ++logicalX
        ) {
            const uint8_t color =
                row[logicalX];

            if (color == WHITE) {
                continue;
            }

            ++inkPixels;

            const int32_t physicalX =
                logicalY;

            const int32_t physicalY =
                Config::DISPLAY_HEIGHT -
                logicalX -
                1;

            epd_draw_pixel(
                physicalX,
                physicalY,
                color,
                physicalFramebuffer_);
        }
    }

    const uint32_t composed =
        millis();

    /*
     * GL16 é a atualização normal: grayscale,
     * sem o flash completo do GC16.
     *
     * GC16 é usado no primeiro redraw e
     * periodicamente para limpar ghosting.
     */
    EpdDrawMode mode = MODE_GC16;

    ensurePower();

    EpdDrawError result =
        epd_hl_update_screen(
            &gEpdState,
            mode,
            gEpdTemperature);

    if (
        result !=
            EPD_DRAW_SUCCESS &&
        mode != MODE_GC16
    ) {
        Serial.printf(
            "[display] GL16 falhou 0x%X; "
            "fallback GC16\n",
            static_cast<unsigned int>(
                result));

        mode = MODE_GC16;

        result =
            epd_hl_update_screen(
                &gEpdState,
                mode,
                gEpdTemperature);
    }

    if (
        !Config::
            KEEP_EPD_AUX_POWER_WHILE_AWAKE
    ) {
        epd_poweroff();
        powerOn_ = false;
    }

    ++gRefreshCount;

    const uint32_t finished =
        millis();

    Serial.printf(
        "[display] refresh mode=%s "
        "ink=%u compose=%lums epd=%lums total=%lums "
        "result=0x%X\n",
        refreshModeName(
            mode),
        static_cast<unsigned>(
            inkPixels),
        static_cast<unsigned long>(
            composed -
            started),
        static_cast<unsigned long>(
            finished -
            composed),
        static_cast<unsigned long>(
            finished -
            started),
        static_cast<unsigned int>(
            result));
}



void T5Display::drawHomeIcon(
    int32_t x,
    int32_t y) {

    // Roof: three parallel BLACK strokes.
    for (int32_t o = -1; o <= 1; ++o) {
        drawLine(
            x + 2,
            y + 16 + o,
            x + 18,
            y + 2 + o,
            BLACK);

        drawLine(
            x + 18,
            y + 2 + o,
            x + 34,
            y + 16 + o,
            BLACK);
    }

    // House body, 3 px outline.
    fillRect(
        x + 7,
        y + 15,
        3,
        22,
        BLACK);

    fillRect(
        x + 28,
        y + 15,
        3,
        22,
        BLACK);

    fillRect(
        x + 7,
        y + 34,
        24,
        3,
        BLACK);

    // Door.
    fillRect(
        x + 16,
        y + 25,
        7,
        12,
        BLACK);
}



void T5Display::drawMenuIcon(
    int32_t x,
    int32_t y) {

    for (
        int32_t i = 0;
        i < 3;
        ++i
    ) {
        fillRect(
            x,
            y + i * 10,
            30,
            4,
            BLACK);
    }
}





void T5Display::drawSyncIcon(
    int32_t x,
    int32_t y) {

    // Upper arrow -> right.
    fillRect(
        x + 2,
        y + 7,
        25,
        4,
        BLACK);

    for (
        int32_t o = 0;
        o < 3;
        ++o
    ) {
        drawLine(
            x + 27 - o,
            y + 9,
            x + 20 - o,
            y + 3,
            BLACK);

        drawLine(
            x + 27 - o,
            y + 9,
            x + 20 - o,
            y + 15,
            BLACK);
    }

    // Lower arrow -> left.
    fillRect(
        x + 2,
        y + 23,
        25,
        4,
        BLACK);

    for (
        int32_t o = 0;
        o < 3;
        ++o
    ) {
        drawLine(
            x + 2 + o,
            y + 25,
            x + 9 + o,
            y + 19,
            BLACK);

        drawLine(
            x + 2 + o,
            y + 25,
            x + 9 + o,
            y + 31,
            BLACK);
    }
}



void T5Display::drawRotateIcon(
    int32_t,
    int32_t) {

    // Orientação fixa em retrato no T5S3 Pro.
}



void T5Display::drawAbortIcon(
    int32_t x,
    int32_t y) {

    for (
        int32_t o = -1;
        o <= 1;
        ++o
    ) {
        drawLine(
            x + 5 + o,
            y + 5,
            x + 33 + o,
            y + 33,
            BLACK);

        drawLine(
            x + 33 + o,
            y + 5,
            x + 5 + o,
            y + 33,
            BLACK);
    }
}




void T5Display::drawBatteryIcon(
    int32_t x,
    int32_t y) {

    constexpr int32_t W = 31;
    constexpr int32_t H = 18;

    // 2 px BLACK outline.
    drawRect(
        x,
        y,
        W,
        H,
        BLACK);

    drawRect(
        x + 1,
        y + 1,
        W - 2,
        H - 2,
        BLACK);

    fillRect(
        x + W,
        y + 5,
        4,
        8,
        BLACK);

    if (!batteryAvailable_) {
        for (
            int32_t o = -1;
            o <= 1;
            ++o
        ) {
            drawLine(
                x + 4,
                y + 4 + o,
                x + W - 5,
                y + H - 5 + o,
                BLACK);
        }

        return;
    }

    const uint8_t segments =
        batteryPercent_ >= 76
            ? 4
            : batteryPercent_ >= 51
                ? 3
                : batteryPercent_ >= 26
                    ? 2
                    : batteryPercent_ >= 6
                        ? 1
                        : 0;

    constexpr int32_t SEG_W = 5;
    constexpr int32_t GAP = 2;

    for (
        uint8_t i = 0;
        i < 4;
        ++i
    ) {
        const int32_t sx =
            x +
            3 +
            i *
                (
                    SEG_W +
                    GAP
                );

        if (i < segments) {
            fillRect(
                sx,
                y + 4,
                SEG_W,
                H - 8,
                BLACK);
        } else {
            drawRect(
                sx,
                y + 4,
                SEG_W,
                H - 8,
                BLACK);
        }
    }

    if (batteryCharging_) {
        // BLACK '+' immediately left of the battery.
        fillRect(
            x - 8,
            y + 8,
            6,
            2,
            BLACK);

        fillRect(
            x - 6,
            y + 6,
            2,
            6,
            BLACK);
    }
}




void T5Display::drawNetworkIcon(
    int32_t x,
    int32_t y) {

    /*
     * All states are BLACK.
     * Connected = filled bars.
     * Offline = outlined bars.
     * Disabled = outlined bars + BLACK slash.
     */
    if (networkConnected_) {
        fillRect(
            x,
            y + 13,
            5,
            5,
            BLACK);

        fillRect(
            x + 8,
            y + 9,
            5,
            9,
            BLACK);

        fillRect(
            x + 16,
            y + 3,
            5,
            15,
            BLACK);
    } else {
        drawRect(
            x,
            y + 13,
            5,
            5,
            BLACK);

        drawRect(
            x + 8,
            y + 9,
            5,
            9,
            BLACK);

        drawRect(
            x + 16,
            y + 3,
            5,
            15,
            BLACK);
    }

    if (!networkEnabled_) {
        for (
            int32_t o = -1;
            o <= 1;
            ++o
        ) {
            drawLine(
                x - 2,
                y + 2 + o,
                x + 23,
                y + 19 + o,
                BLACK);
        }
    }
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
        BLACK);

    const int32_t iconY =
        portrait()
            ? 24
            : 16;

    if (showHome) {
        drawHomeIcon(
            18,
            iconY + 1);
    }

    if (showMenu) {
        drawMenuIcon(
            showHome
                ? 78
                : 32,
            portrait()
                ? 31
                : 23);

        /*
         * Mantém Sync fora da área central de MNEMOS.
         */
        drawSyncIcon(
            showHome
                ? 142
                : 102,
            portrait()
                ? 24
                : 16);
    }

    /*
     * MNEMOS possui uma caixa própria e não disputa espaço
     * com os ícones laterais.
     */
    if (portrait()) {
        drawCenteredTextInRect(
            "MNEMOS",
            205,
            0,
            140,
            barH - 1,
            MnemosFontRole::Title22,
            BLACK);
    } else {
        drawCenteredTextInRect(
            "MNEMOS",
            365,
            0,
            230,
            barH - 1,
            MnemosFontRole::Title22,
            BLACK);
    }

    if (portrait()) {
        drawNetworkIcon(
            390,
            31);

        drawBatteryIcon(
            430,
            31);

        if (showAbort) {
            drawAbortIcon(
                492,
                iconY);
        }
    } else {
        drawNetworkIcon(
            810,
            23);

        drawBatteryIcon(
            850,
            23);

        if (showAbort) {
            drawAbortIcon(
                912,
                iconY);
        }
    }

    if (!showContext) {
        return;
    }

    /*
     * Battery percentage was intentionally removed here.
     * Battery state now lives exclusively in the top icon.
     */
    const String statusMeta =
        rightMeta;

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

    /*
     * Battery percentage removed.
     * The top battery icon is the single battery status source.
     */
    const String status =
        meta;

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
        LIGHT_GRAY);

    // Primário: nível 0, máximo contraste.
    fillRect(
        button.x,
        button.y,
        button.w,
        button.h,
        BLACK);

    drawRect(
        button.x,
        button.y,
        button.w,
        button.h,
        BLACK);

    if (
        button.w > 8 &&
        button.h > 8
    ) {
        drawRect(
            button.x + 4,
            button.y + 4,
            button.w - 8,
            button.h - 8,
            DARK_GRAY);
    }

    const MnemosFontRole role =
        portrait()
            ? MnemosFontRole::Title22
            : MnemosFontRole::Body18;

    drawCenteredTextInRect(
        fitTextToWidth(
            label,
            button.w - 28,
            role),
        button.x,
        button.y,
        button.w,
        button.h,
        role,
        WHITE);
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
        LIGHT_GRAY);

    const int32_t gap = 24;

    const int32_t w =
        (
            visual.w -
            gap
        ) /
        2;

    const int32_t leftX =
        visual.x;

    const int32_t rightX =
        visual.x +
        w +
        gap;

    /*
     * Primário = 0.
     * Secundário = 2.
     * Ambos recebem texto branco.
     */
    const uint8_t leftFill =
        emphasizeLeft
            ? BLACK
            : DARK_GRAY;

    const uint8_t rightFill =
        emphasizeLeft
            ? DARK_GRAY
            : BLACK;

    fillRect(
        leftX,
        visual.y,
        w,
        visual.h,
        leftFill);

    drawRect(
        leftX,
        visual.y,
        w,
        visual.h,
        BLACK);

    fillRect(
        rightX,
        visual.y,
        w,
        visual.h,
        rightFill);

    drawRect(
        rightX,
        visual.y,
        w,
        visual.h,
        BLACK);

    const MnemosFontRole role =
        portrait()
            ? MnemosFontRole::Body18
            : MnemosFontRole::Meta14;

    drawCenteredTextInRect(
        fitTextToWidth(
            left,
            w - 24,
            role),
        leftX,
        visual.y,
        w,
        visual.h,
        role,
        WHITE);

    drawCenteredTextInRect(
        fitTextToWidth(
            right,
            w - 24,
            role),
        rightX,
        visual.y,
        w,
        visual.h,
        role,
        WHITE);
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
        LIGHT_GRAY);

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

    /*
     * Escolhas equivalentes:
     * nível 5 + texto branco.
     */
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
            MID_GRAY);

        drawRect(
            bx,
            visual.y,
            w,
            visual.h,
            BLACK);

        const String fitted =
            fitTextToWidth(
                labels[i],
                w - 20,
                MnemosFontRole::Meta14);

        drawCenteredTextInRect(
            fitted,
            bx,
            visual.y,
            w,
            visual.h,
            MnemosFontRole::Meta14,
            WHITE);
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

    /*
     * Padrão único de ação/card:
     *
     * normal       = BLACK + WHITE
     * selecionado  = DARK_GRAY + WHITE + borda interna
     *
     * Nenhum card interativo volta a usar fundo claro.
     */
    const uint8_t fillColor =
        selected
            ? DARK_GRAY
            : BLACK;

    fillRect(
        x,
        y,
        w,
        h,
        fillColor);

    drawRect(
        x,
        y,
        w,
        h,
        BLACK);

    if (
        selected &&
        w > 10 &&
        h > 10
    ) {
        drawRect(
            x + 5,
            y + 5,
            w - 10,
            h - 10,
            WHITE);
    }

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
        WHITE);
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
    int32_t,
    int32_t,
    int32_t,
    int32_t) {

    /*
     * Não usamos epd_push_pixels().
     *
     * Essa primitiva altera o painel sem atualizar o
     * front/back framebuffer do epdiy, gerando ghosting
     * e uma etapa bloqueante antes da tela seguinte.
     *
     * A ação é despachada imediatamente; a próxima tela
     * inicia seu update GL16 sem um redraw intermediário.
     */
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
        "I2C SDA 39 · SCL 40 · IRQ 3",
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

    const String labels[3] = {
        "Decks",
        "Conexão",
        "Configurações"
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
            0,
            labels[i],
            card.x,
            card.y,
            card.w,
            card.h,
            false,
            '\0');
    }

    drawPrimaryButton(
        "Voltar à agenda");

    refreshFull();
}






void T5Display::showSettings(
    const String& backlightLabel) {

    clearBuffer();
    drawSystemBar("", true, false, "", true, false);
    drawContextStrip("Configurações");

    const String labels[4] = {
        "Luz de fundo · " + backlightLabel,
        "Limpeza profunda",
        "Armazenamento",
        "Desligar dispositivo"
    };

    for (uint8_t i = 0; i < 4; ++i) {
        const HmiLayout::Rect card =
            HmiLayout::connectionCard(
                portrait(), i);

        drawChoiceCard(
            0, labels[i],
            card.x, card.y,
            card.w, card.h,
            false, '\0');
    }

    drawPrimaryButton("Voltar ao menu");
    refreshFull();
}





void T5Display::showPowerOff(
    bool automatic) {

    clearBuffer();

    drawCenteredTextInRect(
        "MNEMOS",
        0,
        portrait() ? 150 : 70,
        logicalWidth(),
        portrait() ? 100 : 70,
        MnemosFontRole::Title22,
        BLACK);

    drawCenteredTextInRect(
        "Dispositivo desligado",
        MARGIN,
        portrait() ? 360 : 200,
        logicalWidth() - 2 * MARGIN,
        portrait() ? 90 : 70,
        MnemosFontRole::Title22,
        BLACK);

    drawCenteredTextInRect(
        automatic
            ? "Desligado automaticamente por inatividade"
            : "Desligado pelo usuário",
        MARGIN,
        portrait() ? 470 : 280,
        logicalWidth() - 2 * MARGIN,
        portrait() ? 70 : 55,
        MnemosFontRole::Body18,
        DARK_GRAY);

    drawCenteredTextInRect(
        "Pressione BOOT para ligar",
        MARGIN,
        portrait() ? 610 : 355,
        logicalWidth() - 2 * MARGIN,
        portrait() ? 80 : 60,
        MnemosFontRole::Body18,
        BLACK);

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
                BLACK);

            drawRect(
                MARGIN,
                y,
                logicalWidth() - 2 * MARGIN,
                86,
                BLACK);

            drawText(
                shortText(ssids[i], 25),
                MARGIN + 20,
                y + 35,
                MnemosFontRole::Body18,
                WHITE);

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
                LIGHT_GRAY);
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

            fillRect(x, y, 408, 96, BLACK);
            drawRect(x, y, 408, 96, BLACK);

            drawText(
                shortText(ssids[i], 22),
                x + 18,
                y + 38,
                MnemosFontRole::Body18,
                WHITE);

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
                LIGHT_GRAY);
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

    /*
     * A barra superior fica apenas com navegação/status.
     * Título e SSID usam a faixa de contexto, em linhas distintas.
     */
    drawSystemBar(
        "",
        false,
        false,
        "",
        true,
        false);

    drawContextStrip(
        "Senha Wi-Fi",
        shortText(
            ssid,
            portrait()
                ? 30
                : 48));

    /*
     * Campo de entrada separado fisicamente do cabeçalho.
     */
    String masked;

    const size_t visibleChars =
        std::min<size_t>(
            passwordLength,
            32);

    for (
        size_t i = 0;
        i < visibleChars;
        ++i
    ) {
        masked += '*';
    }

    if (
        passwordLength >
        visibleChars
    ) {
        masked =
            "..." +
            masked;
    }

    const int32_t passwordY =
        portrait()
            ? 180
            : 142;

    const int32_t passwordH =
        portrait()
            ? 70
            : 54;

    drawRect(
        MARGIN,
        passwordY,
        logicalWidth() -
            2 * MARGIN,
        passwordH,
        BLACK);

    const String fieldText =
        masked.length() > 0
            ? masked
            : String(
                  "Digite a senha e toque Conectar");

    drawText(
        fitTextToWidth(
            fieldText,
            logicalWidth() -
                2 * MARGIN -
                36,
            masked.length() > 0
                ? MnemosFontRole::Body18
                : MnemosFontRole::Meta14),
        MARGIN + 18,
        passwordY +
            (
                portrait()
                    ? 44
                    : 35
            ),
        masked.length() > 0
            ? MnemosFontRole::Body18
            : MnemosFontRole::Meta14,
        BLACK);

    if (hint.length()) {
        drawText(
            shortText(
                hint,
                portrait()
                    ? 42
                    : 72),
            MARGIN,
            portrait()
                ? 282
                : 204,
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

        fillRect(x, y, keyW, keyH, BLACK);
        drawRect(x, y, keyW, keyH, BLACK);

        String label;
        label += chars[i];
        drawCenteredTextInRect(
            label,
            x,
            y,
            keyW,
            keyH,
            MnemosFontRole::Body18,
            WHITE);
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
        fillRect(x, controlY, widths[i], controlH, BLACK);
        drawRect(x, controlY, widths[i], controlH, BLACK);
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
            WHITE);
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
                BLACK);

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
                WHITE);

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

    /*
     * Não usa drawPrimaryTriple().
     *
     * Usa exatamente o mesmo renderer dos cards de Decks,
     * Conexão e Configurações, que já apresenta contraste
     * correto no painel físico.
     */
    const HmiLayout::Rect visual =
        HmiLayout::actionVisualRect(
            portrait());

    const int32_t gap =
        portrait()
            ? 12
            : 16;

    const int32_t buttonW =
        (
            visual.w -
            2 * gap
        ) /
        3;

    const String labels[3] = {
        "Difícil",
        "Normal",
        "Fácil"
    };

    for (
        uint8_t i = 0;
        i < 3;
        ++i
    ) {
        const int32_t x =
            visual.x +
            static_cast<int32_t>(i) *
                (
                    buttonW +
                    gap
                );

        drawChoiceCard(
            0,
            labels[i],
            x,
            visual.y,
            buttonW,
            visual.h,
            false,
            '\0');
    }

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
