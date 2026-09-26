#include "cardkb_input.h"

#include "config.h"

CardKbInput::CardKbInput() : wire_(1) {}

bool CardKbInput::configureBus(int sda, int scl) {
    if (busStarted_) {
        wire_.end();
        delay(5);
        busStarted_ = false;
    }

    pinMode(sda, INPUT_PULLUP);
    pinMode(scl, INPUT_PULLUP);

    busStarted_ = wire_.begin(sda, scl, Config::CARDKB_I2C_FREQUENCY);
    activeSda_ = sda;
    activeScl_ = scl;

    delay(25);

    Serial.printf("[cardkb][diag] barramento SDA=%d SCL=%d begin=%s idle(SDA=%d,SCL=%d)\n",
                  sda,
                  scl,
                  busStarted_ ? "ok" : "falhou",
                  digitalRead(sda),
                  digitalRead(scl));

    return busStarted_;
}

bool CardKbInput::addressResponds(uint8_t address) {
    if (!busStarted_) return false;
    wire_.beginTransmission(address);
    return wire_.endTransmission() == 0;
}

bool CardKbInput::scanAndSelect(int sda, int scl) {
    if (!configureBus(sda, scl)) return false;

    uint8_t found = 0;
    bool cardKbFound = false;

    Serial.printf("[cardkb][diag] varrendo I2C em SDA=%d SCL=%d...\n", sda, scl);

    for (uint8_t address = 1; address < 127; ++address) {
        wire_.beginTransmission(address);
        const uint8_t error = wire_.endTransmission();

        if (error == 0) {
            ++found;
            Serial.printf("[cardkb][diag] ACK em 0x%02X%s\n",
                          address,
                          address == Config::CARDKB_I2C_ADDRESS ? " <- CardKB esperado" : "");
            if (address == Config::CARDKB_I2C_ADDRESS) cardKbFound = true;
        }
    }

    if (found == 0) {
        Serial.printf("[cardkb][diag] nenhum endereco respondeu em SDA=%d SCL=%d\n", sda, scl);
    }

    if (cardKbFound) {
        online_ = true;
        activeSda_ = sda;
        activeScl_ = scl;
        Serial.printf("[cardkb] ONLINE em SDA=%d SCL=%d addr=0x%02X\n",
                      activeSda_, activeScl_, Config::CARDKB_I2C_ADDRESS);
        return true;
    }

    return false;
}

bool CardKbInput::begin() {
    online_ = false;

    Serial.printf("[cardkb][diag] CardKB esperado em 0x%02X, I2C=%lu Hz\n",
                  Config::CARDKB_I2C_ADDRESS,
                  static_cast<unsigned long>(Config::CARDKB_I2C_FREQUENCY));

    // Primeiro testa a ligação planejada.
    if (scanAndSelect(Config::CARDKB_SDA, Config::CARDKB_SCL)) return true;

    // Depois testa SDA/SCL invertidos sem exigir alteração física.
    if (Config::CARDKB_SDA != Config::CARDKB_SCL &&
        scanAndSelect(Config::CARDKB_SCL, Config::CARDKB_SDA)) {
        Serial.println("[cardkb][diag] ATENCAO: SDA/SCL estao invertidos fisicamente.");
        return true;
    }

    // Se nada respondeu, retorna ao mapeamento planejado para permitir
    // reconexão posterior e manter o estado previsível.
    configureBus(Config::CARDKB_SDA, Config::CARDKB_SCL);
    online_ = false;

    Serial.printf("[cardkb] NAO ENCONTRADO: addr=0x%02X; testados %d/%d e %d/%d\n",
                  Config::CARDKB_I2C_ADDRESS,
                  Config::CARDKB_SDA, Config::CARDKB_SCL,
                  Config::CARDKB_SCL, Config::CARDKB_SDA);
    return false;
}

bool CardKbInput::probe() {
    if (!busStarted_) {
        if (!configureBus(Config::CARDKB_SDA, Config::CARDKB_SCL)) {
            online_ = false;
            return false;
        }
    }

    online_ = addressResponds(Config::CARDKB_I2C_ADDRESS);
    return online_;
}

uint8_t CardKbInput::pollKey() {
    if (!online_) return 0;
    const uint32_t now = millis();
    if (now - lastPollMs_ < Config::CARDKB_POLL_MS) return 0;
    lastPollMs_ = now;

    const uint8_t requested = wire_.requestFrom(Config::CARDKB_I2C_ADDRESS, static_cast<uint8_t>(1));
    if (requested != 1 || !wire_.available()) return 0;
    return static_cast<uint8_t>(wire_.read());
}

bool CardKbInput::printable(uint8_t key) {
    return key >= 0x20 && key <= 0x7E;
}
