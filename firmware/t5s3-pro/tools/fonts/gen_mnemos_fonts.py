"""Gera src/mnemos_font_data.h: as fontes do terminal em 16 tons de cinza.

As famílias são as do design system "Marinho" (docs/design/DESIGN-SYSTEM.md):
Geist na interface, Geist Mono nas sobrancelhas e Literata só no conteúdo do
card. Os arquivos .ttf são os mesmos que o app empacota
(app/mobile/assets/fonts, todos OFL).

Cada papel (MnemosFontRole) vira uma tabela de glifos com bitmap de 4 bits
por pixel — a tela tem 16 tons, e a borda suavizada é o que faz a Geist
parecer a Geist. A Geist não cobre ideogramas chineses nem as vogais com tom
do pinyin; esses glifos continuam vindo das fontes de 1 bit antigas
(tools/fonts/legacy/mnemos_fonts_1bpp.cpp), como fallback.

    uv run --no-project --python 3.12 --with pillow==11.1.0 --with fonttools==4.55.3 \
        python tools/fonts/gen_mnemos_fonts.py

Rode da pasta firmware/t5s3-pro. A saída é determinística.
"""

from __future__ import annotations

import pathlib
import re
from dataclasses import dataclass

from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
FIRMWARE = HERE.parent.parent
FONTS = FIRMWARE.parent.parent / "app" / "mobile" / "assets" / "fonts"
LEGACY = HERE / "legacy" / "mnemos_fonts_1bpp.cpp"
OUT = FIRMWARE / "src" / "mnemos_font_data.h"

ASCII = list(range(0x20, 0x7F))


@dataclass(frozen=True)
class Role:
    name: str  # o enumerador em MnemosFontRole
    file: str
    size: int  # em pixels por em
    tracking: float = 0.0  # em em; somado ao avanço de cada glifo
    charset: str = "full"  # "full" = o conjunto das fontes antigas; "ascii"
    fallback: int = 18  # tamanho da fonte antiga para o que a família não tem


# A ordem é a do enum em include/mnemos_fonts.h.
#
# Os três primeiros mantêm a altura de maiúscula das fontes de 1 bit (11, 14
# e 17 px): as telas que ainda os usam continuam cabendo onde cabiam.
ROLES = [
    Role("Meta14", "Geist-Regular.ttf", 16, fallback=14),
    Role("Body18", "Geist-Regular.ttf", 20, fallback=18),
    Role("Title22", "Geist-Medium.ttf", 24, fallback=22),
    # Os papéis do Marinho. Um px CSS do celular vale ~1,4 px desta tela
    # (4,7" a 234 ppp contra um iPhone de 390 px CSS): o corpo de 15 px CSS
    # vira 21 px aqui, com o mesmo tamanho físico.
    Role("Eyebrow", "GeistMono-Medium.ttf", 17, tracking=0.10, fallback=14),
    Role("Small", "Geist-Regular.ttf", 18, fallback=14),
    Role("Body", "Geist-Regular.ttf", 21, fallback=18),
    Role("Strong", "Geist-SemiBold.ttf", 21, fallback=18),
    Role("Heading", "Geist-SemiBold.ttf", 26, tracking=-0.01, fallback=22),
    Role("Title", "Geist-Medium.ttf", 44, tracking=-0.03, fallback=22),
    Role("Figure", "Geist-Regular.ttf", 50, tracking=-0.03, charset="ascii", fallback=22),
    Role("Display", "Geist-Regular.ttf", 96, tracking=-0.03, charset="ascii", fallback=22),
    Role("Card", "Literata-Regular.ttf", 32, fallback=22),
    Role("CardSmall", "Literata-Regular.ttf", 25, fallback=22),
    # O ideograma do baralho de mandarim: recorte da Noto Sans SC
    # (tools/fonts/subset_noto_sc.py), só os caracteres que os cards usam.
    Role("Hanzi", "MnemosHanzi.ttf", 140, charset="hanzi", fallback=22),
]


