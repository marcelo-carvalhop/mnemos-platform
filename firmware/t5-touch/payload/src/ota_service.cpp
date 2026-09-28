#include "ota_service.h"

#include <ArduinoJson.h>
#include <SD.h>
#include <Update.h>
#include <esp_ota_ops.h>
#include <mbedtls/sha256.h>

#include "config.h"

namespace {

bool isHex64(
    const String& value) {

    if (value.length() != 64) {
        return false;
    }

    for (
        size_t i = 0;
        i < value.length();
        ++i
    ) {
        const char c =
            value[i];

        const bool hex =
            (
                c >= '0' &&
                c <= '9'
            ) ||
            (
                c >= 'a' &&
                c <= 'f'
            ) ||
            (
                c >= 'A' &&
                c <= 'F'
            );

        if (!hex) {
            return false;
        }
    }

    return true;
}


String lowerHex(
    const uint8_t* digest,
    size_t count) {

    static const char HEX[] =
        "0123456789abcdef";

    String result;
    result.reserve(
        count * 2);

    for (
        size_t i = 0;
        i < count;
        ++i
    ) {
        result +=
            HEX[
                (
                    digest[i] >>
                    4
                ) &
                0x0F];

        result +=
            HEX[
                digest[i] &
                0x0F];
    }

    return result;
}

}  // namespace


void OtaService::begin() {
    const esp_partition_t* running =
        esp_ota_get_running_partition();

    const esp_partition_t* next =
        esp_ota_get_next_update_partition(
            nullptr);

    Serial.printf(
        "[ota] running=%s next=%s generation=%lu\n",
        running
            ? running->label
            : "?",
        next
            ? next->label
            : "?",
        static_cast<unsigned long>(
            Config::OTA_GENERATION));

#if defined(CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE) && CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE
    Serial.println(
        "[ota] bootloader rollback=enabled");
#else
    Serial.println(
        "[ota] bootloader rollback=not-enabled");
#endif
}


bool OtaService::loadLocalManifest(
    OtaManifest& manifest) {

    if (
        !SD.exists(
            Config::
                OTA_LOCAL_MANIFEST_PATH)
    ) {
        lastError_ = "";
        return false;
    }

    File file =
        SD.open(
            Config::
                OTA_LOCAL_MANIFEST_PATH,
            FILE_READ);

    if (!file) {
        lastError_ =
            "manifest_open_failed";

        return false;
    }

    JsonDocument doc;

    const DeserializationError error =
        deserializeJson(
            doc,
            file);

    file.close();

    if (error) {
        lastError_ =
            "manifest_invalid_json";

        return false;
    }

    manifest.schema =
        String(
            doc["schema"] | "");

    manifest.version =
        String(
            doc["version"] | "");

    manifest.model =
        String(
            doc["model"] | "");

    manifest.file =
        String(
            doc["file"] |
            Config::
                OTA_LOCAL_IMAGE_PATH);

    manifest.sha256 =
        String(
            doc["sha256"] | "");

    manifest.sha256.toLowerCase();

    manifest.generation =
        doc["generation"] |
        0U;

    manifest.size =
        doc["size"] |
        0U;

    manifest.protocolMin =
        doc["protocolMin"] |
        0U;

    manifest.protocolMax =
        doc["protocolMax"] |
        0U;

    manifest.apply =
        doc["apply"] |
        false;

    return true;
}


bool OtaService::validateManifest(
    const OtaManifest& manifest) {

    if (
        manifest.schema !=
        "mnemos.ota/v1"
    ) {
        lastError_ =
            "manifest_schema";

        return false;
    }

    if (
        manifest.model !=
        Config::DEVICE_MODEL
    ) {
        lastError_ =
            "manifest_model";

        return false;
    }

    if (
        manifest.version.length() ==
            0 ||
        manifest.version ==
            Config::APP_VERSION
    ) {
        lastError_ =
            "manifest_version";

        return false;
    }

    if (
        manifest.generation <=
        Config::OTA_GENERATION
    ) {
        lastError_ =
            "manifest_generation_not_newer";

        return false;
    }

    if (
        manifest.protocolMin == 0 ||
        manifest.protocolMax == 0 ||
        manifest.protocolMin >
            Config::
                DEVICE_PROTOCOL_VERSION ||
        manifest.protocolMax <
            Config::
                DEVICE_PROTOCOL_VERSION
    ) {
        lastError_ =
            "manifest_protocol";

        return false;
    }

    if (
        manifest.size == 0 ||
        manifest.size >
            Config::
                OTA_MAX_IMAGE_BYTES
    ) {
        lastError_ =
            "manifest_size";

        return false;
    }

    if (!isHex64(
            manifest.sha256)) {
        lastError_ =
            "manifest_sha256";

        return false;
    }

    if (
        !manifest.file.startsWith(
            "/mnemos/update/")
    ) {
        lastError_ =
            "manifest_file_path";

        return false;
    }

    return true;
}


