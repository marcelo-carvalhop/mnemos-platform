#include "cyd_display.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include "config.h"
#include <qrcode.h>

namespace {
constexpr int TOUCH_IRQ = 36;
constexpr int TOUCH_MOSI = 32;
constexpr int TOUCH_MISO = 39;
constexpr int TOUCH_CLK = 25;
constexpr int TOUCH_CS = 33;
constexpr int BOOT_BUTTON = 0;

constexpr uint16_t COLOR_BG = 0xF79D;       // Marfim Calmo #F4F1E8
constexpr uint16_t COLOR_TEXT = 0x18E3;     // Grafite Profundo #1F1F1F
constexpr uint16_t COLOR_MUTED = 0x7C4E;    // Salvia Analogica #7A8B72
constexpr uint16_t COLOR_ACCENT = 0x32AC;   // Azul Petroleo #365462
constexpr uint16_t COLOR_BORDER = 0xDEB9;   // Cinza Nevoa #D9D5CC
constexpr uint16_t COLOR_SELECTED = 0xBD0F; // Latao Fosco #B8A27A
constexpr uint16_t COLOR_DISABLED = 0xDEB9;
constexpr uint16_t COLOR_DANGER = 0xB36A;   // Terracota Contida #B56E52
}

CydDisplay::CydDisplay()
    : touch_(TOUCH_CS, TOUCH_IRQ) {}

void CydDisplay::begin() {
    pinMode(BOOT_BUTTON, INPUT_PULLUP);
    pinMode(TFT_BL, OUTPUT);
    digitalWrite(TFT_BL, HIGH);

    tft_.init();
    tft_.setRotation(0);
    tft_.setTextWrap(false);

    // O TFT usa HSPI (USE_HSPI_PORT). O touch usa o objeto SPI global,
    // que no ESP32 corresponde ao VSPI, inicializado com a pinagem própria do CYD.
    SPI.begin(TOUCH_CLK, TOUCH_MISO, TOUCH_MOSI, TOUCH_CS);
    touch_.begin();

    preferences_.begin("mnemos-touch", false);
    calibration_.valid = preferences_.getBool("valid", false);
    calibration_.x0 = preferences_.getInt("x0", 200);
    calibration_.x1 = preferences_.getInt("x1", 3800);
    calibration_.y0 = preferences_.getInt("y0", 200);
    calibration_.y1 = preferences_.getInt("y1", 3800);
    calibration_.swapAxes = preferences_.getBool("swap", false);

    const bool forceCalibration = digitalRead(BOOT_BUTTON) == LOW;
    if (!calibration_.valid || forceCalibration) calibrateTouch();
}

void CydDisplay::clear(uint16_t color) {
    tft_.fillScreen(color);
    clearButtons();
}

void CydDisplay::clearButtons() {
    buttonCount_ = 0;
}

void CydDisplay::drawCentered(const String& text, int16_t y, uint8_t font, uint16_t color) {
    tft_.setTextFont(font);
    tft_.setTextColor(color, COLOR_BG);
    tft_.setTextDatum(TC_DATUM);
    tft_.drawString(text, WIDTH / 2, y);
    tft_.setTextDatum(TL_DATUM);
}

void CydDisplay::drawHeader(const String& title, const String& rightText) {
    tft_.fillRect(0, 0, WIDTH, 32, COLOR_TEXT);
    tft_.setTextFont(2);
    tft_.setTextColor(TFT_WHITE, COLOR_TEXT);
    tft_.setTextDatum(ML_DATUM);
    tft_.drawString(title, 8, 16);
    if (rightText.length() != 0) {
        tft_.setTextDatum(MR_DATUM);
        tft_.drawString(rightText, WIDTH - 8, 16);
    }
    tft_.setTextDatum(TL_DATUM);
}