def legacy_tables() -> dict[int, dict]:
    """As tabelas de 1 bit, por tamanho: {cp: (w, h, xo, yo, adv, bits)}."""
    src = LEGACY.read_text(encoding="utf-8")
    tables = {}
    for size in (14, 18, 22):
        glyph_block = src.split(f"GLYPHS_{size}[GLYPH_COUNT_{size}] PROGMEM = {{", 1)[1]
        glyph_block = glyph_block.split("};", 1)[0]
        bitmap_block = src.split(f"BITMAP_{size}[BITMAP_BYTES_{size}] PROGMEM = {{", 1)[1]
        bitmap_block = bitmap_block.split("};", 1)[0]
        bitmap = bytes(int(v, 16) for v in re.findall(r"0x[0-9A-Fa-f]{2}", bitmap_block))
        table = {}
        for row in re.findall(r"\{([^}]*)\}", glyph_block):
            cp, off, w, h, xo, yo, adv = (int(v.rstrip("U")) for v in row.split(","))
            bits = [
                (bitmap[off + i // 8] >> (7 - i % 8)) & 1 for i in range(w * h)
            ]
            table[cp] = (w, h, xo, yo, adv, bits)
        tables[size] = table
    return tables


def render(font: ImageFont.FreeTypeFont, ch: str, tracking_px: float):
    """(w, h, xo, yo, adv, níveis 0..15) de um glifo, origem na linha de base."""
    advance = round(font.getlength(ch) + tracking_px)
    left, top, right, bottom = font.getbbox(ch, anchor="ls")
    w, h = right - left, bottom - top
    if w <= 0 or h <= 0:
        return (0, 0, 0, 0, max(advance, 0), [])
    img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(img).text((-left, -top), ch, font=font, fill=255, anchor="ls")
    levels = [round(v * 15 / 255) for v in img.getdata()]
    # Corta linhas e colunas que ficaram vazias depois da quantização.
    rows = [levels[y * w : (y + 1) * w] for y in range(h)]
    while rows and not any(rows[0]):
        rows.pop(0)
        top += 1
    while rows and not any(rows[-1]):
        rows.pop()
    if not rows:
        return (0, 0, 0, 0, max(advance, 0), [])
    cols = list(zip(*rows))
    first = next(i for i, c in enumerate(cols) if any(c))
    last = len(cols) - next(i for i, c in enumerate(reversed(cols)) if any(c))
    rows = [r[first:last] for r in rows]
    left += first
    w, h = last - first, len(rows)
    return (w, h, left, top, max(advance, 0), [v for r in rows for v in r])


def pack4(levels: list[int]) -> bytes:
    out = bytearray()
    for i in range(0, len(levels), 2):
        hi = levels[i]
        lo = levels[i + 1] if i + 1 < len(levels) else 0
        out.append((hi << 4) | lo)
    return bytes(out)


def pack1(bits: list[int]) -> bytes:
    out = bytearray()
    for i in range(0, len(bits), 8):
        byte = 0
        for j, b in enumerate(bits[i : i + 8]):
            byte |= b << (7 - j)
        out.append(byte)
    return bytes(out)


def c_bytes(data: bytes) -> str:
    lines = []
    for i in range(0, len(data), 16):
        lines.append("    " + ", ".join(f"0x{b:02X}" for b in data[i : i + 16]) + ",")
    return "\n".join(lines) or "    0x00,"


def check(value: int, lo: int, hi: int, what: str) -> int:
    if not lo <= value <= hi:
        raise SystemExit(f"{what} fora do intervalo: {value}")
    return value


def table(prefix: str, glyphs: list[tuple]) -> tuple[str, int]:
    """Emite GLYPHS_<prefix> e BITMAP_<prefix>; devolve (código, bytes)."""
    bitmap = bytearray()
    rows = []
    for cp, (w, h, xo, yo, adv, packed) in glyphs:
        rows.append(
            f"    {{{cp}U, {len(bitmap)}U, {check(w, 0, 255, 'w')}, {check(h, 0, 255, 'h')}, "
            f"{check(xo, -128, 127, 'xo')}, {check(yo, -128, 127, 'yo')}, {check(adv, 0, 255, 'adv')}}},"
        )
        bitmap += packed
    code = (
        f"constexpr uint16_t GLYPH_COUNT_{prefix} = {len(glyphs)};\n"
        f"static const MnemosFontGlyph GLYPHS_{prefix}[GLYPH_COUNT_{prefix}] PROGMEM = {{\n"
        + "\n".join(rows)
        + "\n};\n\n"
        f"static const uint8_t BITMAP_{prefix}[{max(len(bitmap), 1)}] PROGMEM = {{\n"
        + c_bytes(bytes(bitmap))
        + "\n};\n"
    )
    return code, len(bitmap)


def main() -> None:
    legacy = legacy_tables()
    full = sorted(legacy[18])

    parts = []
    views = []
    total = 0
    fallback_needed: dict[int, set[int]] = {14: set(), 18: set(), 22: set()}

    for role in ROLES:
        path = HERE / role.file if (HERE / role.file).exists() else FONTS / role.file
        font = ImageFont.truetype(str(path), role.size, layout_engine=ImageFont.Layout.BASIC)
        cmap = set(_cmap(path))
        if role.charset == "ascii":
            wanted = ASCII
        elif role.charset == "hanzi":
            wanted = [cp for cp in full if 0x4E00 <= cp <= 0x9FFF]
        else:
            wanted = full
        glyphs = []
        for cp in wanted:
            if cp != 0x20 and cp not in cmap:
                fallback_needed[role.fallback].add(cp)
                continue
            w, h, xo, yo, adv, levels = render(font, chr(cp), role.tracking * role.size)
            glyphs.append((cp, (w, h, xo, yo, adv, pack4(levels))))
        code, size = table(role.name, glyphs)
        parts.append(f"// {role.name}: {role.file} {role.size} px, {len(glyphs)} glifos, {size} bytes\n" + code)
        views.append((role, len(glyphs)))
        total += size

    for size, cps in fallback_needed.items():
        glyphs = []
        for cp in sorted(cps):
            if cp not in legacy[size]:
                continue
            w, h, xo, yo, adv, bits = legacy[size][cp]
            glyphs.append((cp, (w, h, xo, yo, adv, pack1(bits))))
        code, nbytes = table(f"FALLBACK_{size}", glyphs)
        parts.append(f"// Fallback de 1 bit ({size}): o que a família não tem\n" + code)
        total += nbytes

    cases = []
    for role, _ in views:
        cases.append(
            f"        case MnemosFontRole::{role.name}:\n"
            f"            return {{GLYPHS_{role.name}, BITMAP_{role.name}, GLYPH_COUNT_{role.name}, "
            f"GLYPHS_FALLBACK_{role.fallback}, BITMAP_FALLBACK_{role.fallback}, GLYPH_COUNT_FALLBACK_{role.fallback}}};"
        )

    header = (
        "// Gerado por tools/fonts/gen_mnemos_fonts.py. Não edite à mão.\n"
        f"// {total} bytes de bitmap.\n"
        "#pragma once\n\n"
        + "\n".join(parts)
        + "\nstatic FontView fontViewFor(MnemosFontRole role) {\n"
        "    switch (role) {\n"
        + "\n".join(cases)
        + "\n        default:\n"
        "            return fontViewFor(MnemosFontRole::Body18);\n"
        "    }\n"
        "}\n"
    )
    OUT.write_text(header, encoding="utf-8", newline="\n")
    print(f"{OUT.relative_to(FIRMWARE)}: {total} bytes de bitmap")


def _cmap(path: pathlib.Path):
    from fontTools.ttLib import TTFont

    return TTFont(str(path)).getBestCmap().keys()


if __name__ == "__main__":
    main()