bool OtaService::sha256File(
    const String& path,
    String& digest,
    uint32_t& size) {

    digest = "";
    size = 0;

    File file =
        SD.open(
            path,
            FILE_READ);

    if (!file) {
        lastError_ =
            "image_open_failed";

        return false;
    }

    mbedtls_sha256_context ctx;
    mbedtls_sha256_init(
        &ctx);

    if (
        mbedtls_sha256_starts_ret(
            &ctx,
            0) != 0
    ) {
        file.close();
        mbedtls_sha256_free(
            &ctx);

        lastError_ =
            "sha256_start_failed";

        return false;
    }

    uint8_t buffer[4096];

    while (file.available()) {
        const size_t read =
            file.read(
                buffer,
                sizeof(buffer));

        if (read == 0) {
            break;
        }

        if (
            mbedtls_sha256_update_ret(
                &ctx,
                buffer,
                read) != 0
        ) {
            file.close();
            mbedtls_sha256_free(
                &ctx);

            lastError_ =
                "sha256_update_failed";

            return false;
        }

        size +=
            static_cast<uint32_t>(
                read);
    }

    uint8_t output[32];

    const int finish =
        mbedtls_sha256_finish_ret(
            &ctx,
            output);

    mbedtls_sha256_free(
        &ctx);

    file.close();

    if (finish != 0) {
        lastError_ =
            "sha256_finish_failed";

        return false;
    }

    digest =
        lowerHex(
            output,
            sizeof(output));

    return true;
}


bool OtaService::verifyImage(
    const OtaManifest& manifest) {

    if (!SD.exists(
            manifest.file)) {
        lastError_ =
            "image_missing";

        return false;
    }

    File image =
        SD.open(
            manifest.file,
            FILE_READ);

    if (!image) {
        lastError_ =
            "image_open_failed";

        return false;
    }

    const int magic =
        image.read();

    image.close();

    if (magic != 0xE9) {
        lastError_ =
            "image_magic";

        return false;
    }

    String digest;
    uint32_t actualSize = 0;

    if (
        !sha256File(
            manifest.file,
            digest,
            actualSize)
    ) {
        return false;
    }

    if (
        actualSize !=
        manifest.size
    ) {
        lastError_ =
            "image_size_mismatch";

        Serial.printf(
            "[ota] tamanho invalido expected=%lu actual=%lu\n",
            static_cast<unsigned long>(
                manifest.size),
            static_cast<unsigned long>(
                actualSize));

        return false;
    }

    if (
        digest !=
        manifest.sha256
    ) {
        lastError_ =
            "image_sha256_mismatch";

        Serial.printf(
            "[ota] SHA-256 invalido actual=%s\n",
            digest.c_str());

        return false;
    }

    Serial.printf(
        "[ota] imagem verificada version=%s size=%lu sha256=%s\n",
        manifest.version.c_str(),
        static_cast<unsigned long>(
            manifest.size),
        digest.c_str());

    return true;
}