void CydDisplay::drawButton(int16_t x, int16_t y, int16_t w, int16_t h,
                            const String& label, UiAction action,
                            bool selected, bool enabled) {
    const uint16_t fill = !enabled ? COLOR_DISABLED : (selected ? COLOR_SELECTED : TFT_WHITE);
    const uint16_t border = !enabled ? COLOR_MUTED : (selected ? COLOR_ACCENT : COLOR_BORDER);
    const uint16_t text = !enabled ? COLOR_MUTED : COLOR_TEXT;

    tft_.fillRoundRect(x, y, w, h, 6, fill);
    tft_.drawRoundRect(x, y, w, h, 6, border);
    tft_.setTextFont(2);
    tft_.setTextColor(text, fill);
    tft_.setTextDatum(MC_DATUM);
    tft_.drawString(label, x + w / 2, y + h / 2);
    tft_.setTextDatum(TL_DATUM);

    if (enabled && action != UiAction::None && buttonCount_ < MAX_BUTTONS) {
        buttons_[buttonCount_++] = Button{x, y, w, h, action};
    }
}

int16_t CydDisplay::drawWrappedText(const String& text,
                                    int16_t x, int16_t y, int16_t maxWidth,
                                    uint8_t font, uint16_t color,
                                    int16_t lineHeight, uint8_t maxLines) {
    tft_.setTextFont(font);
    tft_.setTextColor(color, COLOR_BG);
    tft_.setTextDatum(TL_DATUM);

    String line;
    String word;
    uint8_t lines = 0;

    auto flushLine = [&]() {
        if (lines >= maxLines) return;
        tft_.drawString(line, x, y + lines * lineHeight);
        ++lines;
        line = "";
    };

    for (size_t i = 0; i <= text.length(); ++i) {
        const char c = i < text.length() ? text[i] : ' ';
        if (c != ' ' && c != '\n') {
            word += c;
            continue;
        }

        if (word.length() != 0) {
            const String candidate = line.length() == 0 ? word : line + " " + word;
            if (tft_.textWidth(candidate) > maxWidth && line.length() != 0) {
                flushLine();
                if (lines >= maxLines) break;
                line = word;
            } else {
                line = candidate;
            }
            word = "";
        }

        if (c == '\n' && line.length() != 0) {
            flushLine();
            if (lines >= maxLines) break;
        }
    }

    if (line.length() != 0 && lines < maxLines) flushLine();
    return y + lines * lineHeight;
}

void CydDisplay::showBoot(const String& message) {
    clear();
    drawCentered("MNEMOS", 78, 4, COLOR_TEXT);
    drawCentered("Terminal de estudos", 120, 2, COLOR_MUTED);
    drawCentered(message, 190, 2, COLOR_ACCENT);
    drawCentered(String("v") + Config::APP_VERSION, 286, 2, COLOR_MUTED);
}

void CydDisplay::showHome(uint16_t due, size_t total, bool trustedClock, bool canResume) {
    clear();
    drawHeader("MNEMOS");

    drawCentered(due == 0 ? "Nada pendente" : String(due) + " revisoes", 72, 3,
                 due == 0 ? COLOR_MUTED : COLOR_ACCENT);
    drawCentered(String(total) + " cards no dispositivo", 112, 2, COLOR_MUTED);
    if (!trustedClock) drawCentered("Relogio aproximado", 136, 2, COLOR_MUTED);

    drawButton(24, 174, 192, 38, canResume ? "CONTINUAR SESSAO" : "INICIAR SESSAO",
               UiAction::Start, false, canResume || due > 0);
    drawButton(24, 220, 192, 38, "SINCRONIZACAO", UiAction::OpenSync);
    drawButton(24, 266, 192, 38, "CONEXAO", UiAction::OpenConnection);
}

void CydDisplay::showSyncMenu(size_t total, uint16_t pendingReviews, bool wifiConnected) {
    clear();
    drawHeader("Sincronizacao", wifiConnected ? "Wi-Fi" : "Offline");
    drawCentered(String(total) + " cards no Mnemos", 62, 2, COLOR_TEXT);
    drawCentered(String(pendingReviews) + " revisoes aguardando", 88, 2,
                 pendingReviews > 0 ? COLOR_ACCENT : COLOR_MUTED);

    drawButton(24, 146, 192, 40, "SINCRONIZAR AGORA", UiAction::SyncBackend, false, wifiConnected);
    drawButton(24, 196, 192, 40, "CELULAR / BLUETOOTH", UiAction::SyncBluetooth);
    drawButton(40, 270, 160, 34, "VOLTAR", UiAction::Back);
}

