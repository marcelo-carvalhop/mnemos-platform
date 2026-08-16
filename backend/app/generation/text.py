"""The `constrain` stage (§7.6).

Structured outputs support neither `maxLength` nor `minLength`, so §5.4's hard
character limit **cannot** be enforced by the schema. It has to run here, after
the model returns.

Sharing the constant with the client is not enough — the counting function has
to match too. Dart's `String.length` counts UTF-16 code units and Python's
`len()` counts code points; for "ção" both return 3, but a decomposed combining
accent gives a different answer in each while the user sees no difference. The
result would be an editor that accepts text this stage drops.
"""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass

import regex

from app.contract import BACK_MAX_GRAPHEMES, FRONT_MAX_GRAPHEMES


def grapheme_length(text: str) -> int:
    """User-perceived characters. `\\X` is the grapheme-cluster escape.

    Matches Dart's `characters` package, verified on the shared fixture of
    composed and decomposed accents, emoji and ZWJ sequences.
    """
    return len(regex.findall(r"\X", text))


def normalise(text: str) -> str:
    """NFC, so two devices editing the same visible text produce equal rows.

    Normalisation never changes what [grapheme_length] returns — that is the
    whole reason grapheme clusters are the unit. It matters for storage and for
    the LWW comparison of §6.1, not for counting.
    """
    return unicodedata.normalize("NFC", text)


@dataclass(frozen=True)
class ConstrainResult:
    kept: list[dict]
    dropped: list[dict]

    @property
    def drop_rate(self) -> float:
        total = len(self.kept) + len(self.dropped)
        return len(self.dropped) / total if total else 0.0


def constrain(cards: list[dict]) -> ConstrainResult:
    """Drops oversized cards rather than truncating them.

    Truncation produces a card whose answer is cut mid-sentence, which is worse
    than one fewer card — and §2.2 means a human reviews the result anyway.

    The wave 0 spike measured zero violations in 108 generated cards, so this
    is expected to be a no-op in practice. It stays because a guarantee the
    schema cannot express needs somewhere to live, and because a stage that
    never fires costs nothing.
    """
    kept: list[dict] = []
    dropped: list[dict] = []

    for card in cards:
        front = normalise(card.get("front", ""))
        back = normalise(card.get("back", ""))

        if not front.strip() or not back.strip():
            dropped.append({**card, "reason": "empty"})
            continue

        front_len = grapheme_length(front)
        back_len = grapheme_length(back)

        if front_len > FRONT_MAX_GRAPHEMES or back_len > BACK_MAX_GRAPHEMES:
            dropped.append(
                {
                    **card,
                    "reason": "too_long",
                    "front_graphemes": front_len,
                    "back_graphemes": back_len,
                }
            )
            continue

        tags = [t.strip().lower() for t in (card.get("tags") or []) if t and t.strip()]
        kept.append({**card, "front": front, "back": back, "tags": tags[:3]})

    return ConstrainResult(kept=kept, dropped=dropped)
