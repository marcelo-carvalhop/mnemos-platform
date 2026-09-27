#include "sd_card_service.h"

#include <ArduinoJson.h>
#include <FS.h>
#include <SD.h>
#include <SPI.h>

#include "config.h"

namespace {

constexpr const char* DECK_DIR =
    "/mnemos/decks";

constexpr const char* EXPORT_DIR =
    "/mnemos/export";

bool jsonFileName(
    const String& name) {

    String lower = name;
    lower.toLowerCase();

    return lower.endsWith(".json");
}

String baseName(
    const String& path) {

    const int slash =
        path.lastIndexOf('/');

    return
        slash >= 0
            ? path.substring(slash + 1)
            : path;
}

}  // namespace


bool SdCardService::begin() {
    return remount();
}


bool SdCardService::remount() {
    lastError_ = "";

    if (mounted_) {
        SD.end();
        SPI.end();
        mounted_ = false;
    }

    pinMode(
        Config::SD_CS_PIN,
        OUTPUT);

    digitalWrite(
        Config::SD_CS_PIN,
        HIGH);

    SPI.begin(
        Config::SD_SCK_PIN,
        Config::SD_MISO_PIN,
        Config::SD_MOSI_PIN,
        Config::SD_CS_PIN);

    mounted_ = SD.begin(
        Config::SD_CS_PIN,
        SPI,
        Config::SD_FREQUENCY_HZ);

    if (!mounted_) {
        lastError_ =
            "sd_mount_failed";

        Serial.println(
            "[sd] cartao nao montado");

        return false;
    }

    if (!ensureFolders()) {
        mounted_ = false;
        SD.end();
        lastError_ =
            "sd_folder_failed";
        return false;
    }

    Serial.printf(
        "[sd] montado: %.2f GB, usado %.2f GB\n",
        cardSizeBytes() /
            1024.0 /
            1024.0 /
            1024.0,
        usedBytes() /
            1024.0 /
            1024.0 /
            1024.0);

    return true;
}


bool SdCardService::ensureFolders() {
    if (!mounted_) {
        return false;
    }

    if (!SD.exists("/mnemos")) {
        if (!SD.mkdir("/mnemos")) {
            return false;
        }
    }

    if (!SD.exists(DECK_DIR)) {
        if (!SD.mkdir(DECK_DIR)) {
            return false;
        }
    }

    if (!SD.exists(EXPORT_DIR)) {
        if (!SD.mkdir(EXPORT_DIR)) {
            return false;
        }
    }

    return true;
}


uint64_t SdCardService::cardSizeBytes() const {
    return
        mounted_
            ? SD.cardSize()
            : 0ULL;
}


uint64_t SdCardService::usedBytes() const {
    return
        mounted_
            ? SD.usedBytes()
            : 0ULL;
}


size_t SdCardService::listDeckFiles(
    String* paths,
    String* names,
    uint32_t* sizes,
    size_t maxFiles) {

    if (
        !mounted_ ||
        !paths ||
        !names ||
        !sizes ||
        maxFiles == 0
    ) {
        return 0;
    }

    File root =
        SD.open(DECK_DIR);

    if (!root || !root.isDirectory()) {
        lastError_ =
            "sd_deck_dir_unavailable";
        return 0;
    }

    size_t count = 0;

    File entry =
        root.openNextFile();

    while (
        entry &&
        count < maxFiles
    ) {
        if (
            !entry.isDirectory() &&
            jsonFileName(
                String(entry.name()))
        ) {
            names[count] =
                baseName(
                    String(entry.name()));

            paths[count] =
                String(DECK_DIR) +
                "/" +
                names[count];

            sizes[count] =
                static_cast<uint32_t>(
                    entry.size());

            ++count;
        }

        entry.close();
        entry =
            root.openNextFile();
    }

    root.close();

    return count;
}


bool SdCardService::parseCard(
    JsonObjectConst obj,
    CardDefinition& card) const {

    card = CardDefinition{};

    card.id =
        obj["id"] | "";

    card.deckId =
        obj["deckId"] | "";

    card.deck =
        obj["deck"] |
        "Sem baralho";

    card.type =
        obj["type"] |
        "open_recall";

    if (card.type == "basic") {
        card.type =
            "open_recall";
    }

    card.format =
        obj["format"] |
        "plain";

    if (
        obj["question"].
            is<const char*>()
    ) {
        card.question =
            String(
                obj["question"].
                    as<const char*>());
    } else {
        card.question =
            String(
                obj["prompt"] |
                "");
    }

    card.answer =
        obj["answer"] | "";

    card.revision =
        obj["revision"] | 1ULL;

    card.correctOptionIndex =
        obj["correctOptionIndex"] |
        -1;

    for (
        JsonVariantConst option :
        obj["options"].
            as<JsonArrayConst>()
    ) {
        if (
            card.optionCount >=
            Config::MAX_CARD_OPTIONS
        ) {
            break;
        }

        card.options[
            card.optionCount++] =
            option.as<String>();
    }

    if (
        card.type ==
            "true_false" &&
        card.optionCount == 0
    ) {
        card.options[0] =
            "Verdadeiro";

        card.options[1] =
            "Falso";

        card.optionCount = 2;
    }

    return
        card.id.length() > 0 &&
        card.deckId.length() > 0 &&
        card.question.length() > 0;
}


