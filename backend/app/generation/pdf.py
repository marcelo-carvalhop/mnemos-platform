"""Reading and cutting a PDF before it goes to the model.

Two uses. The briefing (`briefing.py`) reads only the first pages and the
outline, so asking "what matters to you here?" costs a fraction of reading the
whole file. The job (`runner.py`) sends only the pages the person chose: a
150-page handout costs ~150 pages of tokens on every generation, and the cards
it produces are about everything instead of what the person needs.

Pages are 1-based and inclusive everywhere, because that is how people and
the outline count them.
"""

from __future__ import annotations

import io
from dataclasses import dataclass

from pypdf import PdfReader, PdfWriter
from pypdf.errors import PdfReadError

# What the briefing reads: enough for a cover, a table of contents and the
# first chapter of most handouts.
PREVIEW_PAGES = 10

# The outline can run to hundreds of entries in a law code; the model needs
# the shape, not every article.
MAX_OUTLINE_ENTRIES = 60

# What one generation reads. A whole law code would cost hundreds of pages of
# tokens for a dozen cards; past this the person chooses the parts first.
MAX_GENERATION_PAGES = 100


class PdfUnreadable(Exception):
    """Encrypted, corrupt or not a PDF. The message is safe to log."""


class TooManyPages(Exception):
    """More than `MAX_GENERATION_PAGES` would go to the model."""


@dataclass(frozen=True)
class PdfInfo:
    page_count: int
    # (title, first page, depth) in reading order, depth 0 for chapters.
    outline: tuple[tuple[str, int, int], ...] = ()


def _reader(data: bytes) -> PdfReader:
    try:
        reader = PdfReader(io.BytesIO(data))
        if reader.is_encrypted:
            # An empty password opens most "protected" PDFs, which only
            # restrict printing or copying.
            if not reader.decrypt(""):
                raise PdfUnreadable("encrypted")
        return reader
    except PdfReadError as exc:
        raise PdfUnreadable(f"unreadable: {exc}") from exc
    except (ValueError, KeyError, TypeError) as exc:
        raise PdfUnreadable(f"malformed: {type(exc).__name__}") from exc


def inspect(data: bytes) -> PdfInfo:
    reader = _reader(data)
    try:
        count = len(reader.pages)
    except Exception as exc:  # noqa: BLE001 — pypdf raises a zoo on bad files
        raise PdfUnreadable(f"no pages: {type(exc).__name__}") from exc

    entries: list[tuple[str, int, int]] = []

    def walk(items: list, depth: int) -> None:
        for item in items:
            if len(entries) >= MAX_OUTLINE_ENTRIES:
                return
            if isinstance(item, list):
                walk(item, depth + 1)
                continue
            try:
                page = reader.get_destination_page_number(item) + 1
            except Exception:  # noqa: BLE001 — broken destinations are common
                continue
            title = " ".join(str(getattr(item, "title", "") or "").split())
            if title and 1 <= page <= count:
                entries.append((title[:120], page, depth))

    try:
        walk(reader.outline, 0)
    except Exception:  # noqa: BLE001 — an outline is a bonus, never a blocker
        entries = []

    return PdfInfo(page_count=count, outline=tuple(entries))


def normalise_ranges(
    ranges: list[tuple[int, int]] | None, page_count: int
) -> list[tuple[int, int]]:
    """Clamped, ordered and merged; empty means "the whole document"."""
    clean = []
    for start, end in ranges or []:
        start, end = max(1, start), min(page_count, end)
        if start <= end:
            clean.append((start, end))
    clean.sort()
    merged: list[tuple[int, int]] = []
    for start, end in clean:
        if merged and start <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def cut(data: bytes, ranges: list[tuple[int, int]]) -> bytes:
    """A new PDF with only the pages in `ranges` (1-based, inclusive)."""
    reader = _reader(data)
    writer = PdfWriter()
    for start, end in normalise_ranges(ranges, len(reader.pages)):
        for index in range(start - 1, end):
            writer.add_page(reader.pages[index])
    if len(writer.pages) == 0:
        raise PdfUnreadable("no pages in the chosen ranges")
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()


def describe_ranges(ranges: list[tuple[int, int]]) -> str:
    """ "p. 3–10, 15" — for the prompt and for the screens."""
    parts = [f"{a}" if a == b else f"{a}–{b}" for a, b in ranges]
    return "p. " + ", ".join(parts)
