"""Recorta a Noto Sans SC para os ideogramas que o terminal mostra.

A Geist não tem ideogramas; o baralho de mandarim mostra um caractere grande
na pergunta e na resposta. Em vez de empacotar os 17 MB da Noto Sans SC,
este script fixa o peso 400 e guarda só os ideogramas da tabela antiga
(tools/fonts/legacy/mnemos_fonts_1bpp.cpp), em tools/fonts/MnemosHanzi.ttf.

A Noto Sans SC é OFL 1.1 (tools/fonts/OFL-NotoSansSC.txt). O recorte é uma
versão modificada e por isso leva outro nome de família, "Mnemos Hanzi".

    uv run --no-project --python 3.12 --with fonttools==4.55.3 \
        python tools/fonts/subset_noto_sc.py caminho/NotoSansSC[wght].ttf

Fonte original: https://github.com/google/fonts/tree/main/ofl/notosanssc
"""

from __future__ import annotations

import pathlib
import re
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = pathlib.Path(__file__).resolve().parent
LEGACY = HERE / "legacy" / "mnemos_fonts_1bpp.cpp"
OUT = HERE / "MnemosHanzi.ttf"


def hanzi() -> list[int]:
    src = LEGACY.read_text(encoding="utf-8")
    block = src.split("GLYPHS_22[GLYPH_COUNT_22] PROGMEM = {", 1)[1].split("};", 1)[0]
    cps = {int(m) for m in re.findall(r"\{(\d+)U,", block)}
    return sorted(cp for cp in cps if 0x4E00 <= cp <= 0x9FFF)


def main() -> None:
    font = TTFont(sys.argv[1])
    font = instancer.instantiateVariableFont(font, {"wght": 400})

    options = subset.Options()
    options.layout_features = []
    options.name_IDs = ["*"]
    options.notdef_outline = True
    subsetter = subset.Subsetter(options)
    cps = hanzi()
    subsetter.populate(unicodes=cps)
    subsetter.subset(font)

    for record in font["name"].names:
        if record.nameID in (1, 4, 16):
            record.string = "Mnemos Hanzi"
        elif record.nameID == 6:
            record.string = "MnemosHanzi-Regular"
    font.save(OUT)
    print(f"{OUT.name}: {len(cps)} ideogramas, {OUT.stat().st_size} bytes")


if __name__ == "__main__":
    main()
