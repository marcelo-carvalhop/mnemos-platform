#pragma once

#include <Arduino.h>

struct OtaManifest {
    String schema;
    String version;
    String model;
    String file;
    String sha256;

    uint32_t generation = 0;
    uint32_t size = 0;

    uint8_t protocolMin = 0;
    uint8_t protocolMax = 0;

    bool apply = false;
};

enum class OtaResult : uint8_t {
    NoUpdate = 0,
    Installed,
    Skipped,
    InvalidManifest,
    UnsafePower,
    VerificationFailed,
    InstallFailed,
};

class OtaService {
public:
    void begin();

    OtaResult applyLocalUpdateIfRequested(
        bool batteryAvailable,
        uint8_t batteryPercent);

    void confirmRunningImage();

    void logStatus(
        const char* phase = "runtime") const;

    const String& lastError() const {
        return lastError_;
    }

private:
    String lastError_;

    bool loadLocalManifest(
        OtaManifest& manifest);

    bool validateManifest(
        const OtaManifest& manifest);

    bool verifyImage(
        const OtaManifest& manifest);

    bool installImage(
        const OtaManifest& manifest);

    bool sha256File(
        const String& path,
        String& digest,
        uint32_t& size);

    bool moveManifestToApplied();
};
