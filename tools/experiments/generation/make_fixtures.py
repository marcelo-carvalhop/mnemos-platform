#!/usr/bin/env python3
"""Build synthetic fixtures for the generation spike.

Two of the spike's questions can be answered without material from the user:

  - a **text PDF** exercises the `document` content block;
  - a **scanned PDF** — the same text rendered to a bitmap and embedded, with
    no text layer at all — tests §7.1's claim that a scanned PDF needs no
    extraction stage because the model reads it as pixels.

A photo of handwritten notes cannot be synthesised honestly and stays a
human-supplied fixture.
"""

from __future__ import annotations

import pathlib

from fpdf import FPDF
from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE / "fixtures"

TEXT = """Revolucao Gloriosa (1688)

A Revolucao Gloriosa foi o processo pelo qual Jaime II da Inglaterra foi
deposto e substituido por Guilherme de Orange e Maria II. O episodio
consolidou a monarquia parlamentar inglesa.

Causas principais:
- O catolicismo de Jaime II e o temor de uma restauracao catolica.
- O nascimento de um herdeiro catolico em 1688, que ameacava perpetuar a
  dinastia.
- O conflito crescente entre a Coroa e o Parlamento sobre prerrogativas
  reais.

Consequencias:
- A Declaracao de Direitos (Bill of Rights) de 1689 limitou o poder real.
- O Parlamento passou a controlar a tributacao e o exercito permanente.
- Consolidou-se o principio de que o monarca reina, mas nao governa.

A revolucao foi chamada de "gloriosa" por ter ocorrido praticamente sem
derramamento de sangue na Inglaterra, ainda que tenha havido conflito
significativo na Irlanda e na Escocia.
"""


def make_text_pdf(path: pathlib.Path) -> None:
    """A normal PDF with a real text layer."""
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", size=11)
    for line in TEXT.splitlines():
        pdf.cell(0, 6, line, new_x="LMARGIN", new_y="NEXT")
    pdf.output(str(path))


def make_scanned_pdf(path: pathlib.Path) -> None:
    """A PDF whose pages are images — no text layer, like a real scan."""
    width, height = 1240, 1754  # ~A4 at 150 dpi
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)

    try:
        font = ImageFont.truetype("arial.ttf", 26)
    except OSError:
        font = ImageFont.load_default()

    y = 80
    for line in TEXT.splitlines():
        draw.text((90, y), line, fill=(15, 15, 15), font=font)
        y += 38

    # Slight rotation and a grey cast, so it is not a pristine render.
    image = image.rotate(0.7, expand=False, fillcolor="white")

    png = path.with_suffix(".page.png")
    image.save(png, "PNG")

    pdf = FPDF(unit="pt", format=(595, 842))
    pdf.add_page()
    pdf.image(str(png), x=0, y=0, w=595, h=842)
    pdf.output(str(path))
    png.unlink()


def main() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    make_text_pdf(FIXTURES / "texto.pdf")
    make_scanned_pdf(FIXTURES / "escaneado.pdf")
    for f in sorted(FIXTURES.glob("*.pdf")):
        print(f"{f.name}: {f.stat().st_size / 1024:.1f} KB")


if __name__ == "__main__":
    main()
