#include "t5_display.h"

#include <algorithm>
#include <cstring>
#include <memory>

#include "config.h"
#include "epd_driver.h"
#include "roboto12.h"
#include <qrcode.h>

namespace {
constexpr uint8_t BLACK = 0x00;
constexpr uint8_t DARK_GRAY = 0x55;
constexpr uint8_t MID_GRAY = 0x99;
constexpr uint8_t LIGHT_GRAY = 0xDD;
constexpr uint8_t WHITE = 0xFF;

GFXfont* const BODY_FONT = const_cast<GFXfont*>(&Roboto12);

int32_t textWidthPx(const String& value) {
    if (value.length() == 0) return 0;
    int32_t x = 0;
    int32_t y = BODY_FONT->ascender;
    int32_t x1 = 0;
    int32_t y1 = 0;
    int32_t w = 0;
    int32_t h = 0;
    get_text_bounds(BODY_FONT, value.c_str(), &x, &y, &x1, &y1, &w, &h, nullptr);
    return w;
}

constexpr int32_t MARGIN_X = 42;
constexpr int32_t HEADER_Y = 42;
constexpr int32_t CONTENT_Y = 92;
constexpr int32_t FOOTER_Y = 510;


String truncateText(const String& value, size_t maxChars) {
    if (value.length() <= maxChars) return value;
    return value.substring(0, maxChars - 3) + "...";
}
}

bool T5Display::begin() {
    framebuffer_ = static_cast<uint8_t*>(ps_calloc(sizeof(uint8_t), EPD_WIDTH * EPD_HEIGHT / 2));
    if (!framebuffer_) {
        Serial.println("[display] falha ao alocar framebuffer na PSRAM");
        return false;
    }

    std::memset(framebuffer_, WHITE, EPD_WIDTH * EPD_HEIGHT / 2);
    epd_init();
    ensurePower();
    epd_clear();
    Serial.printf("[display] T5 EPD pronto %dx%d\n", EPD_WIDTH, EPD_HEIGHT);
    return true;
}

void T5Display::setBatteryStatus(bool available, uint8_t percent) {
    batteryAvailable_ = available;
    batteryPercent_ = std::min<uint8_t>(100, percent);
}

void T5Display::ensurePower() {
    if (powerOn_) return;
    epd_poweron();
    powerOn_ = true;
}

void T5Display::clearBuffer() {
    if (!framebuffer_) return;
    std::memset(framebuffer_, WHITE, EPD_WIDTH * EPD_HEIGHT / 2);
}

void T5Display::refreshFull() {
    if (!framebuffer_) return;
    ensurePower();
    // Full-screen EPD redraw: clear the physical panel first.
    // The grayscale draw routine does not erase the previous image.
    epd_clear();
    epd_draw_grayscale_image(epd_full_screen(), framebuffer_);
    if (!Config::KEEP_EPD_AUX_POWER_WHILE_AWAKE) {
        epd_poweroff();
        powerOn_ = false;
    }
}

void T5Display::drawText(const String& text, int32_t x, int32_t y, uint8_t* target) {
    int32_t cx = x;
    int32_t cy = y;
    writeln(BODY_FONT, text.c_str(), &cx, &cy,
            target == nullptr ? framebuffer_ : target);
}

int32_t T5Display::drawWrapped(const String& text,
                               int32_t x,
                               int32_t y,
                               uint16_t maxWidthPx,
                               uint16_t lineHeight,
                               uint8_t maxLines,
                               uint8_t* target) {
    String line;
    String word;
    uint8_t lines = 0;
    uint8_t* dst = target == nullptr ? framebuffer_ : target;

    auto flushLine = [&]() {
        if (line.length() == 0 || lines >= maxLines) return;
        drawText(line, x, y + lines * lineHeight, dst);
        line = "";
        ++lines;
    };

    for (size_t i = 0; i <= text.length(); ++i) {
        const char c = i < text.length() ? text[i] : ' ';
        if (c != ' ' && c != '\n') {
            word += c;
            continue;
        }

        if (word.length() > 0) {
            const String candidate = line.length() > 0 ? line + " " + word : word;
            if (line.length() > 0 && textWidthPx(candidate) > maxWidthPx) {
                flushLine();
            }
            if (lines >= maxLines) break;
            if (line.length() > 0) line += ' ';
            line += word;
            word = "";
        }

        if (c == '\n') flushLine();
        if (lines >= maxLines) break;
    }

    if (line.length() > 0 && lines < maxLines) flushLine();
    return y + static_cast<int32_t>(lines) * lineHeight;
}

