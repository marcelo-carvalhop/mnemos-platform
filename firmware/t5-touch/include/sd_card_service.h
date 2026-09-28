#pragma once

#include <Arduino.h>
#include <SPI.h>
#include <ArduinoJson.h>

#include "models.h"

struct SdImportResult {
    bool ok = false;
    uint16_t added = 0;
    uint16_t updated = 0;
    uint16_t skipped = 0;
    String error;
};

class SdCardService {
public:
    static constexpr size_t MAX_VISIBLE_FILES = 6;

    bool begin();
    bool remount();
    void suspend();
    bool resume();
    bool mounted() const { return mounted_; }

    uint64_t cardSizeBytes() const;
    uint64_t usedBytes() const;

    size_t listDeckFiles(
        String* paths,
        String* names,
        uint32_t* sizes,
        size_t maxFiles);

    SdImportResult importDeckFile(
        const String& path,
        CardDefinition* cards,
        CardState* states,
        size_t maxCards,
        size_t& count);

    // Biblioteca SD-first.
    bool canonicalLibraryAvailable() const;

    bool saveCanonicalLibrary(
        const CardDefinition* cards,
        size_t count);

    bool loadCatalog(
        CardDefinition* cards,
        CardState* states,
        size_t maxCards,
        size_t& count);

    bool hydrateCard(
        const String& id,
        CardDefinition& card);

    void compactCatalog(
        CardDefinition* cards,
        size_t count);

    SdImportResult importDeckFileToCanonical(
        const String& path,
        size_t maxCards);
    bool exportLibrary(
        const CardDefinition* cards,
        size_t count,
        String& exportedPath);

    const String& lastError() const {
        return lastError_;
    }

private:
    bool mounted_ = false;
    String lastError_;

    bool ensureFolders();
    bool parseCard(
        JsonObjectConst obj,
        CardDefinition& card) const;
    int findCard(
        const CardDefinition* cards,
        size_t count,
        const String& id) const;
};
