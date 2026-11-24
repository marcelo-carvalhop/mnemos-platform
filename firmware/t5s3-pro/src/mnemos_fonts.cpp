#include "mnemos_fonts.h"

#include <algorithm>
#include <cstring>

namespace {

struct MnemosFontGlyph {
    uint32_t codepoint;
    uint32_t bitmapOffset;
    uint8_t width;
    uint8_t height;
    int8_t xOffset;
    int8_t yOffset;
    uint8_t advance;
};

/*
 * Um papel e o seu fallback. O bitmap principal tem 4 bits por pixel; o de
 * fallback (ideogramas, pinyin) é o de 1 bit das fontes antigas.
 */
struct FontView {
    const MnemosFontGlyph* glyphs;
    const uint8_t* bitmap;
    uint16_t glyphCount;
    const MnemosFontGlyph* fallbackGlyphs;
    const uint8_t* fallbackBitmap;
    uint16_t fallbackCount;
};

}  // namespace

#include "mnemos_font_data.h"

namespace {

uint32_t nextCodepoint(const char*& p) {
    const uint8_t c0 = static_cast<uint8_t>(*p++);

    if (c0 < 0x80) {
        return c0;
    }

    if ((c0 & 0xE0) == 0xC0) {
        const uint8_t c1 = static_cast<uint8_t>(*p++);
        return ((c0 & 0x1F) << 6) | (c1 & 0x3F);
    }

    if ((c0 & 0xF0) == 0xE0) {
        const uint8_t c1 = static_cast<uint8_t>(*p++);
        const uint8_t c2 = static_cast<uint8_t>(*p++);
        return ((c0 & 0x0F) << 12) |
               ((c1 & 0x3F) << 6) |
               (c2 & 0x3F);
    }

    if ((c0 & 0xF8) == 0xF0) {
        const uint8_t c1 = static_cast<uint8_t>(*p++);
        const uint8_t c2 = static_cast<uint8_t>(*p++);
        const uint8_t c3 = static_cast<uint8_t>(*p++);
        return ((c0 & 0x07) << 18) |
               ((c1 & 0x3F) << 12) |
               ((c2 & 0x3F) << 6) |
               (c3 & 0x3F);
    }

    return static_cast<uint32_t>('?');
}

bool findGlyph(const MnemosFontGlyph* glyphs,
               uint16_t count,
               uint32_t codepoint,
               MnemosFontGlyph& out) {
    int32_t lo = 0;
    int32_t hi = static_cast<int32_t>(count) - 1;

    while (lo <= hi) {
        const int32_t mid = (lo + hi) / 2;

        MnemosFontGlyph probe;
        memcpy_P(&probe, &glyphs[mid], sizeof(probe));

        if (probe.codepoint == codepoint) {
            out = probe;
            return true;
        }

        if (probe.codepoint < codepoint) {
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }

    return false;
}

/*
 * O glifo e de qual bitmap ele vem. `fourBit` falso quer dizer fallback de
 * 1 bit.
 */
struct ResolvedGlyph {
    MnemosFontGlyph glyph;
    const uint8_t* bitmap;
    bool fourBit;
};

bool getGlyph(const FontView& view,
              uint32_t codepoint,
              ResolvedGlyph& out) {
    if (findGlyph(view.glyphs, view.glyphCount, codepoint, out.glyph)) {
        out.bitmap = view.bitmap;
        out.fourBit = true;
        return true;
    }

    if (findGlyph(view.fallbackGlyphs, view.fallbackCount, codepoint, out.glyph)) {
        out.bitmap = view.fallbackBitmap;
        out.fourBit = false;
        return true;
    }

    if (findGlyph(view.glyphs, view.glyphCount, static_cast<uint32_t>('?'), out.glyph)) {
        out.bitmap = view.bitmap;
        out.fourBit = true;
        return true;
    }

    return false;
}

// Cobertura 0..15 do pixel i do glifo.
uint8_t coverageAt(const ResolvedGlyph& g, uint32_t i) {
    if (g.fourBit) {
        const uint8_t packed =
            pgm_read_byte(&g.bitmap[g.glyph.bitmapOffset + i / 2U]);
        return (i % 2U) == 0 ? (packed >> 4) : (packed & 0x0F);
    }

    const uint8_t packed =
        pgm_read_byte(&g.bitmap[g.glyph.bitmapOffset + i / 8U]);
    return (packed & (0x80U >> (i % 8U))) ? 15 : 0;
}

}  // namespace

int32_t mnemosFontTextWidth(
    const String& text,
    MnemosFontRole role) {

    const FontView view = fontViewFor(role);
    const char* p = text.c_str();
    int32_t width = 0;

    while (*p) {
        ResolvedGlyph g;
        if (!getGlyph(view, nextCodepoint(p), g)) {
            continue;
        }
        width += g.glyph.advance;
    }

    return width;
}

bool mnemosFontVisualBounds(
    const String& text,
    MnemosFontRole role,
    int32_t& left,
    int32_t& top,
    int32_t& right,
    int32_t& bottom) {

    const FontView view = fontViewFor(role);
    const char* p = text.c_str();

    int32_t cursor = 0;
    bool hasInk = false;
    int32_t minX = 0;
    int32_t minY = 0;
    int32_t maxX = 0;
    int32_t maxY = 0;

    while (*p) {
        ResolvedGlyph g;
        if (!getGlyph(view, nextCodepoint(p), g)) {
            continue;
        }

        const MnemosFontGlyph& glyph = g.glyph;
        if (glyph.width > 0 && glyph.height > 0) {
            const int32_t glyphLeft = cursor + glyph.xOffset;
            const int32_t glyphTop = glyph.yOffset;
            const int32_t glyphRight = glyphLeft + glyph.width;
            const int32_t glyphBottom = glyphTop + glyph.height;

            if (!hasInk) {
                minX = glyphLeft;
                minY = glyphTop;
                maxX = glyphRight;
                maxY = glyphBottom;
                hasInk = true;
            } else {
                minX = std::min(minX, glyphLeft);
                minY = std::min(minY, glyphTop);
                maxX = std::max(maxX, glyphRight);
                maxY = std::max(maxY, glyphBottom);
            }
        }

        cursor += glyph.advance;
    }

    if (!hasInk) {
        left = 0;
        top = 0;
        right = cursor;
        bottom = 0;
        return false;
    }

    left = minX;
    top = minY;
    right = maxX;
    bottom = maxY;
    return true;
}

bool mnemosFontTextBounds(
    const String& text,
    MnemosFontRole role,
    int32_t& left,
    int32_t& right) {

    int32_t top = 0;
    int32_t bottom = 0;
    return mnemosFontVisualBounds(text, role, left, top, right, bottom);
}

void mnemosFontDrawText(
    const String& text,
    int32_t x,
    int32_t baselineY,
    uint8_t* framebuffer,
    int32_t canvasWidth,
    int32_t canvasHeight,
    MnemosFontRole role,
    uint8_t color,
    uint8_t scale) {

    if (!framebuffer ||
        canvasWidth <= 0 ||
        canvasHeight <= 0 ||
        scale == 0) {
        return;
    }

    const FontView view = fontViewFor(role);
    const char* p = text.c_str();
    int32_t cursor = x;

    auto blend = [&](int32_t px, int32_t py, uint8_t coverage) {
        if (px < 0 || py < 0 || px >= canvasWidth || py >= canvasHeight) {
            return;
        }
        uint8_t& dst =
            framebuffer[static_cast<size_t>(py) *
                            static_cast<size_t>(canvasWidth) +
                        static_cast<size_t>(px)];
        if (coverage >= 15) {
            dst = color;
            return;
        }
        const int32_t d = dst;
        dst = static_cast<uint8_t>(
            d + ((static_cast<int32_t>(color) - d) * coverage) / 15);
    };

    while (*p) {
        ResolvedGlyph g;
        if (!getGlyph(view, nextCodepoint(p), g)) {
            continue;
        }

        const MnemosFontGlyph& glyph = g.glyph;
        const uint32_t pixelCount =
            static_cast<uint32_t>(glyph.width) *
            static_cast<uint32_t>(glyph.height);

        for (uint32_t i = 0; i < pixelCount; ++i) {
            const uint8_t coverage = coverageAt(g, i);
            if (coverage == 0) {
                continue;
            }

            const int32_t glyphX =
                glyph.xOffset + static_cast<int32_t>(i % glyph.width);
            const int32_t glyphY =
                glyph.yOffset + static_cast<int32_t>(i / glyph.width);

            for (uint8_t yy = 0; yy < scale; ++yy) {
                for (uint8_t xx = 0; xx < scale; ++xx) {
                    blend(cursor + glyphX * scale + xx,
                          baselineY + glyphY * scale + yy,
                          coverage);
                }
            }
        }

        cursor += static_cast<int32_t>(glyph.advance) * scale;
    }
}

String mnemosUpper(const String& text) {
    String out;
    out.reserve(text.length());
    const char* p = text.c_str();

    while (*p) {
        const uint8_t c0 = static_cast<uint8_t>(*p);

        if (c0 < 0x80) {
            out += static_cast<char>(
                (c0 >= 'a' && c0 <= 'z') ? c0 - 32 : c0);
            ++p;
            continue;
        }

        // Latin-1 em dois bytes: C3 A0..C3 BE (à..þ, exceto ÷) sobem 0x20.
        if (c0 == 0xC3 && p[1]) {
            const uint8_t c1 = static_cast<uint8_t>(p[1]);
            const bool lower = c1 >= 0xA0 && c1 <= 0xBE && c1 != 0xB7;
            out += static_cast<char>(c0);
            out += static_cast<char>(lower ? c1 - 0x20 : c1);
            p += 2;
            continue;
        }

        out += static_cast<char>(*p++);
    }

    return out;
}