void CydDisplay::showConnectionMenu(bool wifiEnabled,
                                    bool wifiConnected,
                                    const String& ssid,
                                    size_t knownNetworks) {
    clear();
    drawHeader("Conexao");
    const String state = !wifiEnabled ? "Wi-Fi desligado" :
                         (wifiConnected ? "Conectado" : "Sem conexao");
    drawCentered(state, 62, 2, wifiConnected ? COLOR_ACCENT : COLOR_MUTED);
    if (wifiConnected && ssid.length() > 0) drawCentered(ssid, 88, 2, COLOR_TEXT);
    drawCentered(String(knownNetworks) + " redes conhecidas", 114, 2, COLOR_MUTED);

    drawButton(24, 164, 192, 40, "CONFIGURAR REDE", UiAction::ConfigureNetwork);
    drawButton(24, 214, 192, 40,
               wifiEnabled ? "DESLIGAR WI-FI" : "LIGAR WI-FI", UiAction::ToggleWifi);
    drawButton(40, 270, 160, 34, "VOLTAR", UiAction::Back);
}

void CydDisplay::showBluetoothSync(const String& deviceId, bool connected) {
    clear();
    drawHeader("Bluetooth", connected ? "Conectado" : "Aguardando");
    drawCentered("Sincronizacao local", 70, 2, COLOR_TEXT);
    drawCentered(deviceId, 98, 2, COLOR_ACCENT);
    drawWrappedText("Abra Sincronizacao no app e escolha Bluetooth. O radio sera desligado ao concluir.",
                    18, 132, 204, 2, COLOR_MUTED, 20, 5);
    drawButton(40, 270, 160, 34, "CANCELAR", UiAction::CancelBluetooth);
}

void CydDisplay::showPairing(const String& qrPayload, const String& ssid, const String& password) {
    clear();
    drawHeader("Configurar Mnemos", "5 min");

    constexpr uint8_t QR_VERSION = 8;
    const uint16_t qrBufferSize = qrcode_getBufferSize(QR_VERSION);
    std::unique_ptr<uint8_t[]> qrcodeData(new uint8_t[qrBufferSize]);
    QRCode qrcode;
    const int8_t status = qrcode_initText(&qrcode, qrcodeData.get(), QR_VERSION, ECC_LOW, qrPayload.c_str());

    if (status == 0) {
        const int scale = 3;
        const int quiet = 2;
        const int qrPixels = (qrcode.size + quiet * 2) * scale;
        const int originX = (WIDTH - qrPixels) / 2;
        const int originY = 34;
        tft_.fillRect(originX, originY, qrPixels, qrPixels, TFT_WHITE);
        for (uint8_t y = 0; y < qrcode.size; ++y) {
            for (uint8_t x = 0; x < qrcode.size; ++x) {
                if (qrcode_getModule(&qrcode, x, y)) {
                    tft_.fillRect(originX + (x + quiet) * scale,
                                  originY + (y + quiet) * scale,
                                  scale, scale, COLOR_TEXT);
                }
            }
        }
    } else {
        drawCentered("Falha ao gerar QR Code", 90, 2, COLOR_DANGER);
    }

    drawCentered("Escaneie para configurar", 202, 2, COLOR_TEXT);
    drawCentered(ssid, 224, 2, COLOR_ACCENT);
    drawCentered("Senha: " + password, 244, 2, COLOR_MUTED);
    drawButton(40, 278, 160, 34, "CANCELAR", UiAction::CancelPairing);
}

void CydDisplay::showQuestion(const CardDefinition& card,
                              uint8_t position,
                              uint8_t total,
                              Confidence confidence) {
    clear();
    drawHeader(card.deck, String(position + 1) + "/" + String(total));

    drawWrappedText(card.question, 12, 46, 216, 2, COLOR_TEXT, 22, 6);

    tft_.drawFastHLine(12, 184, 216, COLOR_BORDER);
    drawCentered("Voce acredita que sabe?", 194, 2, COLOR_MUTED);

    drawButton(8, 220, 70, 38, "Nao sei", UiAction::ConfidenceDontKnow,
               confidence == Confidence::DontKnow);
    drawButton(85, 220, 70, 38, "Talvez", UiAction::ConfidenceMaybe,
               confidence == Confidence::Maybe);
    drawButton(162, 220, 70, 38, "Certeza", UiAction::ConfidenceCertain,
               confidence == Confidence::Certain);

    const bool enabled = confidence != Confidence::None;
    drawButton(24, 270, 192, 42, "MOSTRAR RESPOSTA", UiAction::Reveal, false, enabled);
}

