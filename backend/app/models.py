"""Server tables (§5.5).

Every row carries `user_id`, because ownership is enforced server-side: ids are
client-generated (§5.7), so an id proves identity and never authorisation.

Every synced row also carries `server_seq` — the pull cursor of §6.2, assigned
by the server, never by a device clock.
"""

from datetime import date, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base

# Client-generated UUIDv7, stored as text so SQLite-backed tests and Postgres
# agree on representation.
_ID = String(36)


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    email: Mapped[str | None] = mapped_column(String(320), unique=True, nullable=True)

    # Null during the anonymous period (§8.1): the row is a real user from
    # first launch, it simply has no way to sign in yet.
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class UserSyncState(Base):
    """The per-user sequence allocator behind `server_seq` (§6.2).

    A global Postgres sequence would be monotonic but not commit-ordered: a
    transaction that draws a low value and commits late is invisible to a
    device that already pulled past it — the exact hole §6.2 describes for
    timestamps. A per-user counter taken under `FOR UPDATE` serialises one
    user's pushes, which costs nothing for a single-user product and makes the
    cursor gap-free and commit-safe.
    """

    __tablename__ = "user_sync_state"

    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), primary_key=True)
    last_seq: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)


class Deck(Base):
    __tablename__ = "decks"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), nullable=False)

    parent_id: Mapped[str | None] = mapped_column(_ID, nullable=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Reserved and unused in v1; they exist so shared decks (§7) do not force a
    # migration. `version` gets semantics when shared decks do.
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    author: Mapped[str | None] = mapped_column(String(200), nullable=True)
    license: Mapped[str | None] = mapped_column(String(100), nullable=True)
    origin: Mapped[str] = mapped_column(String(20), nullable=False, default="own")
    source_deck_id: Mapped[str | None] = mapped_column(_ID, nullable=True)

    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    # Written by the client: it is the LWW criterion (§6.2).
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    device_id: Mapped[str] = mapped_column(_ID, nullable=False)
    server_seq: Mapped[int] = mapped_column(BigInteger, nullable=False)

    __table_args__ = (Index("ix_decks_user_seq", "user_id", "server_seq"),)


class Card(Base):
    __tablename__ = "cards"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), nullable=False)
    deck_id: Mapped[str] = mapped_column(_ID, nullable=False)

    front: Mapped[str] = mapped_column(Text, nullable=False)
    back: Mapped[str] = mapped_column(Text, nullable=False)

    # A value of the card, not a join table (§5.1): a join table has nowhere to
    # put a tombstone, so a tag removed offline reappears on sync.
    tags: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)

    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    device_id: Mapped[str] = mapped_column(_ID, nullable=False)
    server_seq: Mapped[int] = mapped_column(BigInteger, nullable=False)

    __table_args__ = (
        Index("ix_cards_user_seq", "user_id", "server_seq"),
        Index("ix_cards_deck", "deck_id"),
    )


class CardFlags(Base):
    """Volatile per-card state, split from `cards` on purpose (§5.1).

    Row-level LWW loses concurrent edits to different fields of one row:
    burying on the phone while fixing a typo on the tablet would discard one.
    `buried_until` also expires in 24 hours, so keeping it here stops a trivial
    daily write from competing with real text edits.
    """

    __tablename__ = "card_flags"

    card_id: Mapped[str] = mapped_column(_ID, primary_key=True)
    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), nullable=False)

    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    buried_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    device_id: Mapped[str] = mapped_column(_ID, nullable=False)
    server_seq: Mapped[int] = mapped_column(BigInteger, nullable=False)

    __table_args__ = (Index("ix_card_flags_user_seq", "user_id", "server_seq"),)


class Review(Base):
    """Append-only (§5.2). No UPDATE, no DELETE — enforced by trigger."""

    __tablename__ = "reviews"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), nullable=False)
    card_id: Mapped[str] = mapped_column(_ID, nullable=False)

    reviewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    grade: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    source: Mapped[str] = mapped_column(String(20), nullable=False)
    elapsed_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)

    device_id: Mapped[str] = mapped_column(_ID, nullable=False)
    server_seq: Mapped[int] = mapped_column(BigInteger, nullable=False)

    # Written once, advisory, never authoritative (§5.2): card_state always
    # comes from replay, because a review written under different parameters
    # can disagree with another device's replay.
    interval_days_after: Mapped[int | None] = mapped_column(Integer, nullable=True)
    stability_after: Mapped[float | None] = mapped_column(Float, nullable=True)
    difficulty_after: Mapped[float | None] = mapped_column(Float, nullable=True)
    scheduler_version: Mapped[int | None] = mapped_column(Integer, nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(40), nullable=True)

    __table_args__ = (
        Index("ix_reviews_user_seq", "user_id", "server_seq"),
        Index("ix_reviews_card", "card_id", "reviewed_at", "id"),
        Index("ix_reviews_user_reviewed", "user_id", "reviewed_at"),
    )


