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

constexpr const char* UPDATE_DIR =
    "/mnemos/update";


constexpr const char* LIBRARY_DIR =
    "/mnemos/library";

constexpr const char* CANONICAL_LIBRARY_PATH =
    "/mnemos/library/cards.ndjson";

constexpr const char* TEMP_CANONICAL_LIBRARY_PATH =
    "/mnemos/library/cards.tmp";

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

bool serializeCardLine(
    const CardDefinition& card,
    String& line) {

    if (
        card.id.length() == 0 ||
        card.deckId.length() == 0 ||
        card.question.length() == 0
    ) {
        return false;
    }

    JsonDocument doc;

    doc["schema"] =
        "mnemos.sd-card/v1";

    doc["id"] =
        card.id;

    doc["deckId"] =
        card.deckId;

    doc["deck"] =
        card.deck;

    doc["type"] =
        card.type;

    doc["format"] =
        card.format;

    doc["question"] =
        card.question;

    doc["answer"] =
        card.answer;

    doc["revision"] =
        card.revision;

    if (card.optionCount > 0) {
        JsonArray options =
            doc["options"].
                to<JsonArray>();

        for (
            uint8_t i = 0;
            i < card.optionCount;
            ++i
        ) {
            options.add(
                card.options[i]);
        }

        doc["correctOptionIndex"] =
            card.correctOptionIndex;
    }

    line = "";

    return
        serializeJson(
            doc,
            line) > 0;
}


