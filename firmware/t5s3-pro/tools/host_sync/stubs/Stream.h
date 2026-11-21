#pragma once
#include "Print.h"
class Stream : public Print {
public:
    virtual int available() = 0;
    virtual int read() = 0;
    virtual int peek() { return -1; }
    size_t readBytes(char* b, size_t n) { size_t k = 0; while (k < n) { int c = read(); if (c < 0) break; b[k++] = (char)c; } return k; }
    size_t readBytes(uint8_t* b, size_t n) { return readBytes((char*)b, n); }
    String readString() { String s; int c; while ((c = read()) >= 0) s += (char)c; return s; }
    void setTimeout(unsigned long) {}
};
