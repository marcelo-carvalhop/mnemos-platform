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

constexpr uint16_t COLOR_BG = 0xF79D;       // Marfim Calmo
constexpr uint16_t COLOR_TEXT = 0x18E3;     // Grafite Profundo
constexpr uint16_t COLOR_MUTED = 0x7C4E;    // Salvia Analogica
constexpr uint16_t COLOR_ACCENT = 0x32AC;   // Azul Petroleo
constexpr uint16_t COLOR_BORDER = 0xDEB9;   // Cinza Nevoa
constexpr uint16_t COLOR_SELECTED = 0xBD0F; // Latao Fosco
constexpr uint16_t COLOR_DISABLED = 0xDEB9;
constexpr uint16_t COLOR_DANGER = 0xB36A;   // Terracota Contida
}

CydDisplay::CydDisplay() : touch_(TOUCH_CS, TOUCH_IRQ) {}

void CydDisplay::begin() {
    pinMode(BOOT_BUTTON, INPUT_PULLUP);
    pinMode(TFT_BL, OUTPUT);
    digitalWrite(TFT_BL, HIGH);

    tft_.init();
    tft_.setRotation(0);
    tft_.setTextWrap(false);

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

void CydDisplay::clearButtons() { buttonCount_ = 0; }

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

void CydDisplay::showHome(uint16_t due, uint16_t newCards, size_t total, bool trustedClock, bool canResume,
                          const String& nextReview) {
    clear();
    drawHeader("MNEMOS");
    const String headline = canResume ? "Sessao interrompida" :
                            (due > 0 ? String(due) + " revisoes" :
                             (newCards > 0 ? String(newCards) + " novos" : "Nada pendente"));
    drawCentered(headline, 68, 3, (due > 0 || newCards > 0 || canResume) ? COLOR_ACCENT : COLOR_MUTED);
    drawCentered(String(total) + " cards", 108, 2, COLOR_MUTED);

    if (!canResume && due == 0 && nextReview.length() > 0) {
        drawCentered("Proxima revisao", 136, 2, COLOR_MUTED);
        drawCentered(nextReview, 158, 2, COLOR_TEXT);
    } else if (!trustedClock) {
        drawCentered("Relogio aproximado", 148, 2, COLOR_MUTED);
    }

    const String primary = canResume ? "CONTINUAR" : ((due > 0 || newCards > 0) ? "ESTUDAR" : "PRATICAR");
    drawButton(24, 190, 192, 44, primary, UiAction::PrimaryStudy, false, total > 0 || canResume);
    drawButton(24, 248, 192, 44, "MENU", UiAction::OpenMenu);
}

void CydDisplay::showMainMenu() {
    clear();
    drawHeader("Menu");
    drawButton(24, 70, 192, 44, "SINCRONIZAR", UiAction::OpenSync);
    drawButton(24, 126, 192, 44, "AGENDA", UiAction::OpenAgenda);
    drawButton(24, 182, 192, 44, "CONEXAO", UiAction::OpenConnection);
    drawButton(40, 266, 160, 34, "VOLTAR", UiAction::Back);
}

void CydDisplay::showAgenda(uint16_t dueNow, uint16_t laterToday, uint16_t tomorrow,
                            uint16_t next7Days, const String& nextReview) {
    clear();
    drawHeader("Agenda");

    tft_.setTextFont(2);
    tft_.setTextColor(COLOR_TEXT, COLOR_BG);
    tft_.drawString("Agora", 18, 58);
    tft_.setTextDatum(TR_DATUM);
    tft_.drawString(String(dueNow), WIDTH - 18, 58);
    tft_.setTextDatum(TL_DATUM);

    tft_.drawString("Ainda hoje", 18, 90);
    tft_.setTextDatum(TR_DATUM);
    tft_.drawString(String(laterToday), WIDTH - 18, 90);
    tft_.setTextDatum(TL_DATUM);

    tft_.drawString("Amanha", 18, 122);
    tft_.setTextDatum(TR_DATUM);
    tft_.drawString(String(tomorrow), WIDTH - 18, 122);
    tft_.setTextDatum(TL_DATUM);

    tft_.drawString("Proximos 7 dias", 18, 154);
    tft_.setTextDatum(TR_DATUM);
    tft_.drawString(String(next7Days), WIDTH - 18, 154);
    tft_.setTextDatum(TL_DATUM);

    tft_.drawFastHLine(18, 190, WIDTH - 36, COLOR_BORDER);
    drawCentered("Proxima revisao", 208, 2, COLOR_MUTED);
    drawCentered(nextReview.length() > 0 ? nextReview : "Sem revisao agendada", 232, 2, COLOR_ACCENT);
    drawButton(40, 272, 160, 34, "VOLTAR", UiAction::Back);
}

void CydDisplay::showSyncMenu(size_t total, uint16_t pendingReviews, bool wifiConnected) {
    clear();
    drawHeader("Sincronizar", wifiConnected ? "Wi-Fi" : "Offline");
    drawCentered(String(total) + " cards no Mnemos", 66, 2, COLOR_TEXT);
    drawCentered(String(pendingReviews) + " revisoes aguardando", 94, 2,
                 pendingReviews > 0 ? COLOR_ACCENT : COLOR_MUTED);

    drawButton(24, 142, 192, 42, "PELA REDE", UiAction::SyncBackend, false, wifiConnected);
    drawButton(24, 198, 192, 42, "COM O CELULAR", UiAction::SyncPhone);
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
    drawCentered(String(knownNetworks) + " redes conhecidas", 116, 2, COLOR_MUTED);

    drawButton(24, 160, 192, 42, "CONFIGURAR REDE", UiAction::ConfigureNetwork);
    drawButton(24, 214, 192, 42,
               wifiEnabled ? "DESLIGAR WI-FI" : "LIGAR WI-FI", UiAction::ToggleWifi);
    drawButton(40, 270, 160, 34, "VOLTAR", UiAction::Back);
}

void CydDisplay::showLocalLink(const String& qrPayload,
                               const String& ssid,
                               const String& password,
                               bool provisioning) {
    clear();
    drawHeader(provisioning ? "Configurar rede" : "Sincronizar celular", "5 min");

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

    drawCentered(provisioning ? "Escaneie no app" : "Conecte o app ao Mnemos", 202, 2, COLOR_TEXT);
    drawCentered(ssid, 224, 2, COLOR_ACCENT);
    drawCentered("Senha: " + password, 244, 2, COLOR_MUTED);
    drawButton(40, 278, 160, 34, "CANCELAR", UiAction::CancelLocalLink);
}

void CydDisplay::showQuestion(const CardDefinition& card, uint8_t position, uint8_t total) {
    clear();
    drawHeader(card.deck, String(position + 1) + "/" + String(total));
    const int16_t bottom = drawWrappedText(card.question, 12, 48, 216, 2, COLOR_TEXT, 22, 7);

    if (card.isObjective()) {
        const uint8_t count = std::min<uint8_t>(card.optionCount, 4);
        int16_t y = std::max<int16_t>(150, bottom + 12);
        const int16_t h = count <= 2 ? 52 : 36;
        const int16_t gap = count <= 2 ? 12 : 6;
        const UiAction actions[4] = {UiAction::Choice0, UiAction::Choice1, UiAction::Choice2, UiAction::Choice3};
        for (uint8_t i = 0; i < count; ++i) {
            String label = String(static_cast<char>('A' + i)) + "  " + card.options[i];
            if (label.length() > 28) label = label.substring(0, 27) + "...";
            drawButton(12, y, 216, h, label, actions[i]);
            y += h + gap;
        }
    } else {
        drawWrappedText("Formule a resposta antes de continuar.", 18, 204, 204, 2, COLOR_MUTED, 20, 3);
        drawButton(24, 258, 192, 44, "RESPONDI", UiAction::AnswerReady);
    }
}

void CydDisplay::showConfidence(const CardDefinition& card, uint8_t position, uint8_t total) {
    clear();
    drawHeader("Confianca", String(position + 1) + "/" + String(total));
    drawWrappedText(card.question, 14, 50, 212, 2, COLOR_TEXT, 21, 4);
    drawCentered("Antes do feedback:", 154, 2, COLOR_MUTED);
    drawCentered("quanto voce acredita na resposta?", 178, 2, COLOR_MUTED);
    drawButton(12, 218, 66, 42, "BAIXA", UiAction::ConfidenceLow);
    drawButton(87, 218, 66, 42, "MEDIA", UiAction::ConfidenceMedium);
    drawButton(162, 218, 66, 42, "ALTA", UiAction::ConfidenceHigh);
}

void CydDisplay::showSelfAssessment(const CardDefinition& card, uint8_t position, uint8_t total) {
    clear();
    drawHeader("Resposta", String(position + 1) + "/" + String(total));
    drawWrappedText(card.answer, 12, 48, 216, 2, COLOR_TEXT, 21, 7);
    tft_.drawFastHLine(12, 212, 216, COLOR_BORDER);
    drawCentered("Sua resposta estava correta?", 224, 2, COLOR_MUTED);
    drawButton(12, 258, 102, 44, "ERREI", UiAction::SelfIncorrect);
    drawButton(126, 258, 102, 44, "ACERTEI", UiAction::SelfCorrect);
}

void CydDisplay::showObjectiveFeedback(const CardDefinition& card,
                                       uint8_t position,
                                       uint8_t total,
                                       int8_t selectedOptionIndex,
                                       Outcome outcome) {
    clear();
    drawHeader("Resultado", String(position + 1) + "/" + String(total));
    drawCentered(outcome == Outcome::Correct ? "CORRETO" : "INCORRETO", 58, 4,
                 outcome == Outcome::Correct ? COLOR_ACCENT : COLOR_DANGER);

    if (selectedOptionIndex >= 0 && selectedOptionIndex < card.optionCount) {
        drawWrappedText("Voce marcou: " + card.options[selectedOptionIndex], 14, 112, 212, 2, COLOR_TEXT, 21, 3);
    }
    if (card.correctOptionIndex >= 0 && card.correctOptionIndex < card.optionCount) {
        drawWrappedText("Resposta: " + card.options[card.correctOptionIndex], 14, 178, 212, 2,
                        outcome == Outcome::Correct ? COLOR_MUTED : COLOR_ACCENT, 21, 3);
    }
    drawButton(40, 268, 160, 38, "CONTINUAR", UiAction::Continue);
}

void CydDisplay::showEffort(uint8_t position, uint8_t total) {
    clear();
    drawHeader("Esforco", String(position + 1) + "/" + String(total));
    drawCentered("Como foi lembrar?", 90, 3, COLOR_TEXT);
    drawCentered("Avalie o esforco de recuperacao.", 142, 2, COLOR_MUTED);
    drawButton(12, 220, 66, 42, "DIFICIL", UiAction::EffortDifficult);
    drawButton(87, 220, 66, 42, "NORMAL", UiAction::EffortNormal);
    drawButton(162, 220, 66, 42, "FACIL", UiAction::EffortEasy);
}

void CydDisplay::showSummary(const SessionStats& stats, uint16_t remainingDue, uint16_t remainingNew, const String& nextReview) {
    clear();
    drawHeader(stats.mode == SessionMode::Practice ? "Pratica concluida" : "Sessao concluida");
    drawCentered(String(stats.reviewed) + " cards", 54, 4, COLOR_ACCENT);
    drawCentered(String(stats.correct) + " corretos  |  " + String(stats.incorrect) + " erros", 100, 2, COLOR_TEXT);
    const uint32_t minutes = stats.durationSeconds() / 60U;
    const uint32_t seconds = stats.durationSeconds() % 60U;
    drawCentered("Tempo: " + String(minutes) + "m " + String(seconds) + "s", 130, 2, COLOR_MUTED);
    if (remainingDue > 0) {
        drawCentered(String(remainingDue) + " revisoes ainda pendentes", 166, 2, COLOR_MUTED);
    } else if (remainingNew > 0) {
        drawCentered(String(remainingNew) + " cards novos disponiveis", 166, 2, COLOR_MUTED);
        if (nextReview.length() > 0 && nextReview != "Sem revisao agendada") {
            drawCentered("Proxima revisao: " + nextReview, 190, 2, COLOR_MUTED);
        }
    } else {
        drawCentered("Proxima revisao", 158, 2, COLOR_MUTED);
        drawCentered(nextReview.length() > 0 ? nextReview : "Sem revisao agendada", 182, 2, COLOR_TEXT);
    }

    const String nextAction = remainingDue > 0 ? "CONTINUAR REVISOES" :
                              (remainingNew > 0 ? "ESTUDAR NOVOS" : "PRATICAR NOVAMENTE");
    drawButton(24, 220, 192, 42, nextAction, UiAction::StudyAgain);
    drawButton(40, 274, 160, 34, "CONCLUIR", UiAction::Home);
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
            point.y >= b.y && point.y < b.y + b.h) return b.action;
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

    int64_t sx = 0, sy = 0, sz = 0;
    int samples = 0;
    const uint32_t started = millis();
    while (millis() - started < 700U && samples < 20) {
        if (touch_.touched()) {
            TS_Point p = touch_.getPoint();
            if (p.z >= Config::TOUCH_PRESSURE_MIN) {
                sx += p.x; sy += p.y; sz += p.z; ++samples;
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
