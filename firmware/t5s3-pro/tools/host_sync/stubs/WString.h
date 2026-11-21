#pragma once
#include <string>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <cstdint>
#include <algorithm>

#ifndef HEX
#define HEX 16
#define DEC 10
#endif

class String {
public:
    std::string s;
    String() {}
    String(const char* c) : s(c ? c : "") {}
    String(const std::string& v) : s(v) {}
    String(const String& o) = default;
    String(String&& o) = default;
    String& operator=(const String& o) = default;
    String& operator=(String&& o) = default;
    String& operator=(const char* c) { s = c ? c : ""; return *this; }
    explicit String(char c) : s(1, c) {}
    String(unsigned char v, unsigned char base = 10) { fromU(v, base); }
    String(int v, unsigned char base = 10) { if (base == 10) s = std::to_string(v); else fromU((unsigned)v, base); }
    String(unsigned int v, unsigned char base = 10) { fromU(v, base); }
    String(long v, unsigned char base = 10) { if (base == 10) s = std::to_string(v); else fromU((unsigned long)v, base); }
    String(unsigned long v, unsigned char base = 10) { fromU(v, base); }
    String(long long v, unsigned char base = 10) { if (base == 10) s = std::to_string(v); else fromU((unsigned long long)v, base); }
    String(unsigned long long v, unsigned char base = 10) { fromU(v, base); }
    String(float v, unsigned int dp = 2) { char b[64]; snprintf(b, sizeof b, "%.*f", dp, v); s = b; }
    String(double v, unsigned int dp = 2) { char b[64]; snprintf(b, sizeof b, "%.*f", dp, v); s = b; }
    void fromU(unsigned long long v, unsigned base) {
        if (base == 10) { s = std::to_string(v); return; }
        const char* d = "0123456789abcdef"; std::string o; if (!v) o = "0";
        while (v) { o.insert(o.begin(), d[v % base]); v /= base; } s = o;
    }
    const char* c_str() const { return s.c_str(); }
    unsigned int length() const { return (unsigned)s.size(); }
    bool isEmpty() const { return s.empty(); }
    bool reserve(unsigned int n) { s.reserve(n); return true; }
    bool concat(const String& o) { s += o.s; return true; }
    bool concat(const char* c) { if (c) s += c; return true; }
    bool concat(const char* c, unsigned int n) { s.append(c, n); return true; }
    bool concat(char c) { s += c; return true; }
    bool concat(unsigned char c) { s += std::to_string(c); return true; }
    bool concat(int n) { s += std::to_string(n); return true; }
    bool concat(unsigned int n) { s += std::to_string(n); return true; }
    bool concat(long n) { s += std::to_string(n); return true; }
    bool concat(unsigned long n) { s += std::to_string(n); return true; }
    bool concat(long long n) { s += std::to_string(n); return true; }
    bool concat(unsigned long long n) { s += std::to_string(n); return true; }
    bool concat(double n) { s += String(n).s; return true; }
    String& operator+=(const String& o) { s += o.s; return *this; }
    String& operator+=(const char* c) { if (c) s += c; return *this; }
    String& operator+=(char c) { s += c; return *this; }
    String& operator+=(int n) { s += std::to_string(n); return *this; }
    String& operator+=(unsigned int n) { s += std::to_string(n); return *this; }
    String& operator+=(long n) { s += std::to_string(n); return *this; }
    String& operator+=(unsigned long n) { s += std::to_string(n); return *this; }
    bool operator==(const String& o) const { return s == o.s; }
    bool operator==(const char* c) const { return s == (c ? c : ""); }
    bool operator!=(const String& o) const { return s != o.s; }
    bool operator!=(const char* c) const { return !(*this == c); }
    bool operator<(const String& o) const { return s < o.s; }
    char operator[](unsigned int i) const { return i < s.size() ? s[i] : 0; }
    char& operator[](unsigned int i) { return s[i]; }
    char charAt(unsigned int i) const { return (*this)[i]; }
    bool equals(const String& o) const { return s == o.s; }
    int compareTo(const String& o) const { return s.compare(o.s); }
    int indexOf(char c, unsigned int from = 0) const { auto p = s.find(c, from); return p == std::string::npos ? -1 : (int)p; }
    int indexOf(const String& t, unsigned int from = 0) const { auto p = s.find(t.s, from); return p == std::string::npos ? -1 : (int)p; }
    int indexOf(const char* t, unsigned int from = 0) const { return indexOf(String(t), from); }
    int lastIndexOf(char c) const { auto p = s.rfind(c); return p == std::string::npos ? -1 : (int)p; }
    String substring(unsigned int a) const { return a >= s.size() ? String() : String(s.substr(a)); }
    String substring(unsigned int a, unsigned int b) const { if (a > b) std::swap(a, b); if (a >= s.size()) return String(); return String(s.substr(a, std::min<size_t>(b, s.size()) - a)); }
    bool startsWith(const String& p) const { return s.compare(0, p.s.size(), p.s) == 0 && s.size() >= p.s.size(); }
    bool endsWith(const String& p) const { return s.size() >= p.s.size() && s.compare(s.size() - p.s.size(), p.s.size(), p.s) == 0; }
    void trim() { size_t a = 0, b = s.size(); while (a < b && isspace((unsigned char)s[a])) ++a; while (b > a && isspace((unsigned char)s[b - 1])) --b; s = s.substr(a, b - a); }
    void toLowerCase() { for (auto& c : s) c = (char)tolower((unsigned char)c); }
    void toUpperCase() { for (auto& c : s) c = (char)toupper((unsigned char)c); }
    void replace(const String& f, const String& t) { if (f.s.empty()) return; size_t p = 0; while ((p = s.find(f.s, p)) != std::string::npos) { s.replace(p, f.s.size(), t.s); p += t.s.size(); } }
    void remove(unsigned int i) { if (i < s.size()) s.erase(i); }
    void remove(unsigned int i, unsigned int n) { if (i < s.size()) s.erase(i, n); }
    long toInt() const { return strtol(s.c_str(), nullptr, 10); }
    float toFloat() const { return strtof(s.c_str(), nullptr); }
    double toDouble() const { return strtod(s.c_str(), nullptr); }
};
inline String operator+(const String& a, const String& b) { String r(a); r += b; return r; }
inline String operator+(const String& a, const char* b) { String r(a); r += b; return r; }
inline String operator+(const char* a, const String& b) { String r(a); r += b; return r; }
inline String operator+(const String& a, char b) { String r(a); r += b; return r; }
inline bool operator==(const char* a, const String& b) { return b == a; }