void T5Display::drawHeader(const String& title, const String& rightText) {
    drawText(title, MARGIN_X, HEADER_Y);

    int32_t statusRight = EPD_WIDTH - MARGIN_X;

    if (batteryAvailable_) {
        const String batteryText = String(batteryPercent_) + "%";
        const int32_t batteryWidth = textWidthPx(batteryText);
        const int32_t batteryX = statusRight - batteryWidth;
        drawText(batteryText, batteryX, HEADER_Y);
        statusRight = batteryX - 24;
    }

    if (rightText.length() > 0) {
        const int32_t rightWidth = textWidthPx(rightText);
        const int32_t rightX = std::max<int32_t>(MARGIN_X + 300, statusRight - rightWidth);
        drawText(rightText, rightX, HEADER_Y);
    }

    epd_draw_line(36, 70, EPD_WIDTH - 36, 70, DARK_GRAY, framebuffer_);
}

void T5Display::drawFooter(const String& hint) {
    epd_draw_line(36, 476, EPD_WIDTH - 36, 476, LIGHT_GRAY, framebuffer_);
    drawText(hint, MARGIN_X, FOOTER_Y);
}

void T5Display::drawChoice(uint8_t number, const String& label, int32_t y) {
    epd_draw_rect(48, y - 27, 840, 48, MID_GRAY, framebuffer_);
    drawText(String(number) + "  " + truncateText(label, 76), 68, y + 3);
}

void T5Display::drawQr(const String& payload, int32_t originX, int32_t originY, int scale) {
    constexpr uint8_t QR_VERSION = 8;
    const uint16_t qrBufferSize = qrcode_getBufferSize(QR_VERSION);
    std::unique_ptr<uint8_t[]> qrcodeData(new uint8_t[qrBufferSize]);
    QRCode qrcode;
    if (qrcode_initText(&qrcode, qrcodeData.get(), QR_VERSION, ECC_LOW, payload.c_str()) != 0) {
        drawText("Falha ao gerar QR", originX, originY + 40);
        return;
    }

    const int quiet = 2;
    const int qrPixels = (qrcode.size + quiet * 2) * scale;
    epd_fill_rect(originX, originY, qrPixels, qrPixels, WHITE, framebuffer_);
    epd_draw_rect(originX, originY, qrPixels, qrPixels, MID_GRAY, framebuffer_);
    for (uint8_t y = 0; y < qrcode.size; ++y) {
        for (uint8_t x = 0; x < qrcode.size; ++x) {
            if (qrcode_getModule(&qrcode, x, y)) {
                epd_fill_rect(originX + (x + quiet) * scale,
                              originY + (y + quiet) * scale,
                              scale, scale, BLACK, framebuffer_);
            }
        }
    }
}

void T5Display::showBoot(const String& message) {
    clearBuffer();
    drawText("MNEMOS", 350, 180);
    drawText("Terminal dedicado de estudo", 310, 230);
    drawText(message, 330, 310);
    drawText(String("v") + Config::APP_VERSION, 390, 390);
    refreshFull();
}

void T5Display::showKeyboardMissing() {
    clearBuffer();
    drawHeader("MNEMOS");
    drawText("CardKB nao encontrado", MARGIN_X, 190);
    drawWrapped("Conecte o Unit CardKB v1.1 ao barramento I2C: SDA GPIO16, SCL GPIO15. O terminal tentara novamente automaticamente.",
                MARGIN_X, 250, EPD_WIDTH - 2 * MARGIN_X, 34, 5);
    drawFooter("Aguardando teclado...");
    refreshFull();
}

