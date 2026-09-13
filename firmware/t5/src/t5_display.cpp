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

constexpr int32_t MARGIN_X = 48;
constexpr int32_t HEADER_Y = 30;
constexpr int32_t CONTENT_Y = 104;
constexpr int32_t FOOTER_Y = 512;


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

void T5Display::drawHeader(
    const String& title,
    const String& rightText) {

    // Assinatura permanente do produto.
    drawText(
        "MNEMOS",
        MARGIN_X,
        HEADER_Y);

    // Bateria permanece discreta no primeiro nivel.
    int32_t statusRight =
        EPD_WIDTH - MARGIN_X;

    if (batteryAvailable_) {
        const String batteryText =
            String(batteryPercent_) + "%";

        const int32_t batteryWidth =
            textWidthPx(batteryText);

        const int32_t batteryX =
            statusRight - batteryWidth;

        drawText(
            batteryText,
            batteryX,
            HEADER_Y);

        statusRight =
            batteryX - 28;
    }

    // Contexto da tela em segundo nivel.
    drawText(
        title,
        MARGIN_X,
        62);

    // rightText e reservado a contexto util ou anomalia.
    // Estado normal do relogio permanece silencioso.
    if (rightText.length() > 0) {
        const int32_t rightWidth =
            textWidthPx(rightText);

        const int32_t rightX =
            std::max<int32_t>(
                MARGIN_X + 320,
                EPD_WIDTH -
                    MARGIN_X -
                    rightWidth);

        drawText(
            rightText,
            rightX,
            62);
    }

    epd_draw_line(
        MARGIN_X,
        82,
        EPD_WIDTH - MARGIN_X,
        82,
        DARK_GRAY,
        framebuffer_);
}

void T5Display::drawFooter(
    const String& hint) {

    epd_draw_line(
        MARGIN_X,
        474,
        EPD_WIDTH - MARGIN_X,
        474,
        LIGHT_GRAY,
        framebuffer_);

    drawText(
        hint,
        MARGIN_X,
        FOOTER_Y);
}

