#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdarg>
#include "WString.h"
class Print {
public:
    virtual ~Print() {}
    virtual size_t write(uint8_t c) = 0;
    virtual size_t write(const uint8_t* b, size_t n) { size_t k = 0; while (n--) k += write(*b++); return k; }
    size_t write(const char* s) { return write((const uint8_t*)s, strlen(s)); }
    size_t print(const String& s) { return write((const uint8_t*)s.c_str(), s.length()); }
    size_t print(const char* s) { return write((const uint8_t*)s, strlen(s)); }
    size_t print(char c) { return write((uint8_t)c); }
    size_t print(int v) { return print(String(v)); }
    size_t print(unsigned v) { return print(String(v)); }
    size_t print(long v) { return print(String(v)); }
    size_t print(unsigned long v) { return print(String(v)); }
    size_t println() { return print("\r\n"); }
    size_t println(const String& s) { return print(s) + println(); }
    size_t println(const char* s) { return print(s) + println(); }
    size_t println(int v) { return print(v) + println(); }
    size_t printf(const char* fmt, ...) { char buf[2048]; va_list a; va_start(a, fmt); int n = vsnprintf(buf, sizeof buf, fmt, a); va_end(a); return write((const uint8_t*)buf, n < 0 ? 0 : (size_t)std::min(n, (int)sizeof(buf) - 1)); }
    virtual void flush() {}
};
class Printable { public: virtual ~Printable() {} virtual size_t printTo(Print& p) const = 0; };
class __FlashStringHelper;
