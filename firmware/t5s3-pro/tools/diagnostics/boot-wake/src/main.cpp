#include <Arduino.h>
#include <driver/rtc_io.h>
#include <esp_sleep.h>
#include <esp_system.h>

namespace {

constexpr gpio_num_t BOOT_PIN = GPIO_NUM_0;
constexpr uint32_t SLEEP_DELAY_MS = 5000;

const char* wakeName(esp_sleep_wakeup_cause_t cause) {
    switch (cause) {
        case ESP_SLEEP_WAKEUP_EXT0:
            return "EXT0";
        case ESP_SLEEP_WAKEUP_EXT1:
            return "EXT1";
        case ESP_SLEEP_WAKEUP_GPIO:
            return "GPIO";
        case ESP_SLEEP_WAKEUP_TIMER:
            return "TIMER";
        case ESP_SLEEP_WAKEUP_UNDEFINED:
            return "UNDEFINED";
        default:
            return "OTHER";
    }
}

void configureBootAsDigitalInput() {
    rtc_gpio_deinit(BOOT_PIN);
    pinMode(static_cast<int>(BOOT_PIN), INPUT_PULLUP);
}

}  // namespace

void setup() {
    Serial.begin(115200);
    delay(1500);

    const esp_sleep_wakeup_cause_t wake =
        esp_sleep_get_wakeup_cause();

    const esp_reset_reason_t reset =
        esp_reset_reason();

    configureBootAsDigitalInput();

    Serial.println();
    Serial.println("=== T5S3 Pro BOOT wake diagnostic ===");
    Serial.printf(
        "reset=%d wake=%d (%s) GPIO0=%d\n",
        static_cast<int>(reset),
        static_cast<int>(wake),
        wakeName(wake),
        digitalRead(static_cast<int>(BOOT_PIN)));

    if (wake == ESP_SLEEP_WAKEUP_EXT0) {
        Serial.println();
        Serial.println("PASS: o ESP32-S3 acordou do deep sleep pelo BOOT/GPIO0.");
        Serial.println("O diagnóstico permanecerá ligado.");
        return;
    }

    Serial.println();
    Serial.println("O dispositivo entrará em deep sleep em 5 segundos.");
    Serial.println("Depois que a serial parar, pressione e solte BOOT.");
    Serial.println("NÃO pressione RST durante o teste.");

    const uint32_t started = millis();

    while (millis() - started < SLEEP_DELAY_MS) {
        Serial.printf(
            "sleep em %lu ms | GPIO0=%d\n",
            static_cast<unsigned long>(
                SLEEP_DELAY_MS - (millis() - started)),
            digitalRead(static_cast<int>(BOOT_PIN)));
        delay(500);
    }

    while (
        digitalRead(static_cast<int>(BOOT_PIN)) == LOW
    ) {
        Serial.println("Aguardando BOOT ser solto...");
        delay(50);
    }

    const esp_err_t result =
        esp_sleep_enable_ext0_wakeup(
            BOOT_PIN,
            0);

    Serial.printf(
        "EXT0 configure result=%d | GPIO0=%d\n",
        static_cast<int>(result),
        digitalRead(static_cast<int>(BOOT_PIN)));

    if (result != ESP_OK) {
        Serial.println(
            "FAIL: não foi possível configurar EXT0. "
            "O dispositivo NÃO entrará em deep sleep.");
        return;
    }

    Serial.println("Entrando em deep sleep agora.");
    Serial.flush();
    delay(100);

    esp_deep_sleep_start();
}

void loop() {
    static int lastLevel = HIGH;

    const int level =
        digitalRead(
            static_cast<int>(BOOT_PIN));

    if (level != lastLevel) {
        Serial.printf(
            "GPIO0 %s\n",
            level == LOW
                ? "LOW (BOOT pressionado)"
                : "HIGH (BOOT solto)");
        lastLevel = level;
    }

    delay(10);
}
