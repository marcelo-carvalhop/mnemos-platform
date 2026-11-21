#include "epd_waveform_builder.h"

#include <string.h>

namespace EpdWaveformBuilder {

namespace {

bool validParams(
    const Params& params) {

    return
        params.saturationFrames >= MIN_SATURATION_FRAMES &&
        params.saturationFrames <= MAX_SATURATION_FRAMES &&
        params.overdriveFrames <= MAX_OVERDRIVE_FRAMES &&
        params.flashCycles <= MAX_FLASH_CYCLES &&
        params.agitationPairs <= MAX_AGITATION_PAIRS &&
        params.settleFrames <= MAX_SETTLE_FRAMES;
}

uint8_t agitationOp(
    uint16_t frame,
    uint8_t from) {

    /*
     * Cada par começa afastando o pixel do estado em que ele já
     * está saturado e depois o devolve: pixels escuros clareiam
     * primeiro, pixels claros escurecem primeiro. Impulso líquido
     * zero e nenhum quadro desperdiçado contra o limite óptico.
     */
    const bool lightenFirst =
        from < 8;

    const bool firstOfPair =
        (frame % 2U) == 0U;

    return
        firstOfPair == lightenFirst
            ? OP_LIGHTEN
            : OP_DARKEN;
}

}  // namespace


void PairSet::clear() {
    memset(bits, 0, sizeof(bits));
}

void PairSet::addAll() {
    memset(bits, 0xFF, sizeof(bits));
}

bool PairSet::empty() const {
    for (size_t i = 0; i < sizeof(bits); ++i) {
        if (bits[i] != 0) {
            return false;
        }
    }

    return true;
}


uint8_t levelFrames(
    uint8_t level,
    uint8_t saturationFrames) {

    if (level > WHITE_LEVEL) {
        level = WHITE_LEVEL;
    }

    // round(level * N / 15), meio para cima.
    const uint32_t scaled =
        static_cast<uint32_t>(level) *
        static_cast<uint32_t>(saturationFrames) *
        2U +
        WHITE_LEVEL;

    return
        static_cast<uint8_t>(
            scaled /
            (2U * WHITE_LEVEL));
}


uint16_t rawFrameCount(
    const Params& params) {

    if (!validParams(params)) {
        return 0;
    }

    const uint32_t n =
        params.saturationFrames;

    uint32_t frames =
        2U * params.agitationPairs;

    if (params.kind == Kind::Clean) {
        const uint32_t rail =
            n + params.overdriveFrames;

        // preto + branco + ciclos extras + destino.
        frames +=
            2U * rail +
            2U * rail * params.flashCycles +
            n;
    } else {
        frames += 2U * n;
    }

    return
        frames > 0xFFFFU
            ? 0xFFFFU
            : static_cast<uint16_t>(frames);
}


bool fits(
    const Params& params) {

    if (!validParams(params)) {
        return false;
    }

    return
        static_cast<uint32_t>(rawFrameCount(params)) +
            params.settleFrames <=
        MAX_PHASES;
}


uint8_t rawOp(
    const Params& params,
    uint16_t frame,
    uint8_t from,
    uint8_t to) {

    if (!validParams(params)) {
        return OP_NONE;
    }

    from &= 0x0FU;
    to &= 0x0FU;

    if (
        params.kind == Kind::Direct &&
        from == to
    ) {
        return OP_NONE;
    }

    const uint16_t n =
        params.saturationFrames;

    const uint16_t agitationFrames =
        static_cast<uint16_t>(
            2U * params.agitationPairs);

    if (frame < agitationFrames) {
        return agitationOp(
            frame,
            from);
    }

    uint16_t f =
        static_cast<uint16_t>(
            frame - agitationFrames);

    const uint16_t fromFrames =
        levelFrames(from, params.saturationFrames);

    const uint16_t toFrames =
        levelFrames(to, params.saturationFrames);

    if (params.kind == Kind::Clean) {
        const uint16_t x =
            params.overdriveFrames;

        const uint16_t rail =
            static_cast<uint16_t>(n + x);

        /*
         * Bloco 1 (N + X): escurece Phi(origem) + X, alinhado à
         * direita. Todos chegam ao preto juntos, com X quadros de
         * sobre-acionamento (inclusive quem já era preto).
         */
        if (f < rail) {
            return
                f >= rail - (fromFrames + x)
                    ? OP_DARKEN
                    : OP_NONE;
        }

        f = static_cast<uint16_t>(f - rail);

        // Bloco 2 (N + X): branco pleno + X para todos.
        if (f < rail) {
            return OP_LIGHTEN;
        }

        f = static_cast<uint16_t>(f - rail);

        // Ciclos extras: preto pleno + X, branco pleno + X.
        for (
            uint8_t cycle = 0;
            cycle < params.flashCycles;
            ++cycle
        ) {
            if (f < rail) {
                return OP_DARKEN;
            }

            f = static_cast<uint16_t>(f - rail);

            if (f < rail) {
                return OP_LIGHTEN;
            }

            f = static_cast<uint16_t>(f - rail);
        }

        // Bloco final (N): do branco até o destino.
        if (f < n) {
            return
                f < n - toFrames
                    ? OP_DARKEN
                    : OP_NONE;
        }

        return OP_NONE;
    }

    /*
     * Direct: via branco.
     *   lighten = quadros até o branco a partir da origem
     *   darken  = quadros do branco até o destino
     *
     * Transições que só clareiam ou só escurecem a partir do branco
     * ficam no bloco 1 (alinhadas à direita); o bloco 2 só é usado
     * quando o pixel precisa das duas etapas (tons de cinza).
     */
    const uint16_t lighten =
        static_cast<uint16_t>(n - fromFrames);

    const uint16_t darken =
        static_cast<uint16_t>(n - toFrames);

    if (f < n) {
        if (lighten > 0) {
            return
                f >= n - lighten
                    ? OP_LIGHTEN
                    : OP_NONE;
        }

        return
            f >= n - darken
                ? OP_DARKEN
                : OP_NONE;
    }

    f = static_cast<uint16_t>(f - n);

    if (
        f < n &&
        lighten > 0
    ) {
        return
            f < darken
                ? OP_DARKEN
                : OP_NONE;
    }

    return OP_NONE;
}


uint16_t build(
    const Params& params,
    const PairSet* used,
    uint8_t* out,
    size_t capacity) {

    if (
        out == nullptr ||
        !fits(params)
    ) {
        return 0;
    }

    const uint16_t rawFrames =
        rawFrameCount(params);

    uint16_t phases = 0;

    for (
        uint16_t frame = 0;
        frame < rawFrames;
        ++frame
    ) {
        bool active = false;

        for (
            uint16_t pair = 0;
            pair < 256U && !active;
            ++pair
        ) {
            const uint8_t index =
                static_cast<uint8_t>(pair);

            if (
                used != nullptr &&
                !used->contains(index)
            ) {
                continue;
            }

            active =
                rawOp(
                    params,
                    frame,
                    static_cast<uint8_t>(index & 0x0FU),
                    static_cast<uint8_t>(index >> 4)) !=
                OP_NONE;
        }

        if (!active) {
            continue;
        }

        if (
            phases >= MAX_PHASES ||
            (static_cast<size_t>(phases) + 1U) * BYTES_PER_PHASE >
                capacity
        ) {
            return 0;
        }

        uint8_t* phase =
            out +
            static_cast<size_t>(phases) * BYTES_PER_PHASE;

        for (uint8_t to = 0; to < LEVELS; ++to) {
            for (uint8_t packed = 0; packed < 4; ++packed) {
                uint8_t value = 0;

                for (uint8_t j = 0; j < 4; ++j) {
                    const uint8_t from =
                        static_cast<uint8_t>(packed * 4U + j);

                    const uint8_t op =
                        rawOp(params, frame, from, to);

                    value = static_cast<uint8_t>(
                        value |
                        ((op & 0x03U) << (6U - 2U * j)));
                }

                phase[to * 4U + packed] = value;
            }
        }

        ++phases;
    }

    for (
        uint8_t i = 0;
        i < params.settleFrames;
        ++i
    ) {
        if (
            phases >= MAX_PHASES ||
            (static_cast<size_t>(phases) + 1U) * BYTES_PER_PHASE >
                capacity
        ) {
            return 0;
        }

        memset(
            out + static_cast<size_t>(phases) * BYTES_PER_PHASE,
            0,
            BYTES_PER_PHASE);

        ++phases;
    }

    return phases;
}


uint8_t opAt(
    const uint8_t* luts,
    uint16_t phase,
    uint8_t from,
    uint8_t to) {

    from &= 0x0FU;
    to &= 0x0FU;

    const uint8_t packed =
        luts[
            static_cast<size_t>(phase) * BYTES_PER_PHASE +
            static_cast<size_t>(to) * 4U +
            from / 4U];

    return
        static_cast<uint8_t>(
            (packed >> (6U - 2U * (from % 4U))) & 0x03U);
}

}  // namespace EpdWaveformBuilder