int SdCardService::findCard(
    const CardDefinition* cards,
    size_t count,
    const String& id) const {

    for (
        size_t i = 0;
        i < count;
        ++i
    ) {
        if (cards[i].id == id) {
            return
                static_cast<int>(i);
        }
    }

    return -1;
}


SdImportResult SdCardService::importDeckFile(
    const String& path,
    CardDefinition* cards,
    CardState* states,
    size_t maxCards,
    size_t& count) {

    SdImportResult result;

    if (!mounted_) {
        result.error =
            "Cartão não montado";
        return result;
    }

    File file =
        SD.open(
            path,
            FILE_READ);

    if (!file) {
        result.error =
            "Não foi possível abrir o arquivo";
        return result;
    }

    JsonDocument doc;

    const DeserializationError error =
        deserializeJson(
            doc,
            file);

    file.close();

    if (error) {
        result.error =
            "JSON inválido";
        return result;
    }

    if (!doc["cards"].is<JsonArray>()) {
        result.error =
            "Arquivo sem lista de cards";
        return result;
    }

    JsonArrayConst items =
        doc["cards"].
            as<JsonArrayConst>();

    for (
        JsonObjectConst obj :
        items
    ) {
        CardDefinition incoming;

        if (!parseCard(
                obj,
                incoming)) {
            ++result.skipped;
            continue;
        }

        const int existing =
            findCard(
                cards,
                count,
                incoming.id);

        if (existing >= 0) {
            CardDefinition& current =
                cards[existing];

            if (
                incoming.revision <
                current.revision
            ) {
                ++result.skipped;
                continue;
            }

            // Definition changes do not overwrite the CardState.
            current = incoming;
            ++result.updated;
            continue;
        }

        if (count >= maxCards) {
            ++result.skipped;
            continue;
        }

        cards[count] =
            incoming;

        states[count] =
            CardState{};

        states[count].id =
            incoming.id;

        ++count;
        ++result.added;
    }

    result.ok =
        result.added > 0 ||
        result.updated > 0 ||
        result.skipped == 0;

    if (!result.ok) {
        result.error =
            "Nenhum card importado";
    }

    Serial.printf(
        "[sd] import %s: +%u ~%u skip=%u\n",
        path.c_str(),
        result.added,
        result.updated,
        result.skipped);

    return result;
}


bool SdCardService::exportLibrary(
    const CardDefinition* cards,
    size_t count,
    String& exportedPath) {

    exportedPath = "";

    if (!mounted_) {
        lastError_ =
            "sd_not_mounted";
        return false;
    }

    if (!ensureFolders()) {
        lastError_ =
            "sd_folder_failed";
        return false;
    }

    const String path =
        String(EXPORT_DIR) +
        "/library.json";

    File file =
        SD.open(
            path,
            FILE_WRITE);

    if (!file) {
        lastError_ =
            "sd_export_open_failed";
        return false;
    }

    JsonDocument doc;

    doc["schema"] =
        "mnemos.local-library/v2";

    JsonArray items =
        doc["cards"].
            to<JsonArray>();

    for (
        size_t i = 0;
        i < count;
        ++i
    ) {
        const CardDefinition& card =
            cards[i];

        JsonObject obj =
            items.add<JsonObject>();

        obj["id"] =
            card.id;
        obj["deckId"] =
            card.deckId;
        obj["deck"] =
            card.deck;
        obj["type"] =
            card.type;
        obj["format"] =
            card.format;
        obj["question"] =
            card.question;
        obj["answer"] =
            card.answer;
        obj["revision"] =
            card.revision;

        if (card.optionCount > 0) {
            JsonArray options =
                obj["options"].
                    to<JsonArray>();

            for (
                uint8_t o = 0;
                o < card.optionCount;
                ++o
            ) {
                options.add(
                    card.options[o]);
            }

            obj["correctOptionIndex"] =
                card.correctOptionIndex;
        }
    }

    const size_t written =
        serializeJsonPretty(
            doc,
            file);

    file.flush();
    file.close();

    if (written == 0) {
        lastError_ =
            "sd_export_write_failed";
        return false;
    }

    exportedPath =
        path;

    lastError_ = "";

    Serial.printf(
        "[sd] biblioteca exportada: %s (%u cards)\n",
        path.c_str(),
        static_cast<unsigned>(count));

    return true;
}
