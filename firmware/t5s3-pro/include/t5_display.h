#pragma once

#include <Arduino.h>

#include "mnemos_fonts.h"
#include "models.h"
#include "wifi_keyboard.h"

enum class DisplayOrientation : uint8_t {
    Portrait = 0,
    Landscape = 1,
};

struct WeeklyPlanDay {
    String label;
    String decks;
    uint16_t cards = 0;
    bool today = false;
};

struct DeckSummary {
    String id;
    String name;
    uint16_t cardCount = 0;
    uint16_t dueCount = 0;
    bool selected = false;
};

class T5Display {
public:
    bool begin();
    bool ready() const {
        return framebuffer_ != nullptr &&
               physicalFramebuffer_ != nullptr;
    }

    void setBatteryStatus(
        bool available,
        uint8_t percent,
        bool charging = false);

    void setNetworkStatus(
        bool enabled,
        bool connected);

    // Ciclos preto/branco balanceados; deixa o painel branco e
    // sincronizado. A próxima tela é desenhada a partir do branco.
    void deepClean();

    void setOrientation(
        DisplayOrientation orientation);

    DisplayOrientation orientation() const {
        return orientation_;
    }


    bool portrait() const {
        return true;
    }


    int32_t logicalWidth() const;
    int32_t logicalHeight() const;

    void showBoot(
        const String& message);

    void showTouchMissing();

    void showHome(
        const WeeklyPlanDay* days,
        uint8_t dayCount,
        bool trustedClock,
        bool canResume);

    void showMainMenu();

    void showPowerOff(bool automatic);

    void showSettings(
        const String& backlightLabel);

    void showDecks(
        const DeckSummary* decks,
        size_t count,
        bool anySelected,
        bool canResume);

    void showAgenda(
        uint16_t dueNow,
        uint16_t laterToday,
        uint16_t tomorrow,
        uint16_t next7Days,
        const String& nextReview);

    void showSyncMenu(
        size_t total,
        uint16_t pendingReviews,
        bool wifiConnected);

    void showConnectionMenu(
        bool wifiEnabled,
        bool wifiConnected,
        const String& ssid,
        size_t knownNetworks);

    void showWifiScanning();

    void showWifiNetworks(
        const String* ssids,
        const int32_t* rssis,
        const uint8_t* flags,
        size_t count);

    void showWifiPassword(
        const String& ssid,
        size_t passwordLength,
        WifiKeyboardPage page,
        const String& hint = "");

    void showWifiMessage(
        const String& title,
        const String& message,
        const String& primaryLabel);

    void showStorage(
        bool mounted,
        uint64_t cardSizeBytes,
        uint64_t usedBytes,
        const String* fileNames,
        const uint32_t* fileSizes,
        size_t fileCount,
        const String& status);

    // "Conectar pelo site": o código para digitar em mnemoscards.com e um QR
    // que abre a página já com ele preenchido.
    void showWebPairing(
        const String& code,
        const String& url,
        const String& hint);

    void showLocalLink(
        const String& qrPayload,
        const String& ssid,
        const String& password,
        bool provisioning);

    void showQuestion(
        const CardDefinition& card,
        uint8_t position,
        uint8_t total);

    void showSelfAssessment(
        const CardDefinition& card,
        uint8_t position,
        uint8_t total);

    void showObjectiveFeedback(
        const CardDefinition& card,
        uint8_t position,
        uint8_t total,
        int8_t selectedOptionIndex,
        Outcome outcome);

    void showEffort(
        uint8_t position,
        uint8_t total);

    void showSummary(
        const SessionStats& stats,
        uint16_t remainingDue,
        uint16_t remainingNew,
        const String& nextReview);

    void showAbortConfirm(
        uint16_t remainingInQueue);

    void showTouchFeedback(
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h);

    /*
     * Envia o canvas lógico (540×960, 4 bits por pixel, base64) para `out`,
     * entre as linhas "@mnemos-screen <w> <h>" e "@mnemos-screen-end".
     * Ferramenta de bancada: tools/hmi_capture.py.
     */
    void dumpCanvas(Print& out) const;

private:
    uint8_t* framebuffer_ = nullptr;
    uint8_t* physicalFramebuffer_ = nullptr;

