#pragma once

#include <stddef.h>
#include <stdint.h>

/*
 * Gerador de waveforms do Mnemos para o ED047TC1 (T5S3 Pro).
 *
 * Por que existe:
 *
 *   O waveform embutido do epdiy para o ED047TC1 foi gerado para o
 *   driver I2S, no qual cada fase tem duração própria (phase_times).
 *   No ESP32-S3 o epdiy usa o periférico LCD e ignora phase_times:
 *   todos os quadros têm a mesma duração. O GC16 embutido entrega
 *   então apenas 15 quadros curtos por excursão preto<->branco,
 *   insuficiente para saturar as partículas. O resultado é o
 *   "fantasma" forte da tela anterior.
 *
 * O que este módulo faz:
 *
 *   Gera, em tempo de execução, tabelas no formato EpdWaveformPhases
 *   (fase x destino x origem, 2 bits por pixel) com:
 *
 *   - número de quadros de saturação N calculado a partir do período
 *     real de quadro medido no hardware e da temperatura;
 *   - balanço DC exato: o impulso líquido de qualquer transição
 *     f -> t é Phi(t) - Phi(f), com Phi(l) = levelFrames(l, N).
 *     Qualquer ciclo de telas soma zero e o DC acumulado no
 *     pixel fica limitado;
 *   - troca de tela (Clean) leva TODOS os pixels ao preto e ao
 *     branco, com sobre-acionamento simétrico em cada extremo, antes
 *     do destino. Pixels escuros que continuam escuros também passam
 *     pelo branco: é isso que apaga restos dentro de botões escuros;
 *   - "agitação" opcional (pares escuro/claro de impulso nulo);
 *   - quadros finais neutros (0 V), para que nenhum pixel fique
 *     retendo tensão no capacitor de armazenamento após o update;
 *   - compactação: quadros em que nenhum par (origem, destino)
 *     presente na imagem recebe tensão são removidos.
 *
 * Não depende de Arduino nem do epdiy: é testável no host
 * (ver test/epd_waveform_builder_test.cpp).
 */

namespace EpdWaveformBuilder {

constexpr uint8_t OP_NONE = 0;
constexpr uint8_t OP_DARKEN = 1;
constexpr uint8_t OP_LIGHTEN = 2;

constexpr uint8_t LEVELS = 16;
constexpr uint8_t WHITE_LEVEL = 15;

// Bytes por fase: 16 destinos x 16 origens x 2 bits.
constexpr size_t BYTES_PER_PHASE = 64;

// epdiy guarda o número de fases em uint8_t.
constexpr uint16_t MAX_PHASES = 250;

constexpr uint8_t MIN_SATURATION_FRAMES = 4;
constexpr uint8_t MAX_SATURATION_FRAMES = 72;
constexpr uint8_t MAX_OVERDRIVE_FRAMES = 40;
constexpr uint8_t MAX_FLASH_CYCLES = 3;
constexpr uint8_t MAX_AGITATION_PAIRS = 8;
constexpr uint8_t MAX_SETTLE_FRAMES = 4;

constexpr size_t MAX_LUT_BYTES =
    static_cast<size_t>(MAX_PHASES) * BYTES_PER_PHASE;

enum class Kind : uint8_t {
    /*
     * Atualização com flash, aplicada a TODOS os pixels do painel
     * (inclusive os que não mudaram). Com N = saturationFrames e
     * X = overdriveFrames:
     *
     *   [agitação]
     *   escurece Phi(origem) + X   -> todos no preto, X além do limite
     *   clareia  N + X             -> todos no branco, X além do limite
     *   [flashCycles x (escurece N + X, clareia N + X)]
     *   escurece N - Phi(destino)  -> destino a partir do branco
     *
     * Impulso líquido: Phi(destino) - Phi(origem). É a transição
     * usada em troca de tela; elimina o histórico de todo pixel.
     */
    Clean,

    /*
     * Atualização sem flash, apenas pixels que mudaram
     * (origem == destino é sempre no-op):
     *
     *   clareia até o branco (proporcional à origem) e escurece até
     *   o destino. Transições puramente preto/branco ocupam um único
     *   bloco de N quadros. Também é o desenho "a partir do branco"
     *   depois de uma limpeza profunda.
     */
    Direct,
};

struct Params {
    Kind kind = Kind::Clean;
    uint8_t saturationFrames = 20;

    // Só Clean: quadros além da saturação em cada extremo.
    uint8_t overdriveFrames = 0;

    // Só Clean: ciclos preto/branco extras antes do destino.
    uint8_t flashCycles = 0;

    uint8_t agitationPairs = 0;
    uint8_t settleFrames = 1;
};

// Conjunto de pares presentes; índice = (destino << 4) | origem,
// exatamente o byte do difference image do epdiy.
struct PairSet {
    uint8_t bits[32] = {};

    void clear();
    void addAll();
    void add(uint8_t interlacedByte) {
        bits[interlacedByte >> 3] |=
            static_cast<uint8_t>(1U << (interlacedByte & 7U));
    }
    bool contains(uint8_t interlacedByte) const {
        return (bits[interlacedByte >> 3] >> (interlacedByte & 7U)) & 1U;
    }
    bool empty() const;
};

inline uint8_t pairIndex(uint8_t from, uint8_t to) {
    return static_cast<uint8_t>(((to & 0x0FU) << 4) | (from & 0x0FU));
}

// Phi(l): quadros de saturação equivalentes ao nível l (0 = preto).
uint8_t levelFrames(uint8_t level, uint8_t saturationFrames);

// Número de quadros antes da compactação e dos quadros neutros
// (0 se os parâmetros forem inválidos).
uint16_t rawFrameCount(const Params& params);

// true se a tabela completa (com quadros neutros) cabe em MAX_PHASES.
bool fits(const Params& params);

// Operação (OP_*) do par no quadro bruto `frame`.
uint8_t rawOp(
    const Params& params,
    uint16_t frame,
    uint8_t from,
    uint8_t to);

/*
 * Gera a tabela compactada em `out`.
 *
 * used == nullptr considera todos os 256 pares.
 * Retorna o número de fases (0 se os parâmetros forem inválidos ou
 * a capacidade insuficiente). Se nenhum par usado exigir tensão,
 * retorna apenas os quadros neutros (ou 0 se settleFrames == 0).
 */
uint16_t build(
    const Params& params,
    const PairSet* used,
    uint8_t* out,
    size_t capacity);

// Lê a operação de uma tabela gerada (para testes/diagnóstico).
uint8_t opAt(
    const uint8_t* luts,
    uint16_t phase,
    uint8_t from,
    uint8_t to);

}  // namespace EpdWaveformBuilder
