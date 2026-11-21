#pragma once

#include <Arduino.h>

// Normaliza texto vindo do app/web para o que a tela e-paper sabe desenhar.
//
// As fontes embutidas cobrem ASCII, Latin-1, Latin Extended-A, pinyin e um
// subconjunto CJK. Cartões criados no navegador ou pela IA trazem com
// frequência aspas tipográficas, travessões, setas, letras gregas, índices,
// emoji e, vindo do macOS, acentos decompostos (NFD). Sem isto cada um vira
// "?" na tela.
//
// O texto é normalizado só para exibição no terminal: o conteúdo canônico
// continua no servidor e o terminal nunca envia cartões de volta.
namespace TextSanitizer {

String forDisplay(const String& input);

// Corta em no máximo maxBytes sem quebrar uma sequência UTF-8.
String truncateUtf8(const String& input, size_t maxBytes);

}  // namespace TextSanitizer