class ProgressReset(Base):
    """§5.10 — resets the schedule without deleting history (§3)."""

    __tablename__ = "progress_resets"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), nullable=False)
    card_id: Mapped[str] = mapped_column(_ID, nullable=False)
    reset_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    device_id: Mapped[str] = mapped_column(_ID, nullable=False)
    server_seq: Mapped[int] = mapped_column(BigInteger, nullable=False)

    __table_args__ = (Index("ix_progress_resets_user_seq", "user_id", "server_seq"),)


class GoalHistory(Base):
    """§9 — records the change, not a daily snapshot.

    The streak needs the goal in force on a past day; a setting only ever holds
    today's value. Append-only, so it merges by union like the review log and
    survives a reinstall.
    """

    __tablename__ = "goal_history"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), nullable=False)
    effective_from_local_date: Mapped[date] = mapped_column(Date, nullable=False)
    daily_goal: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    device_id: Mapped[str] = mapped_column(_ID, nullable=False)
    server_seq: Mapped[int] = mapped_column(BigInteger, nullable=False)

    __table_args__ = (Index("ix_goal_history_user_seq", "user_id", "server_seq"),)


class UserSetting(Base):
    """Synced settings (§5.4).

    `desired_retention` and the FSRS vector live here because they are inputs
    to the interval formula: device-local, they make two devices compute
    different due dates from identical histories (§3.1). `daily_goal` is
    deliberately absent — it lives in goal_history.
    """

    __tablename__ = "user_settings"

    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), primary_key=True)
    key: Mapped[str] = mapped_column(String(60), primary_key=True)
    value: Mapped[str] = mapped_column(Text, nullable=False)

    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    device_id: Mapped[str] = mapped_column(_ID, nullable=False)
    server_seq: Mapped[int] = mapped_column(BigInteger, nullable=False)

    __table_args__ = (Index("ix_user_settings_user_seq", "user_id", "server_seq"),)


class Device(Base):
    """§8.1 — quota attaches to a device before an account exists.

    `attested` records whether App Attest / Play Integrity vouched for this
    install. With the free tier at one generation for the lifetime of the
    account (§7.7.1), a reinstall doubles everything the user was given, so
    attestation is required in v1 rather than held in reserve.
    """

    __tablename__ = "devices"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    user_id: Mapped[str | None] = mapped_column(_ID, ForeignKey("users.id"), nullable=True)
    platform: Mapped[str] = mapped_column(String(20), nullable=False)
    attested: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    # iOS only: SHA256 of the attested public key, unique across devices so
    # one key cannot register two installs. Null on Android, where Play
    # Integrity has no per-device key to remember.
    attest_key_id: Mapped[str | None] = mapped_column(String(64), nullable=True, unique=True)

    # Survives account deletion (§8.4 against §8.1). The free tier is one
    # generation for the lifetime of an *account*, and deleting the account is
    # a way to get a new one — the same attack a reinstall is, with an extra
    # step. So the device row outlives the user and keeps exactly one fact:
    # that its free allowance was already spent. No name, no email, no study
    # data; a random client-generated id and a boolean.
    free_grant_spent: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class TerminalCredential(Base):
    """Opaque, terminal-scoped credential used by dedicated Mnemos hardware.

    The phone/account bearer token is never copied to the terminal. Re-registering
    a terminal rotates this secret, so a lost device can be revoked independently.
    """

    __tablename__ = "terminal_credentials"

    device_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    model: Mapped[str] = mapped_column(String(80), nullable=False, default="Mnemos Terminal")
    firmware: Mapped[str] = mapped_column(String(40), nullable=False, default="unknown")
    deck_ids: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    revoked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    __table_args__ = (Index("ix_terminal_credentials_user", "user_id"),)


class QuotaUsage(Base):
    """§7.7 — allowance per (user, period).

    `period_key` is `lifetime` for the free tier and `YYYY-MM` for paid plans,
    so "a period that never ends" reuses one code path instead of forking the
    reservation logic (§7.7.1).
    """

    __tablename__ = "quota_usage"

    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), primary_key=True)
    period_key: Mapped[str] = mapped_column(String(20), primary_key=True)

    used: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    reserved: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    limit_count: Mapped[int] = mapped_column(Integer, nullable=False)