    // Aba ativa da tela em desenho (0..4), ou -1 numa tela sem abas. Cada
    // show*() com abas define logo depois de clearBuffer().
    int8_t tab_ = -1;

    // Subtela do "Mais" (Conexão, Configurações, Armazenamento, Agenda):
    // o topo mostra "‹ Voltar" no lugar da marca.
    bool back_ = false;

    bool powerOn_ = false;
    bool batteryAvailable_ = false;
    uint8_t batteryPercent_ = 0;
    bool batteryCharging_ = false;
    bool networkEnabled_ = false;
    bool networkConnected_ = false;

    DisplayOrientation orientation_ =
        DisplayOrientation::Portrait;

    void clearBuffer();
    void ensurePower();
    void releasePower();

    /*
     * Publica o canvas no painel.
     *
     * screenKey identifica a tela; por padrão é o nome da função
     * show*() chamadora. Troca de tela => transição completa com
     * flash em todo o painel. Mesma tela com mudança pequena =>
     * atualização parcial sem flash. Ver docs/EPD_REFRESH.md.
     */
    void refreshFull(
        const char* screenKey = __builtin_FUNCTION());

    // Caminho anterior (GC16 embutido), com EPD_USE_LEGACY_REFRESH.
    void refreshLegacy();

    void putPixel(
        int32_t x,
        int32_t y,
        uint8_t color);

    void fillRect(
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h,
        uint8_t color);

    void drawLine(
        int32_t x0,
        int32_t y0,
        int32_t x1,
        int32_t y1,
        uint8_t color);

    void drawRect(
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h,
        uint8_t color);

    void drawText(
        const String& text,
        int32_t x,
        int32_t baselineY,
        MnemosFontRole role =
            MnemosFontRole::Body18,
        uint8_t color = 0x00,
        uint8_t scale = 1);

    int32_t textWidth(
        const String& text,
        MnemosFontRole role) const;

int32_t centeredTextOriginX(
        const String& text,
        int32_t centerX,
        MnemosFontRole role,
        uint8_t scale = 1) const;

    void drawCenteredText(
        const String& text,
        int32_t centerX,
        int32_t baselineY,
        MnemosFontRole role =
            MnemosFontRole::Body18,
        uint8_t color = 0x00,
        uint8_t scale = 1);

int32_t centeredTextBaselineY(
        const String& text,
        int32_t centerY,
        MnemosFontRole role,
        uint8_t scale = 1) const;

    int32_t rightAlignedTextOriginX(
        const String& text,
        int32_t rightEdge,
        MnemosFontRole role,
        uint8_t scale = 1) const;

    String fitTextToWidth(
        const String& text,
        int32_t maxWidth,
        MnemosFontRole role) const;

    void drawCenteredTextInRect(
        const String& text,
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h,
        MnemosFontRole role =
            MnemosFontRole::Body18,
        uint8_t color = 0x00,
        uint8_t scale = 1);

    int32_t drawWrapped(
        const String& text,
        int32_t x,
        int32_t y,
        int32_t maxWidth,
        int32_t lineHeight,
        uint8_t maxLines,
        MnemosFontRole role =
            MnemosFontRole::Body18,
        uint8_t color = 0x00);

    // --- Marinho: as primitivas do design system --------------------------
    //
    // Mesmo vocabulário do web e do app (docs/design/DESIGN-SYSTEM.md): cards
    // de raio 8 com borda fina, botões e chips em pílula, sobrancelha em mono
    // caixa alta. As bordas são suavizadas com os 16 tons do painel.

    // Mistura `color` no pixel na proporção coverage/16.
    void blendPixel(
        int32_t x,
        int32_t y,
        uint8_t color,
        uint8_t coverage16);

    void fillRoundRect(
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h,
        int32_t r,
        uint8_t color);

    void strokeRoundRect(
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h,
        int32_t r,
        int32_t thickness,
        uint8_t color);

