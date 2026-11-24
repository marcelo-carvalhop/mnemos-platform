#pragma once

#include <Arduino.h>

/*
 * Os papéis tipográficos do terminal.
 *
 * Os três primeiros são os tamanhos antigos, agora em Geist com 16 tons:
 * mantêm a altura de maiúscula das fontes de 1 bit, então as telas que ainda
 * os usam cabem onde cabiam. Os demais seguem o design system "Marinho"
 * (docs/design/DESIGN-SYSTEM.md), na escala de ~1,4 px desta tela por px CSS
 * do celular. Gerados por tools/fonts/gen_mnemos_fonts.py.
 */
enum class MnemosFontRole : uint8_t {
    Meta14 = 0,
    Body18 = 1,
    Title22 = 2,
    Eyebrow,    // Geist Mono Medium 17, caixa alta (quem chama converte), tracking .10 em
    Small,      // Geist 18: metadados
    Body,       // Geist 21: texto corrido
    Strong,     // Geist SemiBold 21: botões e rótulos
    Heading,    // Geist SemiBold 26: nome de baralho, título de bloco
    Title,      // Geist Medium 44: título de tela ("Hoje")
    Figure,     // Geist 50: numeral de ladrilho (só ASCII)
    Display,    // Geist 96: numeral do bloco-âncora (só ASCII)
    Card,       // Literata 32: pergunta e resposta
    CardSmall,  // Literata 25: card longo
    Hanzi,      // Noto Sans SC 140 (recorte): o ideograma do card de mandarim
};

int32_t mnemosFontTextWidth(
    const String& text,
    MnemosFontRole role);

bool mnemosFontTextBounds(
    const String& text,
    MnemosFontRole role,
    int32_t& left,
    int32_t& right);

bool mnemosFontVisualBounds(
    const String& text,
    MnemosFontRole role,
    int32_t& left,
    int32_t& top,
    int32_t& right,
    int32_t& bottom);

/*
 * Desenha com cobertura: `color` é misturado ao que já está no canvas na
 * proporção da cobertura de cada pixel do glifo (0..15). Texto escuro sobre
 * claro e claro sobre escuro saem suavizados do mesmo jeito.
 */
void mnemosFontDrawText(
    const String& text,
    int32_t x,
    int32_t baselineY,
    uint8_t* framebuffer,
    int32_t canvasWidth,
    int32_t canvasHeight,
    MnemosFontRole role,
    uint8_t color = 0x00,
    uint8_t scale = 1);

/*
 * Caixa alta que entende os acentos do português ("sincronização" →
 * "SINCRONIZAÇÃO"). String::toUpperCase só converte ASCII.
 */
String mnemosUpper(const String& text);
