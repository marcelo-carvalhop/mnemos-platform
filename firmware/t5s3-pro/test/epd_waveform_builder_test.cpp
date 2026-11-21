/*
 * Teste de host do gerador de waveforms.
 *
 *   cd firmware/t5s3-pro
 *   g++ -std=c++17 -O2 -Wall -Wextra -Iinclude \
 *       test/epd_waveform_builder_test.cpp \
 *       src/epd_waveform_builder.cpp \
 *       -o /tmp/epd_waveform_builder_test && /tmp/epd_waveform_builder_test
 *
 * Verifica, para cada combinação de parâmetros, num modelo de
 * partícula saturável (posição 0 = preto, N = branco):
 *   - balanço DC exato: (#clarear - #escurecer) == Phi(t) - Phi(f);
 *   - estado final correto;
 *   - Clean: TODO pixel (inclusive preto->preto) visita o preto e o
 *     branco, e o acionamento contra o limite é exatamente o
 *     sobre-acionamento configurado;
 *   - Direct: nunca toca pixels que não mudaram e nunca aciona
 *     contra o limite;
 *   - quadros neutros no fim e nenhum quadro ocioso no meio;
 *   - limite de 250 fases do epdiy.
 */

#include "epd_waveform_builder.h"

#include <cstdio>
#include <cstdlib>
#include <vector>

using namespace EpdWaveformBuilder;

namespace {

int failures = 0;

void expect(bool condition, const char* what, const Params& p, int from, int to) {
    if (condition) {
        return;
    }

    ++failures;

    if (failures < 40) {
        std::printf(
            "FAIL %s kind=%d n=%u x=%u cycles=%u agit=%u settle=%u from=%d to=%d\n",
            what,
            static_cast<int>(p.kind),
            p.saturationFrames,
            p.overdriveFrames,
            p.flashCycles,
            p.agitationPairs,
            p.settleFrames,
            from,
            to);
    }
}

void checkTable(const Params& p, const PairSet* used) {
    std::vector<uint8_t> lut(MAX_LUT_BYTES, 0xA5);

    const uint16_t phases = build(p, used, lut.data(), lut.size());
    const uint16_t raw = rawFrameCount(p);

    if (!fits(p)) {
        expect(phases == 0, "oversized table accepted", p, -1, -1);
        return;
    }

    expect(phases > 0 || p.settleFrames == 0, "empty table", p, -1, -1);
    expect(phases <= MAX_PHASES, "phase limit", p, -1, -1);
    expect(phases <= raw + p.settleFrames, "compaction bound", p, -1, -1);

    for (uint16_t ph = phases >= p.settleFrames ? phases - p.settleFrames : 0; ph < phases; ++ph) {
        for (size_t b = 0; b < BYTES_PER_PHASE; ++b) {
            expect(lut[ph * BYTES_PER_PHASE + b] == 0, "settle frame not neutral", p, -1, -1);
        }
    }

    const uint16_t active = phases - p.settleFrames;
    const uint8_t n = p.saturationFrames;
    const bool clean = p.kind == Kind::Clean;

    for (uint16_t ph = 0; ph < active; ++ph) {
        bool any = false;
        for (int pair = 0; pair < 256 && !any; ++pair) {
            if (used && !used->contains(static_cast<uint8_t>(pair))) {
                continue;
            }
            any = opAt(lut.data(), ph, pair & 0x0F, pair >> 4) != OP_NONE;
        }
        expect(any, "idle frame kept", p, -1, -1);
    }

    for (int from = 0; from < 16; ++from) {
        for (int to = 0; to < 16; ++to) {
            const uint8_t index = pairIndex(from, to);

            if (used && !used->contains(index)) {
                continue;
            }

            const int phiFrom = levelFrames(from, n);
            const int phiTo = levelFrames(to, n);

            int position = phiFrom;
            int net = 0;
            int touched = 0;
            int clamped = 0;
            bool sawBlack = position == 0;
            bool sawWhite = position == n;

            for (uint16_t ph = 0; ph < phases; ++ph) {
                const uint8_t op = opAt(lut.data(), ph, from, to);

                expect(op != 3, "invalid op code", p, from, to);

                if (op == OP_DARKEN) {
                    --net;
                    ++touched;
                    if (position == 0) {
                        ++clamped;
                    } else {
                        --position;
                    }
                } else if (op == OP_LIGHTEN) {
                    ++net;
                    ++touched;
                    if (position == n) {
                        ++clamped;
                    } else {
                        ++position;
                    }
                }

                sawBlack |= position == 0;
                sawWhite |= position == n;
            }

            expect(net == phiTo - phiFrom, "DC balance", p, from, to);
            expect(position == phiTo, "final state", p, from, to);

            if (clean) {
                expect(sawBlack && sawWhite, "clean pixel skipped a rail", p, from, to);

                // Agitação não aciona contra o limite? Pode: pixel preto
                // escurece no 2º quadro do par. Conta só o restante.
                const int expected =
                    (2 + 2 * p.flashCycles) * p.overdriveFrames;

                expect(
                    clamped >= expected &&
                        clamped <= expected + 2 * p.agitationPairs,
                    "clean overdrive amount",
                    p,
                    from,
                    to);
            } else {
                expect(clamped <= 0, "direct drove against a rail", p, from, to);

                if (from == to) {
                    expect(touched == 0, "direct touched unchanged pixel", p, from, to);
                }
            }
        }
    }
}

}  // namespace

