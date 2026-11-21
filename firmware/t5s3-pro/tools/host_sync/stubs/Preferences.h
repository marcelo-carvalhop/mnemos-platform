#pragma once
#include "Arduino.h"
#include <map>
#include <string>
class Preferences {
public:
    static std::map<std::string, std::map<std::string, std::string>>& store() { static std::map<std::string, std::map<std::string, std::string>> s; return s; }
    std::string ns;
    bool begin(const char* n, bool = false) { ns = n; return true; }
    void end() {}
    std::string get(const char* k, const std::string& d) { auto& m = store()[ns]; auto it = m.find(k); return it == m.end() ? d : it->second; }
    String getString(const char* k, const String& d = String()) { return String(get(k, d.s)); }
    size_t putString(const char* k, const String& v) { store()[ns][k] = v.s; return v.length(); }
    bool getBool(const char* k, bool d = false) { return get(k, d ? "1" : "0") == "1"; }
    size_t putBool(const char* k, bool v) { store()[ns][k] = v ? "1" : "0"; return 1; }
    uint32_t getULong(const char* k, uint32_t d = 0) { return (uint32_t)std::stoul(get(k, std::to_string(d))); }
    size_t putULong(const char* k, uint32_t v) { store()[ns][k] = std::to_string(v); return 4; }
    uint16_t getUShort(const char* k, uint16_t d = 0) { return (uint16_t)std::stoul(get(k, std::to_string(d))); }
    size_t putUShort(const char* k, uint16_t v) { store()[ns][k] = std::to_string(v); return 2; }
};