bool OtaService::installImage(
    const OtaManifest& manifest) {

    const esp_partition_t* next =
        esp_ota_get_next_update_partition(
            nullptr);

    if (!next) {
        lastError_ =
            "ota_partition_missing";

        return false;
    }

    if (
        manifest.size >
        next->size
    ) {
        lastError_ =
            "ota_partition_too_small";

        return false;
    }

    File image =
        SD.open(
            manifest.file,
            FILE_READ);

    if (!image) {
        lastError_ =
            "image_open_failed";

        return false;
    }

    if (
        !Update.begin(
            manifest.size,
            U_FLASH)
    ) {
        image.close();

        lastError_ =
            String(
                "update_begin_") +
            String(
                Update.getError());

        return false;
    }

    uint8_t buffer[4096];
    uint32_t written = 0;

    while (
        image.available() &&
        written <
            manifest.size
    ) {
        const size_t read =
            image.read(
                buffer,
                sizeof(buffer));

        if (read == 0) {
            break;
        }

        const size_t committed =
            Update.write(
                buffer,
                read);

        if (committed != read) {
            image.close();

            Update.abort();

            lastError_ =
                String(
                    "update_write_") +
                String(
                    Update.getError());

            return false;
        }

        written +=
            static_cast<uint32_t>(
                committed);
    }

    image.close();

    if (
        written !=
        manifest.size
    ) {
        Update.abort();

        lastError_ =
            "update_written_size";

        return false;
    }

    if (!Update.end(false)) {
        lastError_ =
            String(
                "update_end_") +
            String(
                Update.getError());

        return false;
    }

    if (!Update.isFinished()) {
        lastError_ =
            "update_not_finished";

        return false;
    }

    Serial.printf(
        "[ota] instalada em %s: %s -> %s generation=%lu\n",
        next->label,
        Config::APP_VERSION,
        manifest.version.c_str(),
        static_cast<unsigned long>(
            manifest.generation));

    lastError_ = "";

    return true;
}


bool OtaService::moveManifestToApplied() {
    SD.remove(
        Config::
            OTA_APPLIED_MANIFEST_PATH);

    return
        SD.rename(
            Config::
                OTA_LOCAL_MANIFEST_PATH,
            Config::
                OTA_APPLIED_MANIFEST_PATH);
}


OtaResult OtaService::applyLocalUpdateIfRequested(
    bool batteryAvailable,
    uint8_t batteryPercent) {

    OtaManifest manifest;

    if (!loadLocalManifest(
            manifest)) {
        return
            lastError_.length() == 0
                ? OtaResult::NoUpdate
                : OtaResult::
                      InvalidManifest;
    }

    if (!manifest.apply) {
        Serial.println(
            "[ota] manifesto local presente; apply=false");

        return
            OtaResult::Skipped;
    }

    if (
        batteryAvailable &&
        batteryPercent <
            Config::
                OTA_MIN_BATTERY_PERCENT
    ) {
        lastError_ =
            "battery_too_low";

        Serial.printf(
            "[ota] bloqueada: bateria=%u%% minimo=%u%%\n",
            batteryPercent,
            Config::
                OTA_MIN_BATTERY_PERCENT);

        return
            OtaResult::UnsafePower;
    }

    if (!validateManifest(
            manifest)) {
        Serial.printf(
            "[ota] manifesto rejeitado: %s\n",
            lastError_.c_str());

        return
            OtaResult::
                InvalidManifest;
    }

    if (!verifyImage(
            manifest)) {
        Serial.printf(
            "[ota] verificacao falhou: %s\n",
            lastError_.c_str());

        return
            OtaResult::
                VerificationFailed;
    }

    if (!installImage(
            manifest)) {
        Serial.printf(
            "[ota] instalacao falhou: %s\n",
            lastError_.c_str());

        return
            OtaResult::
                InstallFailed;
    }

    moveManifestToApplied();

    Serial.println(
        "[ota] update concluido; reiniciando");

    Serial.flush();
    delay(100);

    ESP.restart();

    return
        OtaResult::Installed;
}


void OtaService::confirmRunningImage() {
#if defined(CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE) && CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE
    const esp_partition_t* running =
        esp_ota_get_running_partition();

    if (!running) {
        return;
    }

    esp_ota_img_states_t state =
        ESP_OTA_IMG_UNDEFINED;

    if (
        esp_ota_get_state_partition(
            running,
            &state) !=
        ESP_OK
    ) {
        return;
    }

    if (
        state ==
        ESP_OTA_IMG_PENDING_VERIFY
    ) {
        const esp_err_t result =
            esp_ota_mark_app_valid_cancel_rollback();

        Serial.printf(
            "[ota] confirm running=%s result=%d\n",
            running->label,
            static_cast<int>(
                result));
    }
#endif
}