void T5Display::showHome(uint16_t due, uint16_t newCards, size_t total, bool trustedClock,
                         bool canResume, const String& nextReview) {
    clearBuffer();
    drawHeader("MNEMOS", trustedClock ? "" : "relogio aprox.");

    const String headline = canResume ? "Sessao interrompida" :
                            (due > 0 ? String(due) + " revisoes" :
                             (newCards > 0 ? String(newCards) + " novos" : "Nada pendente"));
    drawText(headline, MARGIN_X, 170);
    drawText(String(total) + " cards no terminal", MARGIN_X, 220);

    if (!canResume && due == 0 && nextReview.length() > 0) {
        drawText("Proxima revisao", MARGIN_X, 300);
        drawText(nextReview, MARGIN_X, 345);
    }

    const String primary = canResume ? "ENTER continuar" :
                           ((due > 0 || newCards > 0) ? "ENTER estudar" : "ENTER praticar");
    drawFooter(primary + "     M menu");
    refreshFull();
}

void T5Display::showMainMenu() {
    clearBuffer();
    drawHeader("MENU");
    drawChoice(1, "Sincronizar", 150);
    drawChoice(2, "Agenda", 225);
    drawChoice(3, "Conexao", 300);
    drawFooter("1-3 selecionar     BACKSPACE voltar");
    refreshFull();
}

void T5Display::showAgenda(uint16_t dueNow, uint16_t laterToday, uint16_t tomorrow,
                           uint16_t next7Days, const String& nextReview) {
    clearBuffer();
    drawHeader("AGENDA");
    drawText("Agora", 90, 145);       drawText(String(dueNow), 700, 145);
    drawText("Ainda hoje", 90, 200);  drawText(String(laterToday), 700, 200);
    drawText("Amanha", 90, 255);      drawText(String(tomorrow), 700, 255);
    drawText("Proximos 7 dias", 90, 310); drawText(String(next7Days), 700, 310);
    drawText("Proxima revisao", 90, 390);
    drawText(nextReview.length() ? nextReview : "Sem revisao agendada", 360, 390);
    drawFooter("BACKSPACE voltar");
    refreshFull();
}

void T5Display::showSyncMenu(size_t total, uint16_t pendingReviews, bool wifiConnected) {
    clearBuffer();
    drawHeader("SINCRONIZAR", wifiConnected ? "Wi-Fi" : "offline");
    drawText(String(total) + " cards no Mnemos", 90, 140);
    drawText(String(pendingReviews) + " revisoes aguardando envio", 90, 195);
    drawChoice(1, wifiConnected ? "Sincronizar pela rede" : "Pela rede (indisponivel)", 285);
    drawChoice(2, "Sincronizar diretamente com o celular", 360);
    drawFooter("1 rede     2 celular     BACKSPACE voltar");
    refreshFull();
}

void T5Display::showConnectionMenu(bool wifiEnabled, bool wifiConnected,
                                   const String& ssid, size_t knownNetworks) {
    clearBuffer();
    drawHeader("CONEXAO");
    const String state = !wifiEnabled ? "Wi-Fi desligado" :
                         (wifiConnected ? "Conectado" : "Sem conexao");
    drawText(state, 90, 135);
    if (wifiConnected && ssid.length()) drawText(ssid, 90, 185);
    drawText(String(knownNetworks) + " redes conhecidas", 90, 235);
    drawChoice(1, "Configurar rede", 325);
    drawChoice(2, wifiEnabled ? "Desligar Wi-Fi" : "Ligar Wi-Fi", 400);
    drawFooter("1 configurar     2 Wi-Fi     BACKSPACE voltar");
    refreshFull();
}

void T5Display::showLocalLink(const String& qrPayload,
                              const String& ssid,
                              const String& password,
                              bool provisioning) {
    clearBuffer();
    drawHeader(provisioning ? "CONFIGURAR REDE" : "SINCRONIZAR CELULAR", "5 min");
    drawQr(qrPayload, 70, 105, 5);
    drawText(provisioning ? "Escaneie no app" : "Conecte o app ao Mnemos", 450, 155);
    drawText("Rede", 450, 235);
    drawText(ssid, 450, 270);
    drawText("Senha", 450, 330);
    drawText(password, 450, 365);
    drawFooter("BACKSPACE cancelar");
    refreshFull();
}

