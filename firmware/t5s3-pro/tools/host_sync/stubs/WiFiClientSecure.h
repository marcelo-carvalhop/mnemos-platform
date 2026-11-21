#pragma once
#include "Arduino.h"
class WiFiClientSecure { public: const char* ca = nullptr; void setCACert(const char* c) { ca = c; } void setHandshakeTimeout(unsigned long) {} int lastError(char* b, size_t n) { if (n) b[0] = 0; return 0; } void stop() {} };