void CydDisplay::showAnswer(const CardDefinition& card,
                            uint8_t position,
                            uint8_t total) {
    clear();
    drawHeader("Resposta", String(position + 1) + "/" + String(total));

    drawWrappedText(card.answer, 12, 46, 216, 2, COLOR_TEXT, 21, 7);
    tft_.drawFastHLine(12, 190, 216, COLOR_BORDER);
    drawCentered("Como foi sua resposta?", 198, 2, COLOR_MUTED);

    drawButton(8, 224, 108, 40, "1  Errei", UiAction::RateAgain);
    drawButton(124, 224, 108, 40, "2  Dificil", UiAction::RateHard);
    drawButton(8, 272, 108, 40, "3  Acertei", UiAction::RateGood);
    drawButton(124, 272, 108, 40, "4  Facil", UiAction::RateEasy);
}

void CydDisplay::showSummary(const SessionStats& stats, uint16_t remainingDue) {
    clear();
    drawHeader("Sessao concluida");

    drawCentered(String(stats.reviewed) + " revisoes", 54, 4, COLOR_ACCENT);

    const uint32_t minutes = stats.durationSeconds() / 60U;
    const uint32_t seconds = stats.durationSeconds() % 60U;
    drawCentered("Tempo: " + String(minutes) + "m " + String(seconds) + "s", 102, 2, COLOR_MUTED);

    tft_.setTextFont(2);
    tft_.setTextColor(COLOR_TEXT, COLOR_BG);
    tft_.drawString("Errei", 24, 144);
    tft_.drawRightString(String(stats.ratingCounts[0]), 216, 144, 2);
    tft_.drawString("Dificil", 24, 168);
    tft_.drawRightString(String(stats.ratingCounts[1]), 216, 168, 2);
    tft_.drawString("Acertei", 24, 192);
    tft_.drawRightString(String(stats.ratingCounts[2]), 216, 192, 2);
    tft_.drawString("Facil", 24, 216);
    tft_.drawRightString(String(stats.ratingCounts[3]), 216, 216, 2);

    drawCentered(String(remainingDue) + " revisoes ainda pendentes", 246, 2, COLOR_MUTED);
    drawButton(24, 274, 192, 38, "VOLTAR AO INICIO", UiAction::Home);
}

int16_t CydDisplay::mapAxis(int32_t value, int32_t from0, int32_t from1, int16_t toMax) const {
    if (from0 == from1) return 0;
    const int64_t numerator = static_cast<int64_t>(value - from0) * toMax;
    const int64_t denominator = static_cast<int64_t>(from1 - from0);
    int32_t mapped = static_cast<int32_t>(numerator / denominator);
    mapped = std::max<int32_t>(0, std::min<int32_t>(toMax, mapped));
    return static_cast<int16_t>(mapped);
}

bool CydDisplay::readMappedTouch(TouchPoint& point) {
    const bool down = touch_.touched();
    if (!down) {
        touchWasDown_ = false;
        return false;
    }

    TS_Point raw = touch_.getPoint();
    if (raw.z < Config::TOUCH_PRESSURE_MIN) return false;

    if (touchWasDown_) return false;
    if (millis() - lastTouchMs_ < Config::TOUCH_DEBOUNCE_MS) return false;

    touchWasDown_ = true;
    lastTouchMs_ = millis();

    const int32_t rawX = calibration_.swapAxes ? raw.y : raw.x;
    const int32_t rawY = calibration_.swapAxes ? raw.x : raw.y;
    point.x = mapAxis(rawX, calibration_.x0, calibration_.x1, WIDTH - 1);
    point.y = mapAxis(rawY, calibration_.y0, calibration_.y1, HEIGHT - 1);

    Serial.printf("[touch] raw=(%d,%d,%d) mapped=(%d,%d)\n",
                  raw.x, raw.y, raw.z, point.x, point.y);
    return true;
}