void makeCatalogStub(
    const CardDefinition& full,
    CardDefinition& stub) {

    stub =
        full;

    stub.question = "";
    stub.answer = "";

    for (
        uint8_t i = 0;
        i < Config::MAX_CARD_OPTIONS;
        ++i
    ) {
        stub.options[i] = "";
    }

    stub.optionCount = 0;
    stub.correctOptionIndex = -1;
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


void SdCardService::suspend() {
    if (!mounted_) {
        return;
    }

    SD.end();
    SPI.end();
    mounted_ = false;

    Serial.println(
        "[sd] suspenso para economia de energia");
}


bool SdCardService::resume() {
    return remount();
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

    if (!SD.exists(UPDATE_DIR)) {
        if (!SD.mkdir(UPDATE_DIR)) {
            return false;
        }
    }

    if (!SD.exists(LIBRARY_DIR)) {
        if (!SD.mkdir(LIBRARY_DIR)) {
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


bool SdCardService::canonicalLibraryAvailable() const {
    return
        mounted_ &&
        SD.exists(
            CANONICAL_LIBRARY_PATH);
}


bool SdCardService::saveCanonicalLibrary(
    const CardDefinition* cards,
    size_t count) {

    if (
        !mounted_ ||
        !cards
    ) {
        lastError_ =
            "sd_not_mounted";
        return false;
    }

    if (!ensureFolders()) {
        lastError_ =
            "sd_folder_failed";
        return false;
    }

    SD.remove(
        TEMP_CANONICAL_LIBRARY_PATH);

    File file =
        SD.open(
            TEMP_CANONICAL_LIBRARY_PATH,
            FILE_WRITE);

    if (!file) {
        lastError_ =
            "canonical_open_failed";
        return false;
    }

    size_t writtenCards = 0;

    for (
        size_t i = 0;
        i < count;
        ++i
    ) {
        String line;

        if (
            !serializeCardLine(
                cards[i],
                line)
        ) {
            file.close();

            SD.remove(
                TEMP_CANONICAL_LIBRARY_PATH);

            lastError_ =
                "canonical_source_not_hydrated";

            Serial.printf(
                "[sd] canonical recusado: card %u sem conteudo completo\n",
                static_cast<unsigned>(i));

            return false;
        }

        if (
            file.println(line) == 0
        ) {
            file.close();

            SD.remove(
                TEMP_CANONICAL_LIBRARY_PATH);

            lastError_ =
                "canonical_write_failed";

            return false;
        }

        ++writtenCards;
    }

    file.flush();
    file.close();

    SD.remove(
        CANONICAL_LIBRARY_PATH);

    if (
        !SD.rename(
            TEMP_CANONICAL_LIBRARY_PATH,
            CANONICAL_LIBRARY_PATH)
    ) {
        lastError_ =
            "canonical_rename_failed";

        return false;
    }

    lastError_ = "";

    Serial.printf(
        "[sd] biblioteca canonica gravada: %u cards\n",
        static_cast<unsigned>(
            writtenCards));

    return true;
}


bool SdCardService::loadCatalog(
    CardDefinition* cards,
    CardState* states,
    size_t maxCards,
    size_t& count) {

    count = 0;

    if (
        !mounted_ ||
        !cards ||
        !states ||
        maxCards == 0 ||
        !canonicalLibraryAvailable()
    ) {
        return false;
    }

    File file =
        SD.open(
            CANONICAL_LIBRARY_PATH,
            FILE_READ);

    if (!file) {
        lastError_ =
            "canonical_open_failed";

        return false;
    }

    while (
        file.available() &&
        count < maxCards
    ) {
        String line =
            file.readStringUntil(
                '\n');

        line.trim();

        if (line.length() == 0) {
            continue;
        }

        JsonDocument doc;

        if (
            deserializeJson(
                doc,
                line)
        ) {
            file.close();

            lastError_ =
                "canonical_invalid_json";

            return false;
        }

        CardDefinition full;

        if (
            !parseCard(
                doc.as<JsonObjectConst>(),
                full)
        ) {
            file.close();

            lastError_ =
                "canonical_invalid_card";

            return false;
        }

        makeCatalogStub(
            full,
            cards[count]);

        states[count] =
            CardState{};

        states[count].id =
            cards[count].id;

        ++count;
    }

    const bool overflow =
        file.available();

    file.close();

    if (overflow) {
        lastError_ =
            "catalog_capacity_exceeded";

        Serial.printf(
            "[sd] catalogo limitado a %u cards; ha conteudo adicional no SD\n",
            static_cast<unsigned>(
                maxCards));
    } else {
        lastError_ = "";
    }

    Serial.printf(
        "[sd] catalogo leve carregado: %u cards heap=%u\n",
        static_cast<unsigned>(
            count),
        static_cast<unsigned>(
            ESP.getFreeHeap()));

    return
        count > 0;
}


bool SdCardService::hydrateCard(
    const String& id,
    CardDefinition& card) {

    if (
        !canonicalLibraryAvailable() ||
        id.length() == 0
    ) {
        return false;
    }

    File file =
        SD.open(
            CANONICAL_LIBRARY_PATH,
            FILE_READ);

    if (!file) {
        return false;
    }

    while (file.available()) {
        String line =
            file.readStringUntil(
                '\n');

        line.trim();

        if (line.length() == 0) {
            continue;
        }

        JsonDocument doc;

        if (
            deserializeJson(
                doc,
                line)
        ) {
            continue;
        }

        if (
            String(
                doc["id"] | "") !=
            id
        ) {
            continue;
        }

        const bool ok =
            parseCard(
                doc.as<JsonObjectConst>(),
                card);

        file.close();

        if (!ok) {
            lastError_ =
                "canonical_card_invalid";
        }

        return ok;
    }

    file.close();

    lastError_ =
        "canonical_card_not_found";

    return false;
}


void SdCardService::compactCatalog(
    CardDefinition* cards,
    size_t count) {

    if (!cards) {
        return;
    }

    const uint32_t before =
        ESP.getFreeHeap();

    for (
        size_t i = 0;
        i < count;
        ++i
    ) {
        cards[i].question = "";
        cards[i].answer = "";

        for (
            uint8_t o = 0;
            o < Config::MAX_CARD_OPTIONS;
            ++o
        ) {
            cards[i].options[o] = "";
        }

        cards[i].optionCount = 0;
        cards[i].correctOptionIndex = -1;
    }

    const uint32_t after =
        ESP.getFreeHeap();

    Serial.printf(
        "[sd] catalogo compactado heap=%u -> %u (+%ld)\n",
        static_cast<unsigned>(
            before),
        static_cast<unsigned>(
            after),
        static_cast<long>(
            after) -
            static_cast<long>(
                before));
}


SdImportResult SdCardService::importDeckFileToCanonical(
    const String& path,
    size_t maxCards) {

    SdImportResult result;

    if (
        !mounted_ ||
        maxCards == 0
    ) {
        result.error =
            "Cartao nao montado";

        return result;
    }

    File incomingFile =
        SD.open(
            path,
            FILE_READ);

    if (!incomingFile) {
        result.error =
            "Nao foi possivel abrir o arquivo";

        return result;
    }

    JsonDocument incomingDoc;

    const DeserializationError parseError =
        deserializeJson(
            incomingDoc,
            incomingFile);

    incomingFile.close();

    if (parseError) {
        result.error =
            "JSON invalido";

        return result;
    }

    const String schema =
        incomingDoc["schema"] | "";

    if (
        schema.length() > 0 &&
        schema !=
            "mnemos.local-library/v2" &&
        schema !=
            "mnemos.local-library/v3"
    ) {
        result.error =
            "Schema de deck incompativel";

        return result;
    }

    if (
        !incomingDoc["cards"].
            is<JsonArray>()
    ) {
        result.error =
            "Arquivo sem lista de cards";

        return result;
    }

    JsonArray incoming =
        incomingDoc["cards"].
            as<JsonArray>();

    if (!ensureFolders()) {
        result.error =
            "Falha ao preparar biblioteca no SD";

        return result;
    }

    SD.remove(
        TEMP_CANONICAL_LIBRARY_PATH);

    File output =
        SD.open(
            TEMP_CANONICAL_LIBRARY_PATH,
            FILE_WRITE);

    if (!output) {
        result.error =
            "Falha ao abrir biblioteca temporaria";

        return result;
    }

    size_t written = 0;

    if (canonicalLibraryAvailable()) {
        File current =
            SD.open(
                CANONICAL_LIBRARY_PATH,
                FILE_READ);

        while (
            current &&
            current.available() &&
            written < maxCards
        ) {
            String line =
                current.readStringUntil(
                    '\n');

            line.trim();

            if (line.length() == 0) {
                continue;
            }

            JsonDocument existingDoc;

            if (
                deserializeJson(
                    existingDoc,
                    line)
            ) {
                continue;
            }

            const String id =
                existingDoc["id"] | "";

            const uint64_t oldRevision =
                existingDoc["revision"] |
                1ULL;

            bool replaced = false;

            for (
                JsonObject item :
                incoming
            ) {
                if (
                    item["_mnemos_used"] |
                    false
                ) {
                    continue;
                }

                if (
                    String(
                        item["id"] | "") !=
                    id
                ) {
                    continue;
                }

                CardDefinition candidate;

                if (
                    !parseCard(
                        item,
                        candidate)
                ) {
                    item["_mnemos_used"] =
                        true;

                    ++result.skipped;
                    break;
                }

                if (
                    candidate.revision <
                    oldRevision
                ) {
                    ++result.skipped;
                } else {
                    String replacement;

                    if (
                        !serializeCardLine(
                            candidate,
                            replacement)
                    ) {
                        output.close();
                        current.close();

                        SD.remove(
                            TEMP_CANONICAL_LIBRARY_PATH);

                        result.error =
                            "Falha ao serializar card";

                        return result;
                    }

                    output.println(
                        replacement);

                    ++result.updated;
                    replaced = true;
                }

                item["_mnemos_used"] =
                    true;
                break;
            }

            if (!replaced) {
                output.println(line);
            }

            ++written;
        }

        if (current) {
            current.close();
        }
    }

    for (
        JsonObject item :
        incoming
    ) {
        if (
            item["_mnemos_used"] |
            false
        ) {
            item.remove(
                "_mnemos_used");

            continue;
        }

        if (written >= maxCards) {
            ++result.skipped;
            continue;
        }

        CardDefinition candidate;

        if (
            !parseCard(
                item,
                candidate)
        ) {
            ++result.skipped;
            continue;
        }

        String line;

        if (
            !serializeCardLine(
                candidate,
                line)
        ) {
            ++result.skipped;
            continue;
        }

        output.println(line);

        ++written;
        ++result.added;
    }

    output.flush();
    output.close();

    SD.remove(
        CANONICAL_LIBRARY_PATH);

    if (
        !SD.rename(
            TEMP_CANONICAL_LIBRARY_PATH,
            CANONICAL_LIBRARY_PATH)
    ) {
        result.error =
            "Falha ao ativar biblioteca importada";

        return result;
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
        "[sd] canonical import %s: +%u ~%u skip=%u total=%u\n",
        path.c_str(),
        result.added,
        result.updated,
        result.skipped,
        static_cast<unsigned>(
            written));

    return result;
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

    SD.remove(path);

    File output =
        SD.open(
            path,
            FILE_WRITE);

    if (!output) {
        lastError_ =
            "sd_export_open_failed";

        return false;
    }

    output.print(
        "{\"schema\":\"mnemos.local-library/v3\",\"cards\":[");

    bool first = true;
    size_t exported = 0;

    if (canonicalLibraryAvailable()) {
        File source =
            SD.open(
                CANONICAL_LIBRARY_PATH,
                FILE_READ);

        while (
            source &&
            source.available()
        ) {
            String line =
                source.readStringUntil(
                    '\n');

            line.trim();

            if (line.length() == 0) {
                continue;
            }

            if (!first) {
                output.print(',');
            }

            output.print(line);

            first = false;
            ++exported;
        }

        if (source) {
            source.close();
        }
    } else {
        for (
            size_t i = 0;
            i < count;
            ++i
        ) {
            String line;

            if (
                !serializeCardLine(
                    cards[i],
                    line)
            ) {
                continue;
            }

            if (!first) {
                output.print(',');
            }

            output.print(line);

            first = false;
            ++exported;
        }
    }

    output.print("]}");
    output.flush();
    output.close();

    if (exported == 0) {
        SD.remove(path);

        lastError_ =
            "sd_export_empty";

        return false;
    }

    exportedPath =
        path;

    lastError_ = "";

    Serial.printf(
        "[sd] biblioteca exportada: %s (%u cards)\n",
        path.c_str(),
        static_cast<unsigned>(
            exported));

    return true;
}