    // Card de raio 8 com borda fina, fundo branco.
    void drawSurfaceCard(
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h);

    // O bloco-âncora do web (.mn-panel): claro, com grade fina no canto.
    void drawGridPanel(
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h);

    // Pílula: cheia (tinta, texto branco) ou contornada (texto tinta).
    void drawPill(
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h,
        const String& label,
        bool filled,
        MnemosFontRole role = MnemosFontRole::Strong);

    // Sobrancelha: Geist Mono, caixa alta, cinza.
    void drawEyebrow(
        const String& text,
        int32_t x,
        int32_t baselineY,
        uint8_t color = 0x48);

    // O símbolo: dois cards sobrepostos, `size` px de lado.
    void drawBrandMark(
        int32_t x,
        int32_t y,
        int32_t size);

    // A barra do topo do web no celular: símbolo + "Mnemos" à esquerda,
    // rede e bateria à direita. `back` troca o símbolo por "‹ Voltar".
    void drawTopBar(
        bool back = false,
        bool showAbort = false);

    // A barra de abas do web no celular. `active` é o índice da aba atual
    // (0 Hoje, 1 Baralhos, 2 Agenda, 3 Sincronizar, 4 Mais) ou -1.
    void drawTabBar(int8_t active);

    // Sobrancelha + título grande no topo do conteúdo. Devolve o y livre.
    int32_t drawPageHeader(
        const String& eyebrow,
        const String& title,
        int32_t top);

        void drawSystemBar(
        const String& title,
        bool showMenu,
        bool showAbort,
        const String& rightMeta = "",
        bool showHome = false,
        bool showContext = true);

    void drawContextStrip(
        const String& title,
        const String& meta = "");

    // Linha de baralho: nome, metadado, selo "N hoje" e seleção.
    void drawDeckRow(
        const String& name,
        const String& meta,
        uint32_t due,
        bool selected,
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h);

    // Ladrilho: sobrancelha, número e unidade.
    void drawStatTile(
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h,
        const String& eyebrow,
        const String& value,
        const String& unit);

    // O topo das telas de estudo: baralho, traços de progresso, contagem.
    void drawStudyHeader(
        const String& deck,
        uint8_t position,
        uint8_t total);

    // Texto de card quebrado em linhas e centrado na caixa.
    void drawCardText(
        const String& text,
        int32_t x,
        int32_t top,
        int32_t w,
        int32_t h,
        MnemosFontRole role,
        int32_t lineHeight,
        uint8_t color);

    // Sobrancelha (estado) + título grande, abaixo da barra do topo.
    void drawScreenHeader(
        const String& title,
        const String& meta);

    void drawHomeIcon(
        int32_t x,
        int32_t y);

    void drawMenuIcon(
        int32_t x,
        int32_t y);

    void drawSyncIcon(
        int32_t x,
        int32_t y);

    void drawRotateIcon(
        int32_t x,
        int32_t y);

    void drawAbortIcon(
        int32_t x,
        int32_t y);

    void drawBatteryIcon(
        int32_t x,
        int32_t y);

    void drawNetworkIcon(
        int32_t x,
        int32_t y);

    void drawPrimaryButton(
        const String& label);

    void drawPrimarySplit(
        const String& left,
        const String& right,
        bool emphasizeLeft = false);

    void drawPrimaryTriple(
        const String& left,
        const String& middle,
        const String& right);

    void drawChoiceCard(
        uint8_t number,
        const String& label,
        int32_t x,
        int32_t y,
        int32_t w,
        int32_t h,
        bool selected = false,
        char marker = '\0');

    void drawAgendaBar(
        const String& label,
        uint16_t value,
        uint16_t maximum,
        int32_t x,
        int32_t y,
        int32_t w);

    void drawCenteredHanzi(
        const String& text,
        int32_t centerX,
        int32_t baselineY,
        uint8_t scale);

    void drawQr(
        const String& payload,
        int32_t originX,
        int32_t originY,
        int scale);

    int32_t systemBarHeight() const;
    int32_t actionTop() const;
};