class QuotaReservation(Base):
    """An allowance claim held between enqueue and the staging of cards.

    `expires_at` exists because a worker that dies in between would otherwise
    leak the reservation forever, silently costing the user quota they never
    spent (§7.7).
    """

    __tablename__ = "quota_reservations"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), nullable=False)
    period_key: Mapped[str] = mapped_column(String(20), nullable=False)
    amount: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    committed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    __table_args__ = (Index("ix_quota_reservations_user", "user_id", "committed", "expires_at"),)


class RefreshToken(Base):
    """§8.2 — stored hashed, rotated on use, with reuse detection.

    `family_id` chains every token descended from one login. Presenting an
    already-rotated token means either a leak or a blind retry; we cannot tell
    which, so the whole family is revoked.
    """

    __tablename__ = "refresh_tokens"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), nullable=False)
    device_id: Mapped[str] = mapped_column(_ID, nullable=False)
    family_id: Mapped[str] = mapped_column(String(64), nullable=False)

    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)

    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    __table_args__ = (Index("ix_refresh_tokens_family", "family_id"),)


class GenerationJob(Base):
    """§7.3 — one row per generation, on the queue it is also claimed from.

    The queue is this table, claimed with SELECT ... FOR UPDATE SKIP LOCKED
    (§4.2). Redis would put the quota reservation and the enqueue in two
    systems, and the failure mode of that distributed commit is charging a user
    for a job that never ran.
    """

    __tablename__ = "generation_jobs"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), nullable=False)

    source_type: Mapped[str] = mapped_column(String(20), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="queued")

    target_deck_id: Mapped[str] = mapped_column(_ID, nullable=False)
    requested_count: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    level: Mapped[str] = mapped_column(String(20), nullable=False, default="intermediario")

    topic: Mapped[str | None] = mapped_column(Text, nullable=True)
    upload_key: Mapped[str | None] = mapped_column(String(255), nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    error_code: Mapped[str | None] = mapped_column(String(40), nullable=True)
    error_detail: Mapped[str | None] = mapped_column(Text, nullable=True)

    # The reservation this job holds, so a failure can release exactly it.
    quota_reservation_id: Mapped[str | None] = mapped_column(_ID, nullable=True)

    # §7.7 — recorded per job even though v1 enforces by count. A whiteboard
    # photo can cost ten times a topic prompt, and without the real figures
    # repricing is guesswork plus a migration.
    tokens_in: Mapped[int | None] = mapped_column(Integer, nullable=True)
    tokens_out: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # Kept apart from tokens_in because they are not the same money: a cache
    # read bills at 0.1x and a cache write at 1.25x (§7.4). Folding them
    # together would make the recorded cost of a job wrong in both directions.
    cache_read_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cache_write_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)

    __table_args__ = (
        Index("ix_generation_jobs_queue", "status", "created_at"),
        Index("ix_generation_jobs_user", "user_id", "created_at"),
    )


class PendingCard(Base):
    """The approval queue (§7.8).

    `decision` is a column rather than a deletion, which buys §5.7's mandatory
    undo, the "7 de 24" counter and resume-after-abandon for free.
    """

    __tablename__ = "pending_cards"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    job_id: Mapped[str] = mapped_column(_ID, ForeignKey("generation_jobs.id"), nullable=False)
    user_id: Mapped[str] = mapped_column(_ID, ForeignKey("users.id"), nullable=False)
    deck_id: Mapped[str] = mapped_column(_ID, nullable=False)

    front: Mapped[str] = mapped_column(Text, nullable=False)
    back: Mapped[str] = mapped_column(Text, nullable=False)
    tags: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)

    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    # null | approved | discarded
    decision: Mapped[str | None] = mapped_column(String(20), nullable=True)
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    __table_args__ = (Index("ix_pending_cards_job", "job_id", "position"),)


class AttestationChallenge(Base):
    """A single-use nonce for §8.1.

    Without one, an attestation captured once is a permanent credential:
    replaying it mints a fresh anonymous account, and with the free tier at one
    generation per lifetime that is the entire hole attestation exists to
    close. Rows are deleted when spent, so there is no state in which a
    challenge is both used and present.
    """

    __tablename__ = "attestation_challenges"

    nonce: Mapped[str] = mapped_column(String(64), primary_key=True)
    device_id: Mapped[str] = mapped_column(_ID, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
