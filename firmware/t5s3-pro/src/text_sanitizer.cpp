#include "text_sanitizer.h"

namespace {

struct Replacement {
    uint32_t codepoint;
    const char* text;
};

// Ordenada por codepoint (busca binária).
const Replacement REPLACEMENTS[] = {
    {0x0009, " "},       // tab
    {0x0391, "A"},       // Α
    {0x0392, "B"},       // Β
    {0x0393, "Gama"},    // Γ
    {0x0394, "Delta"},   // Δ
    {0x0398, "Teta"},    // Θ
    {0x039B, "Lambda"},  // Λ
    {0x03A0, "Pi"},      // Π
    {0x03A3, "Sigma"},   // Σ
    {0x03A6, "Fi"},      // Φ
    {0x03A8, "Psi"},     // Ψ
    {0x03A9, "Omega"},   // Ω
    {0x03B1, "alfa"},    // α
    {0x03B2, "beta"},    // β
    {0x03B3, "gama"},    // γ
    {0x03B4, "delta"},   // δ
    {0x03B5, "epsilon"}, // ε
    {0x03B6, "zeta"},    // ζ
    {0x03B7, "eta"},     // η
    {0x03B8, "teta"},    // θ
    {0x03BA, "kapa"},    // κ
    {0x03BB, "lambda"},  // λ
    {0x03BC, "\xC2\xB5"},// μ -> µ (micro, presente na fonte)
    {0x03BD, "ni"},      // ν
    {0x03BE, "csi"},     // ξ
    {0x03C0, "pi"},      // π
    {0x03C1, "ro"},      // ρ
    {0x03C2, "sigma"},   // ς
    {0x03C3, "sigma"},   // σ
    {0x03C4, "tau"},     // τ
    {0x03C6, "fi"},      // φ
    {0x03C7, "qui"},     // χ
    {0x03C8, "psi"},     // ψ
    {0x03C9, "omega"},   // ω
    {0x2002, " "},       // en space
    {0x2003, " "},       // em space
    {0x2004, " "},
    {0x2005, " "},
    {0x2006, " "},
    {0x2007, " "},
    {0x2008, " "},
    {0x2009, " "},       // thin space
    {0x200A, " "},       // hair space
    {0x200B, ""},        // zero width space
    {0x200C, ""},
    {0x200D, ""},
    {0x200E, ""},
    {0x200F, ""},
    {0x2010, "-"},       // hyphen
    {0x2011, "-"},       // non-breaking hyphen
    {0x2012, "-"},       // figure dash
    {0x2013, "-"},       // en dash
    {0x2014, "-"},       // em dash
    {0x2015, "-"},       // horizontal bar
    {0x2016, "||"},
    {0x2018, "'"},       // ‘
    {0x2019, "'"},       // ’
    {0x201A, ","},       // ‚
    {0x201B, "'"},       // ‛
    {0x201C, "\""},      // “
    {0x201D, "\""},      // ”
    {0x201E, "\""},      // „
    {0x201F, "\""},      // ‟
    {0x2020, "+"},       // †
    {0x2022, "-"},       // •
    {0x2023, "-"},       // ‣
    {0x2024, "."},
    {0x2025, ".."},
    {0x2027, "\xC2\xB7"},// hyphenation point -> ·
    {0x2028, "\n"},      // line separator
    {0x2029, "\n"},      // paragraph separator
    {0x202F, " "},       // narrow nbsp
    {0x2030, "%."},      // ‰
    {0x2032, "'"},       // ′
    {0x2033, "\""},      // ″
    {0x2039, "<"},       // ‹
    {0x203A, ">"},       // ›
    {0x2044, "/"},       // ⁄
    {0x205F, " "},
    {0x2060, ""},        // word joiner
    {0x2070, "^0"},
    {0x2071, "^i"},
    {0x2074, "^4"},
    {0x2075, "^5"},
    {0x2076, "^6"},
    {0x2077, "^7"},
    {0x2078, "^8"},
    {0x2079, "^9"},
    {0x207A, "^+"},
    {0x207B, "^-"},
    {0x207F, "^n"},
    {0x2080, "0"},       // subscritos: H₂O -> H2O
    {0x2081, "1"},
    {0x2082, "2"},
    {0x2083, "3"},
    {0x2084, "4"},
    {0x2085, "5"},
    {0x2086, "6"},
    {0x2087, "7"},
    {0x2088, "8"},
    {0x2089, "9"},
    {0x208A, "+"},
    {0x208B, "-"},
    {0x20AC, "EUR"},     // €
    {0x2103, "\xC2\xB0" "C"},  // ℃
    {0x2109, "\xC2\xB0" "F"},  // ℉
    {0x2116, "N\xC2\xBA"},     // № -> Nº
    {0x2122, "(TM)"},    // ™
    {0x2126, "Ohm"},     // Ω (ohm)
    {0x2153, "1/3"},
    {0x2154, "2/3"},
    {0x215B, "1/8"},
    {0x2190, "<-"},      // ←
    {0x2191, "^"},       // ↑
    {0x2192, "->"},      // →
    {0x2193, "v"},       // ↓
    {0x2194, "<->"},     // ↔
    {0x21D0, "<="},      // ⇐
    {0x21D2, "=>"},      // ⇒
    {0x21D4, "<=>"},     // ⇔
    {0x2200, "para todo "},
    {0x2202, "d"},       // ∂
    {0x2203, "existe "},
    {0x2205, "{}"},      // ∅
    {0x2206, "Delta"},   // ∆
    {0x2208, " em "},    // ∈
    {0x2209, " fora de "},
    {0x2211, "Soma"},    // ∑
    {0x2212, "-"},       // minus
    {0x2213, "\xC2\xB1"},// ∓ -> ±
    {0x2215, "/"},
    {0x2217, "*"},
    {0x2218, "o"},
    {0x2219, "\xC2\xB7"},// ∙
    {0x221A, "raiz "},   // √
    {0x221D, "~"},       // ∝
    {0x221E, "infinito"},// ∞
    {0x2220, "ang. "},   // ∠
    {0x2227, " e "},     // ∧
    {0x2228, " ou "},    // ∨
    {0x2229, " inter "}, // ∩
    {0x222A, " uniao "}, // ∪
    {0x222B, "integral "},
    {0x2234, "logo "},   // ∴
    {0x2236, ":"},
    {0x223C, "~"},
    {0x2245, "~="},
    {0x2248, "~"},       // ≈
    {0x2260, "!="},      // ≠
    {0x2261, "=="},      // ≡
    {0x2264, "<="},      // ≤
    {0x2265, ">="},      // ≥
    {0x226A, "<<"},
    {0x226B, ">>"},
    {0x2282, " sub "},   // ⊂
    {0x2286, " sub "},
    {0x22C5, "\xC2\xB7"},// ⋅
    {0x2300, "diam. "},  // ⌀
    {0x2460, "(1)"},
    {0x2461, "(2)"},
    {0x2462, "(3)"},
    {0x2463, "(4)"},
    {0x2464, "(5)"},
    {0x25A0, "-"},       // ■
    {0x25A1, "-"},       // □
    {0x25AA, "-"},
    {0x25B2, "^"},
    {0x25B6, ">"},       // ▶
    {0x25BA, ">"},
    {0x25BC, "v"},
    {0x25C0, "<"},
    {0x25C6, "-"},
    {0x25CB, "o"},       // ○
    {0x25CF, "-"},       // ●
    {0x25E6, "-"},       // ◦
    {0x2605, "*"},       // ★
    {0x2606, "*"},       // ☆
    {0x2610, "[ ]"},     // ☐
    {0x2611, "[x]"},     // ☑
    {0x2612, "[x]"},     // ☒
    {0x2713, "OK"},      // ✓
    {0x2714, "OK"},      // ✔
    {0x2715, "X"},       // ✕
    {0x2716, "X"},       // ✖
    {0x2717, "X"},       // ✗
    {0x2718, "X"},       // ✘
    {0x2794, "->"},      // ➔
    {0x279C, "->"},
    {0x27A1, "->"},      // ➡
    {0x27F6, "->"},      // ⟶
    {0x27F9, "=>"},      // ⟹
    {0x2B05, "<-"},
    {0x2B06, "^"},
    {0x2B07, "v"},
    {0x3000, " "},       // espaço ideográfico (mantém CJK legível)
    {0xFE0E, ""},        // variation selectors
    {0xFE0F, ""},
    {0xFEFF, ""},        // BOM
    {0xFF01, "!"},       // pontuação de largura total
    {0xFF08, "("},
    {0xFF09, ")"},
    {0xFF0C, ","},
    {0xFF1A, ":"},
    {0xFF1B, ";"},
    {0xFF1F, "?"},
    {0xFFFD, "?"},
};

const char* replacementFor(uint32_t cp) {
    size_t lo = 0;
    size_t hi = sizeof(REPLACEMENTS) / sizeof(REPLACEMENTS[0]);
    while (lo < hi) {
        const size_t mid = (lo + hi) / 2;
        if (REPLACEMENTS[mid].codepoint == cp) return REPLACEMENTS[mid].text;
        if (REPLACEMENTS[mid].codepoint < cp) lo = mid + 1;
        else hi = mid;
    }
    return nullptr;
}

// Composição NFC das combinações usadas em português/espanhol/francês.
uint32_t compose(uint32_t base, uint32_t mark) {
    struct Pair { uint32_t base; uint32_t mark; uint32_t composed; };
    static const Pair PAIRS[] = {
        {'A', 0x0300, 0x00C0}, {'A', 0x0301, 0x00C1}, {'A', 0x0302, 0x00C2}, {'A', 0x0303, 0x00C3}, {'A', 0x0308, 0x00C4},
        {'C', 0x0327, 0x00C7},
        {'E', 0x0300, 0x00C8}, {'E', 0x0301, 0x00C9}, {'E', 0x0302, 0x00CA}, {'E', 0x0308, 0x00CB},
        {'I', 0x0300, 0x00CC}, {'I', 0x0301, 0x00CD}, {'I', 0x0302, 0x00CE}, {'I', 0x0308, 0x00CF},
        {'N', 0x0303, 0x00D1},
        {'O', 0x0300, 0x00D2}, {'O', 0x0301, 0x00D3}, {'O', 0x0302, 0x00D4}, {'O', 0x0303, 0x00D5}, {'O', 0x0308, 0x00D6},
        {'U', 0x0300, 0x00D9}, {'U', 0x0301, 0x00DA}, {'U', 0x0302, 0x00DB}, {'U', 0x0308, 0x00DC},
        {'Y', 0x0301, 0x00DD},
        {'a', 0x0300, 0x00E0}, {'a', 0x0301, 0x00E1}, {'a', 0x0302, 0x00E2}, {'a', 0x0303, 0x00E3}, {'a', 0x0308, 0x00E4},
        {'c', 0x0327, 0x00E7},
        {'e', 0x0300, 0x00E8}, {'e', 0x0301, 0x00E9}, {'e', 0x0302, 0x00EA}, {'e', 0x0308, 0x00EB},
        {'i', 0x0300, 0x00EC}, {'i', 0x0301, 0x00ED}, {'i', 0x0302, 0x00EE}, {'i', 0x0308, 0x00EF},
        {'n', 0x0303, 0x00F1},
        {'o', 0x0300, 0x00F2}, {'o', 0x0301, 0x00F3}, {'o', 0x0302, 0x00F4}, {'o', 0x0303, 0x00F5}, {'o', 0x0308, 0x00F6},
        {'u', 0x0300, 0x00F9}, {'u', 0x0301, 0x00FA}, {'u', 0x0302, 0x00FB}, {'u', 0x0308, 0x00FC},
        {'y', 0x0301, 0x00FD}, {'y', 0x0308, 0x00FF},
    };
    for (const Pair& p : PAIRS) {
        if (p.base == base && p.mark == mark) return p.composed;
    }
    return 0;
}

bool isCombiningMark(uint32_t cp) {
    return (cp >= 0x0300 && cp <= 0x036F) || (cp >= 0x1AB0 && cp <= 0x1AFF) ||
           (cp >= 0x20D0 && cp <= 0x20FF);
}

// Decodifica uma sequência UTF-8. Bytes inválidos viram U+FFFD e avançam 1.
uint32_t decode(const char* s, size_t len, size_t& i) {
    const uint8_t c0 = static_cast<uint8_t>(s[i]);
    if (c0 < 0x80) {
        ++i;
        return c0;
    }
    size_t need = 0;
    uint32_t cp = 0;
    if ((c0 & 0xE0) == 0xC0) { need = 1; cp = c0 & 0x1F; }
    else if ((c0 & 0xF0) == 0xE0) { need = 2; cp = c0 & 0x0F; }
    else if ((c0 & 0xF8) == 0xF0) { need = 3; cp = c0 & 0x07; }
    else { ++i; return 0xFFFD; }
    for (size_t k = 1; k <= need; ++k) {
        if (i + k >= len) { ++i; return 0xFFFD; }
        const uint8_t ck = static_cast<uint8_t>(s[i + k]);
        if ((ck & 0xC0) != 0x80) { ++i; return 0xFFFD; }
        cp = (cp << 6) | (ck & 0x3F);
    }
    i += need + 1;
    // Rejeita sobrelongos e surrogates.
    if ((need == 1 && cp < 0x80) || (need == 2 && cp < 0x800) || (need == 3 && cp < 0x10000) ||
        (cp >= 0xD800 && cp <= 0xDFFF) || cp > 0x10FFFF) {
        return 0xFFFD;
    }
    return cp;
}

void encode(uint32_t cp, String& out) {
    char buf[5] = {0};
    if (cp < 0x80) {
        buf[0] = static_cast<char>(cp);
    } else if (cp < 0x800) {
        buf[0] = static_cast<char>(0xC0 | (cp >> 6));
        buf[1] = static_cast<char>(0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
        buf[0] = static_cast<char>(0xE0 | (cp >> 12));
        buf[1] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
        buf[2] = static_cast<char>(0x80 | (cp & 0x3F));
    } else {
        buf[0] = static_cast<char>(0xF0 | (cp >> 18));
        buf[1] = static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
        buf[2] = static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
        buf[3] = static_cast<char>(0x80 | (cp & 0x3F));
    }
    out += buf;
}

bool isEmojiOrPictograph(uint32_t cp) {
    return (cp >= 0x1F000 && cp <= 0x1FAFF) ||  // emoji, símbolos, bandeiras
           (cp >= 0x2600 && cp <= 0x26FF) ||    // símbolos diversos sem mapeamento
           (cp >= 0x2700 && cp <= 0x27BF) ||    // dingbats sem mapeamento
           (cp >= 0xE000 && cp <= 0xF8FF);      // uso privado
}

}  // namespace

namespace TextSanitizer {

String forDisplay(const String& input) {
    const char* s = input.c_str();
    const size_t len = input.length();
    String out;
    out.reserve(len + 8);

    uint32_t pending = 0;  // último codepoint ainda não emitido (para NFC)
    bool hasPending = false;
    bool lastWasSpace = false;

    auto flush = [&]() {
        if (hasPending) {
            const bool space = pending == ' ';
            if (!(space && lastWasSpace)) encode(pending, out);
            lastWasSpace = space;
            hasPending = false;
        }
    };

    auto emitText = [&](const char* text) {
        flush();
        for (const char* p = text; *p; ++p) {
            const bool space = *p == ' ';
            if (space && lastWasSpace) continue;  // evita "  " de substituições
            out += *p;
            lastWasSpace = space;
        }
    };

    size_t i = 0;
    while (i < len) {
        uint32_t cp = decode(s, len, i);

        if (cp == '\r') {
            // CRLF -> LF; CR isolado -> LF.
            if (i < len && s[i] == '\n') continue;
            cp = '\n';
        }

        if (isCombiningMark(cp)) {
            if (hasPending) {
                const uint32_t composed = compose(pending, cp);
                if (composed != 0) pending = composed;
            }
            // Marca sem composição conhecida é descartada: a letra base fica.
            continue;
        }

        if (cp == '\n') {
            flush();
            out += '\n';
            lastWasSpace = true;
            continue;
        }

        if (const char* replacement = replacementFor(cp)) {
            emitText(replacement);
            continue;
        }

        if (cp < 0x20 || cp == 0x7F || (cp >= 0x80 && cp < 0xA0)) {
            continue;  // controles
        }

        if (isEmojiOrPictograph(cp)) {
            flush();
            continue;
        }

        flush();
        pending = cp;
        hasPending = true;
    }
    flush();

    // Remove espaços nas pontas.
    int start = 0;
    int end = static_cast<int>(out.length());
    while (start < end && (out[start] == ' ' || out[start] == '\n')) ++start;
    while (end > start && (out[end - 1] == ' ' || out[end - 1] == '\n')) --end;
    if (start == 0 && end == static_cast<int>(out.length())) return out;
    return out.substring(start, end);
}

String truncateUtf8(const String& input, size_t maxBytes) {
    if (input.length() <= maxBytes) return input;
    size_t cut = maxBytes;
    while (cut > 0 && (static_cast<uint8_t>(input[cut]) & 0xC0) == 0x80) --cut;
    return input.substring(0, cut);
}

}  // namespace TextSanitizer
