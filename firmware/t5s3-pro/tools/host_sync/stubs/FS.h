#pragma once
#include "Arduino.h"
#include <cstdio>
#include <memory>
#include <string>
namespace fs {
class File : public Stream {
public:
    std::shared_ptr<FILE> f;
    std::string path;
    File() {}
    File(FILE* fp, const std::string& p) : f(fp, [](FILE* x) { if (x) fclose(x); }), path(p) {}
    explicit operator bool() const { return (bool)f; }
    size_t write(uint8_t c) override { return f ? fwrite(&c, 1, 1, f.get()) : 0; }
    size_t write(const uint8_t* b, size_t n) override { return f ? fwrite(b, 1, n, f.get()) : 0; }
    int available() override { if (!f) return 0; long cur = ftell(f.get()); fseek(f.get(), 0, SEEK_END); long end = ftell(f.get()); fseek(f.get(), cur, SEEK_SET); return (int)(end - cur); }
    int read() override { if (!f) return -1; int c = fgetc(f.get()); return c == EOF ? -1 : c; }
    size_t read(uint8_t* b, size_t n) { return f ? fread(b, 1, n, f.get()) : 0; }
    int peek() override { if (!f) return -1; int c = fgetc(f.get()); if (c != EOF) ungetc(c, f.get()); return c == EOF ? -1 : c; }
    void flush() override { if (f) fflush(f.get()); }
    size_t size() const { if (!f) return 0; long cur = ftell(f.get()); fseek(f.get(), 0, SEEK_END); long end = ftell(f.get()); fseek(f.get(), cur, SEEK_SET); return (size_t)end; }
    void close() { f.reset(); }
};
}
using fs::File;
