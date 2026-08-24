# GENERATED FROM shared/contract.yaml — DO NOT EDIT.
# Regenerate with: python shared/generate.py

from __future__ import annotations

from enum import IntEnum, StrEnum

CONTRACT_VERSION = 1

# §7.6 — counted in grapheme clusters over NFC-normalised text.
FRONT_MAX_GRAPHEMES = 120
BACK_MAX_GRAPHEMES = 240

# §4 — maturity is a query predicate, never a stored column.
MATURE_INTERVAL_DAYS = 21
DESIRED_RETENTION = 0.9
GRADUATION_MILESTONE_DAYS = (180, 365,)

# §5.7 — the day rolls over at 04:00 local, not midnight.
DEFAULT_DAY_CUTOFF_HOUR = 4

# §7.7 — one generation for the lifetime of the account, not per month.
FREE_GENERATIONS_LIFETIME = 1
MAX_JOBS_IN_FLIGHT = 2

# §7.3 — cap on the subject, or on pasted material. Without it the request body
# becomes the prompt, and a generation is billed by token.
TOPIC_MAX_CHARS = 20000

# §5.9 — alternative modes. Present on the server only so that a future
# server-side check has the same numbers; the modes themselves are on-device.
MULTIPLE_CHOICE_OPTIONS = 4
MULTIPLE_CHOICE_FAST_ANSWER_MS = 10000
LEECH_MIN_LAPSES = 4
SIMULADO_DEFAULT_QUESTIONS = 20
SIMULADO_DEFAULT_MINUTES = 20
TTS_ANSWER_PAUSE_MS = 3000


class Grade(IntEnum):
    """§5.2 — the wire value is the contract. Never renumber."""

    ERREI = 1
    DIFICIL = 2
    BOM = 3
    FACIL = 4


class ReviewSource(StrEnum):
    """§5.2 — a review row exists only for modes that feed the scheduler."""

    STANDARD = "standard"
    MULTIPLE_CHOICE = "multiple_choice"


class CardStatus(StrEnum):
    """§5.1"""

    ACTIVE = "active"
    SUSPENDED = "suspended"
    BURIED = "buried"


class ErrorCode(StrEnum):
    """§10 — machine-readable; the client maps these to copy.

    StrEnum, not `(str, Enum)`: the latter stringifies as "ErrorCode.MEMBER" on
    Python 3.11+, and that string reached the database. A code the client
    cannot map is the same as no code at all.
    """

    QUOTA_EXHAUSTED = "quota_exhausted"
    TOPIC_TOO_VAGUE = "topic_too_vague"
    MATERIAL_INSUFFICIENT = "material_insufficient"
    FILE_TOO_LARGE = "file_too_large"
    PAGE_LIMIT_EXCEEDED = "page_limit_exceeded"
    PHOTO_UNREADABLE = "photo_unreadable"
    MODEL_REFUSED = "model_refused"
    NETWORK_UNAVAILABLE = "network_unavailable"
    RESYNC_REQUIRED = "resync_required"
