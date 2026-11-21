#include "terminal_identity.h"

#include <Preferences.h>
#include <esp_system.h>

namespace {

constexpr char PREFS_NAMESPACE[] = "mnemos-id";
constexpr char PREFS_GENERATION[] = "gen";

String hexDigits(uint32_t value, uint8_t digits) {
    static const char HEX_CHARS[] = "0123456789ABCDEF";
    String out;
    out.reserve(digits);
    for (int shift = (digits - 1) * 4; shift >= 0; shift -= 4) {
        out += HEX_CHARS[(value >> shift) & 0x0F];
    }
    return out;
}

}  // namespace

namespace TerminalIdentity {

String macSuffix() {
    const uint64_t mac = ESP.getEfuseMac();
    return hexDigits(static_cast<uint32_t>(mac & 0xFFFFFFULL), 6);
}

uint16_t generation() {
    Preferences prefs;
    if (!prefs.begin(PREFS_NAMESPACE, true)) return 0;
    const uint16_t value = prefs.getUShort(PREFS_GENERATION, 0);
    prefs.end();
    return value;
}

String deviceId() {
    String id = "T5S3-" + macSuffix();
    const uint16_t gen = generation();
    if (gen > 0) {
        id += "-";
        id += String(gen);
    }
    return id;
}

uint16_t rotate() {
    Preferences prefs;
    if (!prefs.begin(PREFS_NAMESPACE, false)) return 0;
    const uint16_t next = static_cast<uint16_t>(prefs.getUShort(PREFS_GENERATION, 0) + 1U);
    prefs.putUShort(PREFS_GENERATION, next);
    prefs.end();
    return next;
}

String uuidV7(uint64_t epochMs) {
    uint8_t b[16];
    const uint64_t ms = epochMs & 0xFFFFFFFFFFFFULL;
    b[0] = static_cast<uint8_t>(ms >> 40);
    b[1] = static_cast<uint8_t>(ms >> 32);
    b[2] = static_cast<uint8_t>(ms >> 24);
    b[3] = static_cast<uint8_t>(ms >> 16);
    b[4] = static_cast<uint8_t>(ms >> 8);
    b[5] = static_cast<uint8_t>(ms);
    for (int i = 6; i < 16; i += 4) {
        const uint32_t r = esp_random();
        b[i] = static_cast<uint8_t>(r >> 24);
        if (i + 1 < 16) b[i + 1] = static_cast<uint8_t>(r >> 16);
        if (i + 2 < 16) b[i + 2] = static_cast<uint8_t>(r >> 8);
        if (i + 3 < 16) b[i + 3] = static_cast<uint8_t>(r);
    }
    b[6] = static_cast<uint8_t>(0x70 | (b[6] & 0x0F));  // versão 7
    b[8] = static_cast<uint8_t>(0x80 | (b[8] & 0x3F));  // variante RFC

    static const char HEX_CHARS[] = "0123456789abcdef";
    char out[37];
    size_t pos = 0;
    for (int i = 0; i < 16; ++i) {
        if (i == 4 || i == 6 || i == 8 || i == 10) out[pos++] = '-';
        out[pos++] = HEX_CHARS[b[i] >> 4];
        out[pos++] = HEX_CHARS[b[i] & 0x0F];
    }
    out[pos] = '\0';
    return String(out);
}

}  // namespace TerminalIdentity
