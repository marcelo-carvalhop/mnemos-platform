#pragma once
#include "Arduino.h"
struct MDNSHost { bool begin(const char*) { return true; } IPAddress queryHost(const char* h, uint32_t) { (void)h; return IPAddress(127, 0, 0, 1); } };
extern MDNSHost MDNS;
