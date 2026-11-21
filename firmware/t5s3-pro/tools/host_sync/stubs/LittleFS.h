#pragma once
#include "FS.h"
#include <sys/stat.h>
#include <unistd.h>
class LittleFSHost {
public:
    std::string root = "/tmp/lfs";
    std::string p(const char* path) const { return root + path; }
    bool begin(bool = false, const char* = "/littlefs", uint8_t = 10, const char* = "littlefs") { mkdir(root.c_str(), 0755); return true; }
    bool exists(const char* path) const { struct stat st; return stat(p(path).c_str(), &st) == 0; }
    bool exists(const String& path) const { return exists(path.c_str()); }
    File open(const char* path, const char* mode = "r") { const char* m = mode[0] == 'w' ? "wb" : (mode[0] == 'a' ? "ab" : "rb"); FILE* f = fopen(p(path).c_str(), m); return f ? File(f, path) : File(); }
    File open(const String& path, const char* mode = "r") { return open(path.c_str(), mode); }
    bool remove(const char* path) { return ::unlink(p(path).c_str()) == 0; }
    bool rename(const char* a, const char* b) { return ::rename(p(a).c_str(), p(b).c_str()) == 0; }
};
extern LittleFSHost LittleFS;