UiAction CydDisplay::pollAction() {
    TouchPoint point;
    if (!readMappedTouch(point)) return UiAction::None;

    for (uint8_t i = 0; i < buttonCount_; ++i) {
        const Button& b = buttons_[i];
        if (point.x >= b.x && point.x < b.x + b.w &&
            point.y >= b.y && point.y < b.y + b.h) {
            return b.action;
        }
    }
    return UiAction::None;
}

TS_Point CydDisplay::collectCalibrationPoint(int16_t x, int16_t y, const char* label) {
    tft_.fillScreen(COLOR_BG);
    tft_.setTextFont(2);
    tft_.setTextColor(COLOR_TEXT, COLOR_BG);
    tft_.drawCentreString(label, WIDTH / 2, HEIGHT / 2 - 20, 2);
    tft_.drawCircle(x, y, 10, COLOR_ACCENT);
    tft_.drawFastHLine(x - 14, y, 29, COLOR_ACCENT);
    tft_.drawFastVLine(x, y - 14, 29, COLOR_ACCENT);

    while (touch_.touched()) delay(10);
    while (!touch_.touched()) delay(10);

    int64_t sx = 0;
    int64_t sy = 0;
    int64_t sz = 0;
    int samples = 0;
    const uint32_t started = millis();
    while (millis() - started < 700U && samples < 20) {
        if (touch_.touched()) {
            TS_Point p = touch_.getPoint();
            if (p.z >= Config::TOUCH_PRESSURE_MIN) {
                sx += p.x;
                sy += p.y;
                sz += p.z;
                ++samples;
            }
        }
        delay(15);
    }
    while (touch_.touched()) delay(10);

    if (samples == 0) return TS_Point(0, 0, 0);
    return TS_Point(static_cast<int16_t>(sx / samples),
                    static_cast<int16_t>(sy / samples),
                    static_cast<int16_t>(sz / samples));
}

void CydDisplay::calibrateTouch() {
    const int16_t margin = 22;
    TS_Point raw[4];
    raw[0] = collectCalibrationPoint(margin, margin, "Toque no alvo superior esquerdo");
    raw[1] = collectCalibrationPoint(WIDTH - margin, margin, "Toque no alvo superior direito");
    raw[2] = collectCalibrationPoint(WIDTH - margin, HEIGHT - margin, "Toque no alvo inferior direito");
    raw[3] = collectCalibrationPoint(margin, HEIGHT - margin, "Toque no alvo inferior esquerdo");

    const int32_t horizontalX = std::abs(((raw[1].x + raw[2].x) / 2) - ((raw[0].x + raw[3].x) / 2));
    const int32_t horizontalY = std::abs(((raw[1].y + raw[2].y) / 2) - ((raw[0].y + raw[3].y) / 2));
    calibration_.swapAxes = horizontalY > horizontalX;

    auto sourceX = [&](const TS_Point& p) { return calibration_.swapAxes ? p.y : p.x; };
    auto sourceY = [&](const TS_Point& p) { return calibration_.swapAxes ? p.x : p.y; };

    calibration_.x0 = (sourceX(raw[0]) + sourceX(raw[3])) / 2;
    calibration_.x1 = (sourceX(raw[1]) + sourceX(raw[2])) / 2;
    calibration_.y0 = (sourceY(raw[0]) + sourceY(raw[1])) / 2;
    calibration_.y1 = (sourceY(raw[2]) + sourceY(raw[3])) / 2;
    calibration_.valid = true;

    preferences_.putBool("valid", true);
    preferences_.putInt("x0", calibration_.x0);
    preferences_.putInt("x1", calibration_.x1);
    preferences_.putInt("y0", calibration_.y0);
    preferences_.putInt("y1", calibration_.y1);
    preferences_.putBool("swap", calibration_.swapAxes);

    Serial.printf("[touch] calibrado x=(%ld,%ld) y=(%ld,%ld) swap=%d\n",
                  static_cast<long>(calibration_.x0), static_cast<long>(calibration_.x1),
                  static_cast<long>(calibration_.y0), static_cast<long>(calibration_.y1),
                  calibration_.swapAxes);

    tft_.fillScreen(COLOR_BG);
    drawCentered("Calibracao concluida", 140, 2, COLOR_ACCENT);
    delay(800);
    touchWasDown_ = false;
}