void T5Display::showQuestion(const CardDefinition& card,
                             uint8_t position,
                             uint8_t total) {
    clearBuffer();
    drawHeader(card.deck, String(position + 1) + "/" + String(total));
    drawWrapped(card.question, 52, 115, EPD_WIDTH - 104, 32, 5);

    if (card.isObjective()) {
        const uint8_t count = std::min<uint8_t>(card.optionCount, 4);
        int32_t y = 285;
        for (uint8_t i = 0; i < count; ++i) {
            drawChoice(i + 1, card.options[i], y);
            y += 58;
        }
        drawFooter("1-4 selecionar alternativa");
    } else {
        epd_draw_rect(120, 315, EPD_WIDTH - 240, 82, MID_GRAY, framebuffer_);
        drawText("REVELAR RESPOSTA", 330, 365);
        drawFooter("ENTER revelar resposta");
    }
    refreshFull();
}

void T5Display::showSelfAssessment(const CardDefinition& card,
                                   uint8_t position,
                                   uint8_t total) {
    clearBuffer();
    drawHeader("RESPOSTA", String(position + 1) + "/" + String(total));

    drawText("Pergunta", 52, 112);
    drawWrapped(card.question, 52, 148, EPD_WIDTH - 104, 30, 4);

    drawText("Resposta de referencia", 52, 300);
    drawWrapped(card.answer, 52, 338, EPD_WIDTH - 104, 30, 4);

    drawFooter("1 errei     2 acertei");
    refreshFull();
}
void T5Display::showObjectiveFeedback(const CardDefinition& card,
                                      uint8_t position,
                                      uint8_t total,
                                      int8_t selectedOptionIndex,
                                      Outcome outcome) {
    clearBuffer();
    drawHeader("RESULTADO", String(position + 1) + "/" + String(total));
    drawText(outcome == Outcome::Correct ? "CORRETO" : "INCORRETO", 390, 135);
    if (selectedOptionIndex >= 0 && selectedOptionIndex < card.optionCount) {
        drawText("Voce marcou", 70, 235);
        drawWrapped(card.options[selectedOptionIndex], 70, 275, 400, 32, 3);
    }
    if (card.correctOptionIndex >= 0 && card.correctOptionIndex < card.optionCount) {
        drawText("Resposta", 520, 235);
        drawWrapped(card.options[card.correctOptionIndex], 520, 275, 370, 32, 3);
    }
    drawFooter("ENTER continuar");
    refreshFull();
}

void T5Display::showEffort(uint8_t position, uint8_t total) {
    clearBuffer();
    drawHeader("ESFORCO", String(position + 1) + "/" + String(total));
    drawText("Como foi lembrar?", 330, 180);
    drawText("Avalie apenas o esforco de recuperacao.", 250, 230);
    drawChoice(1, "Dificil", 330);
    drawChoice(2, "Normal", 390);
    drawChoice(3, "Facil", 450);
    drawFooter("1 dificil     2 normal     3 facil");
    refreshFull();
}

void T5Display::showSummary(const SessionStats& stats,
                            uint16_t remainingDue,
                            uint16_t remainingNew,
                            const String& nextReview) {
    clearBuffer();
    drawHeader(stats.mode == SessionMode::Practice ? "PRATICA CONCLUIDA" : "SESSAO CONCLUIDA");
    drawText(String(stats.reviewed) + " cards", 390, 145);
    drawText(String(stats.correct) + " corretos     " + String(stats.incorrect) + " erros", 300, 200);
    const uint32_t minutes = stats.durationSeconds() / 60U;
    const uint32_t seconds = stats.durationSeconds() % 60U;
    drawText("Tempo: " + String(minutes) + "m " + String(seconds) + "s", 360, 250);

    if (remainingDue > 0) {
        drawText(String(remainingDue) + " revisoes ainda pendentes", 300, 325);
    } else if (remainingNew > 0) {
        drawText(String(remainingNew) + " cards novos disponiveis", 300, 325);
        if (nextReview.length()) drawText("Proxima revisao: " + nextReview, 270, 375);
    } else {
        drawText("Proxima revisao", 360, 325);
        drawText(nextReview.length() ? nextReview : "Sem revisao agendada", 330, 375);
    }

    drawFooter("1 estudar novamente     ENTER concluir");
    refreshFull();
}