int main() {
    const uint8_t frames[] = {4, 5, 7, 12, 15, 17, 20, 25, 33, 48, 60, 72};
    const uint8_t overdrives[] = {0, 1, 5, 8, 20, 40};

    for (int kind = 0; kind < 2; ++kind) {
        for (uint8_t n : frames) {
            for (uint8_t x : overdrives) {
                for (uint8_t cycles = 0; cycles <= 2; ++cycles) {
                    for (uint8_t agit = 0; agit <= 2; ++agit) {
                        for (uint8_t settle = 0; settle <= 2; ++settle) {
                            Params p;
                            p.kind = kind == 0 ? Kind::Clean : Kind::Direct;
                            p.saturationFrames = n;
                            p.overdriveFrames = x;
                            p.flashCycles = cycles;
                            p.agitationPairs = agit;
                            p.settleFrames = settle;

                            checkTable(p, nullptr);

                            std::srand(n * 131 + x * 31 + cycles * 7 + agit * 3 + settle + kind * 1000);
                            for (int trial = 0; trial < 2; ++trial) {
                                PairSet set;
                                const int count = 1 + std::rand() % 12;
                                for (int i = 0; i < count; ++i) {
                                    set.add(static_cast<uint8_t>(std::rand() & 0xFF));
                                }
                                checkTable(p, &set);
                            }
                        }
                    }
                }
            }
        }
    }

    // Botão escuro que continua escuro: na troca de tela ele pisca.
    {
        Params p;
        p.kind = Kind::Clean;
        p.saturationFrames = 17;
        p.overdriveFrames = 6;
        p.settleFrames = 1;

        PairSet set;
        set.add(pairIndex(0, 0));    // fundo preto do botão
        set.add(pairIndex(5, 5));    // fundo cinza do botão
        set.add(pairIndex(15, 0));   // texto antigo -> fundo
        set.add(pairIndex(0, 15));   // fundo -> texto novo

        std::vector<uint8_t> lut(MAX_LUT_BYTES);
        const uint16_t phases = build(p, &set, lut.data(), lut.size());

        int lighten00 = 0;
        for (uint16_t ph = 0; ph < phases; ++ph) {
            lighten00 += opAt(lut.data(), ph, 0, 0) == OP_LIGHTEN;
        }

        expect(lighten00 == 17 + 6, "black button pixel not flashed", p, 0, 0);
        expect(phases == 2 * 23 + 17 + 1, "clean length", p, 0, 0);
    }

    // Direct preto/branco cabe em N quadros (+ neutros).
    {
        Params p;
        p.kind = Kind::Direct;
        p.saturationFrames = 25;
        p.agitationPairs = 0;
        p.settleFrames = 1;

        PairSet set;
        set.add(pairIndex(0, 15));
        set.add(pairIndex(15, 0));
        set.add(pairIndex(15, 15));
        set.add(pairIndex(0, 0));

        std::vector<uint8_t> lut(MAX_LUT_BYTES);
        const uint16_t phases = build(p, &set, lut.data(), lut.size());
        expect(phases == 26, "direct B/W length", p, 0, 15);
    }

    // Parâmetros inválidos.
    {
        Params p;
        p.saturationFrames = MAX_SATURATION_FRAMES + 1;
        std::vector<uint8_t> lut(MAX_LUT_BYTES);
        expect(build(p, nullptr, lut.data(), lut.size()) == 0, "invalid params accepted", p, -1, -1);
    }

    // Pior caso que o motor usa (N=60, X=30, 0 ciclos, 2 pares, 4 neutros).
    {
        Params p;
        p.kind = Kind::Clean;
        p.saturationFrames = 60;
        p.overdriveFrames = 30;
        p.agitationPairs = 2;
        p.settleFrames = 4;
        std::vector<uint8_t> lut(MAX_LUT_BYTES);
        expect(fits(p), "engine worst case does not fit", p, -1, -1);
        const uint16_t phases = build(p, nullptr, lut.data(), lut.size());
        expect(phases > 0 && phases <= MAX_PHASES, "worst case length", p, -1, -1);
    }

    if (failures != 0) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }

    std::printf("epd_waveform_builder: OK\n");
    return 0;
}