void T5Display::drawChoice(
    uint8_t number,
    const String& label,
    int32_t y) {

    // Bloco pequeno para a tecla; o restante permanece aberto.
    epd_fill_rect(
        56,
        y - 25,
        42,
        42,
        LIGHT_GRAY,
        framebuffer_);

    epd_draw_rect(
        56,
        y - 25,
        42,
        42,
        MID_GRAY,
        framebuffer_);

    drawText(
        String(number),
        71,
        y + 3);

    drawText(
        truncateText(label, 72),
        122,
        y + 3);

    epd_draw_line(
        122,
        y + 22,
        EPD_WIDTH - 60,
        y + 22,
        LIGHT_GRAY,
        framebuffer_);
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

void T5Display::showBoot(
    const String& message) {

    clearBuffer();

    epd_draw_line(
        250,
        178,
        EPD_WIDTH - 250,
        178,
        DARK_GRAY,
        framebuffer_);

    drawText(
        "MNEMOS",
        398,
        230);

    drawText(
        "estudo sem distracoes",
        344,
        278);

    drawText(
        message,
        350,
        350);

    drawText(
        String("v") +
            Config::APP_VERSION,
        412,
        414);

    refreshFull();
}

void T5Display::showKeyboardMissing() {

    clearBuffer();

    drawHeader(
        "TECLADO",
        "entrada indisponivel");

    drawText(
        "CardKB nao encontrado",
        MARGIN_X,
        158);

    drawWrapped(
        "Conecte o Unit CardKB v1.1. "
        "O terminal continuara procurando o teclado "
        "automaticamente.",
        MARGIN_X,
        218,
        EPD_WIDTH - 2 * MARGIN_X,
        34,
        5);

    drawText(
        "SDA GPIO16   SCL GPIO15",
        MARGIN_X,
        390);

    drawFooter(
        "Aguardando teclado");

    refreshFull();
}

void T5Display::showHome(
    uint16_t due,
    uint16_t newCards,
    size_t total,
    bool trustedClock,
    bool canResume,
    const String& nextReview) {

    clearBuffer();

    drawHeader(
        "ESTUDO",
        trustedClock
            ? ""
            : "hora nao confiavel");

    drawText(
        "HOJE",
        MARGIN_X,
        126);

    String headline;

    if (canResume) {
        headline =
            "Sessao pausada";
    } else if (due > 0) {
        headline =
            String(due) +
            (due == 1
                ? " revisao pendente"
                : " revisoes pendentes");
    } else if (newCards > 0) {
        headline =
            String(newCards) +
            (newCards == 1
                ? " cartao novo"
                : " cartoes novos");
    } else {
        headline =
            "Tudo em dia";
    }

    drawText(
        headline,
        MARGIN_X,
        174);

    epd_draw_line(
        MARGIN_X,
        204,
        EPD_WIDTH - MARGIN_X,
        204,
        LIGHT_GRAY,
        framebuffer_);

    drawText(
        "Revisoes",
        MARGIN_X,
        255);

    drawText(
        String(due),
        MARGIN_X,
        294);

    drawText(
        "Novos",
        310,
        255);

    drawText(
        String(newCards),
        310,
        294);

    drawText(
        "Biblioteca",
        540,
        255);

    drawText(
        String(total),
        540,
        294);

    if (
        !canResume &&
        due == 0 &&
        nextReview.length() > 0
    ) {
        drawText(
            "Proxima revisao",
            MARGIN_X,
            370);

        drawText(
            nextReview,
            MARGIN_X,
            410);
    } else if (canResume) {
        drawText(
            "Seu ponto de estudo foi preservado.",
            MARGIN_X,
            382);
    }

    String primary;

    if (canResume) {
        primary =
            "ENTER continuar";
    } else if (
        due > 0 ||
        newCards > 0
    ) {
        primary =
            "ENTER estudar";
    } else {
        primary =
            "ENTER praticar";
    }

    drawFooter(
        primary +
        "     M menu");

    refreshFull();
}

void T5Display::showMainMenu() {

    clearBuffer();

    drawHeader(
        "MENU");

    drawText(
        "Ferramentas do terminal",
        MARGIN_X,
        126);

    drawChoice(
        1,
        "Sincronizacao",
        190);

    drawChoice(
        2,
        "Agenda de estudo",
        270);

    drawChoice(
        3,
        "Conexao",
        350);

    drawFooter(
        "1-3 selecionar     BACKSPACE voltar");

    refreshFull();
}

void T5Display::showAgenda(
    uint16_t dueNow,
    uint16_t laterToday,
    uint16_t tomorrow,
    uint16_t next7Days,
    const String& nextReview) {

    clearBuffer();

    drawHeader(
        "AGENDA");

    const int32_t labelX =
        MARGIN_X + 20;

    const int32_t valueX =
        EPD_WIDTH - 160;

    drawText(
        "Agora",
        labelX,
        145);

    drawText(
        String(dueNow),
        valueX,
        145);

    epd_draw_line(
        labelX,
        164,
        EPD_WIDTH - MARGIN_X,
        164,
        LIGHT_GRAY,
        framebuffer_);

    drawText(
        "Ainda hoje",
        labelX,
        205);

    drawText(
        String(laterToday),
        valueX,
        205);

    epd_draw_line(
        labelX,
        224,
        EPD_WIDTH - MARGIN_X,
        224,
        LIGHT_GRAY,
        framebuffer_);

    drawText(
        "Amanha",
        labelX,
        265);

    drawText(
        String(tomorrow),
        valueX,
        265);

    epd_draw_line(
        labelX,
        284,
        EPD_WIDTH - MARGIN_X,
        284,
        LIGHT_GRAY,
        framebuffer_);

    drawText(
        "Proximos 7 dias",
        labelX,
        325);

    drawText(
        String(next7Days),
        valueX,
        325);

    drawText(
        "Proxima revisao",
        labelX,
        395);

    drawText(
        nextReview.length()
            ? nextReview
            : "Sem revisao agendada",
        335,
        395);

    drawFooter(
        "BACKSPACE voltar");

    refreshFull();
}

void T5Display::showSyncMenu(
    size_t total,
    uint16_t pendingReviews,
    bool wifiConnected) {

    clearBuffer();

    drawHeader(
        "SINCRONIZACAO",
        wifiConnected
            ? ""
            : "sem rede");

    drawText(
        String(total) +
            " cartoes disponiveis",
        MARGIN_X,
        135);

    drawText(
        String(pendingReviews) +
            " revisoes aguardando envio",
        MARGIN_X,
        180);

    drawChoice(
        1,
        wifiConnected
            ? "Sincronizar com a conta"
            : "Sincronizacao pela rede indisponivel",
        285);

    drawChoice(
        2,
        "Sincronizar diretamente com o celular",
        370);

    drawFooter(
        "1 conta     2 celular     BACKSPACE voltar");

    refreshFull();
}

void T5Display::showConnectionMenu(
    bool wifiEnabled,
    bool wifiConnected,
    const String& ssid,
    size_t knownNetworks) {

    clearBuffer();

    String warning;

    if (!wifiEnabled) {
        warning =
            "Wi-Fi desligado";
    } else if (!wifiConnected) {
        warning =
            "sem conexao";
    }

    drawHeader(
        "CONEXAO",
        warning);

    if (wifiConnected) {
        drawText(
            "Rede atual",
            MARGIN_X,
            135);

        drawText(
            ssid.length()
                ? ssid
                : "rede conectada",
            MARGIN_X,
            178);
    } else {
        drawText(
            "Nenhuma rede ativa",
            MARGIN_X,
            158);
    }

    drawText(
        String(knownNetworks) +
            " redes conhecidas",
        MARGIN_X,
        235);

    drawChoice(
        1,
        "Configurar rede",
        325);

    drawChoice(
        2,
        wifiEnabled
            ? "Desligar Wi-Fi"
            : "Ligar Wi-Fi",
        405);

    drawFooter(
        "1 configurar     2 Wi-Fi     BACKSPACE voltar");

    refreshFull();
}

void T5Display::showLocalLink(
    const String& qrPayload,
    const String& ssid,
    const String& password,
    bool provisioning) {

    clearBuffer();

    drawHeader(
        provisioning
            ? "CONFIGURAR TERMINAL"
            : "SINCRONIZAR CELULAR",
        "5 min");

    drawQr(
        qrPayload,
        68,
        112,
        5);

    drawText(
        provisioning
            ? "Escaneie pelo aplicativo Mnemos"
            : "Abra a sincronizacao no aplicativo",
        448,
        150);

    drawText(
        "Rede temporaria",
        448,
        235);

    drawText(
        ssid,
        448,
        272);

    drawText(
        "Senha",
        448,
        330);

    drawText(
        password,
        448,
        367);

    drawFooter(
        "BACKSPACE cancelar");

    refreshFull();
}

void T5Display::showQuestion(
    const CardDefinition& card,
    uint8_t position,
    uint8_t total) {

    clearBuffer();

    drawHeader(
        truncateText(card.deck, 48),
        String(position + 1) +
            "/" +
            String(total));

    drawText(
        "RECUPERE DA MEMORIA",
        52,
        116);

    drawWrapped(
        card.question,
        52,
        158,
        EPD_WIDTH - 104,
        34,
        card.isObjective()
            ? 4
            : 6);

    if (card.isObjective()) {
        const uint8_t count =
            std::min<uint8_t>(
                card.optionCount,
                4);

        int32_t y =
            292;

        for (
            uint8_t i = 0;
            i < count;
            ++i
        ) {
            drawChoice(
                i + 1,
                card.options[i],
                y);

            y += 55;
        }

        drawFooter(
            "1-4 selecionar alternativa");

    } else {
        epd_draw_line(
            160,
            365,
            EPD_WIDTH - 160,
            365,
            LIGHT_GRAY,
            framebuffer_);

        drawText(
            "ENTER revelar somente depois de tentar",
            265,
            414);

        drawFooter(
            "ENTER revelar resposta");
    }

    refreshFull();
}

void T5Display::showSelfAssessment(
    const CardDefinition& card,
    uint8_t position,
    uint8_t total) {

    clearBuffer();

    drawHeader(
        "CONFERIR",
        String(position + 1) +
            "/" +
            String(total));

    drawText(
        "Pergunta",
        52,
        120);

    drawWrapped(
        card.question,
        52,
        156,
        EPD_WIDTH - 104,
        29,
        4);

    epd_draw_line(
        52,
        270,
        EPD_WIDTH - 52,
        270,
        LIGHT_GRAY,
        framebuffer_);

    drawText(
        "Resposta de referencia",
        52,
        310);

    drawWrapped(
        card.answer,
        52,
        347,
        EPD_WIDTH - 104,
        29,
        4);

    drawFooter(
        "1 nao recuperei     2 recuperei");

    refreshFull();
}
void T5Display::showObjectiveFeedback(
    const CardDefinition& card,
    uint8_t position,
    uint8_t total,
    int8_t selectedOptionIndex,
    Outcome outcome) {

    clearBuffer();

    drawHeader(
        "RESULTADO",
        String(position + 1) +
            "/" +
            String(total));

    drawText(
        outcome == Outcome::Correct
            ? "Resposta correta"
            : "Resposta incorreta",
        MARGIN_X,
        132);

    epd_draw_line(
        MARGIN_X,
        162,
        EPD_WIDTH - MARGIN_X,
        162,
        LIGHT_GRAY,
        framebuffer_);

    if (
        selectedOptionIndex >= 0 &&
        selectedOptionIndex <
            card.optionCount
    ) {
        drawText(
            "Sua escolha",
            60,
            225);

        drawWrapped(
            card.options[
                selectedOptionIndex],
            60,
            265,
            390,
            31,
            4);
    }

    if (
        card.correctOptionIndex >= 0 &&
        card.correctOptionIndex <
            card.optionCount
    ) {
        drawText(
            "Referencia",
            520,
            225);

        drawWrapped(
            card.options[
                card.correctOptionIndex],
            520,
            265,
            380,
            31,
            4);
    }

    drawFooter(
        "ENTER continuar");

    refreshFull();
}

void T5Display::showEffort(
    uint8_t position,
    uint8_t total) {

    clearBuffer();

    drawHeader(
        "ESFORCO DE RECUPERACAO",
        String(position + 1) +
            "/" +
            String(total));

    drawText(
        "Quanto esforco foi necessario para lembrar?",
        MARGIN_X,
        145);

    drawText(
        "Avalie o processo de recuperacao, nao a importancia do tema.",
        MARGIN_X,
        190);

    drawChoice(
        1,
        "Dificil",
        290);

    drawChoice(
        2,
        "Normal",
        355);

    drawChoice(
        3,
        "Facil",
        420);

    drawFooter(
        "1 dificil     2 normal     3 facil");

    refreshFull();
}

void T5Display::showSummary(
    const SessionStats& stats,
    uint16_t remainingDue,
    uint16_t remainingNew,
    const String& nextReview) {

    clearBuffer();

    drawHeader(
        stats.mode ==
                SessionMode::Practice
            ? "PRATICA CONCLUIDA"
            : "SESSAO CONCLUIDA");

    drawText(
        String(stats.reviewed) +
            " cartoes trabalhados",
        MARGIN_X,
        140);

    drawText(
        String(stats.correct) +
            " recuperados",
        MARGIN_X,
        205);

    drawText(
        String(stats.incorrect) +
            " para reforcar",
        360,
        205);

    const uint32_t minutes =
        stats.durationSeconds() /
        60U;

    const uint32_t seconds =
        stats.durationSeconds() %
        60U;

    drawText(
        "Duracao  " +
            String(minutes) +
            "m " +
            String(seconds) +
            "s",
        MARGIN_X,
        260);

    epd_draw_line(
        MARGIN_X,
        292,
        EPD_WIDTH - MARGIN_X,
        292,
        LIGHT_GRAY,
        framebuffer_);

    if (remainingDue > 0) {
        drawText(
            String(remainingDue) +
                " revisoes ainda pendentes",
            MARGIN_X,
            345);

    } else if (remainingNew > 0) {
        drawText(
            String(remainingNew) +
                " cartoes novos disponiveis",
            MARGIN_X,
            345);

    } else {
        drawText(
            "Sessao encerrada por agora",
            MARGIN_X,
            345);
    }

    if (nextReview.length() > 0) {
        drawText(
            "Proxima revisao",
            MARGIN_X,
            400);

        drawText(
            nextReview,
            300,
            400);
    }

    drawFooter(
        "1 estudar novamente     ENTER concluir");

    refreshFull();
}
