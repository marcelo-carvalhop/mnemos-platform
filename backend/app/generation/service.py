"""Generation (§7). No FastAPI — the worker calls most of this (§4.2)."""

from __future__ import annotations

import secrets
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import and_, func, or_, select, update
from sqlalchemy.orm import Session

from app.contract import ErrorCode
from app.generation.text import constrain
from app.models import Card, Deck, GenerationJob, PendingCard
from app.quota import service as quota
from app.quota.service import QuotaExhausted, TooManyJobsInFlight

# §7.3 — the client shows the named stage, never a fabricated percentage.
STATUSES = ("queued", "reading", "generating", "ready", "failed")

SOURCE_TYPES = ("topic", "text", "pdf", "photo")


class UnknownDeck(Exception):
    """§5.5 — the target deck must belong to the requester."""


class JobNotFound(Exception):
    pass


@dataclass(frozen=True)
class GeneratedCards:
    """What the model returned, before `constrain` (§7.5)."""

    status: str  # ok | needs_specification
    cards: list[dict]
    reason: str = ""
    tokens_in: int = 0
    tokens_out: int = 0
    cache_read: int = 0
    cache_write: int = 0
    refused: bool = False
    refusal_category: str = ""


def enqueue(
    session: Session,
    user_id: str,
    *,
    source_type: str,
    target_deck_id: str,
    requested_count: int = 10,
    level: str = "intermediario",
    topic: str | None = None,
    upload_key: str | None = None,
    now: datetime | None = None,
) -> GenerationJob:
    """Reserves quota and enqueues in **one transaction** (§4.2).

    This atomicity is the reason the queue is Postgres. With quota here and the
    queue in Redis it is a distributed commit, and its failure mode is charging
    a user for a job that never ran.
    """
    now = now or datetime.now(timezone.utc)

    if source_type not in SOURCE_TYPES:
        raise ValueError(f"unknown source_type: {source_type}")

    deck = session.execute(
        select(Deck).where(Deck.id == target_deck_id, Deck.user_id == user_id)
    ).scalar_one_or_none()
    if deck is None:
        raise UnknownDeck(f"deck {target_deck_id} is not yours")

    job_id = secrets.token_hex(18)
    reservation_id = secrets.token_hex(18)

    # Raises QuotaExhausted / TooManyJobsInFlight before anything is written.
    quota.reserve(session, user_id, reservation_id=reservation_id, at=now)

    job = GenerationJob(
        id=job_id,
        user_id=user_id,
        source_type=source_type,
        status="queued",
        target_deck_id=target_deck_id,
        requested_count=requested_count,
        level=level,
        topic=topic,
        upload_key=upload_key,
        created_at=now,
        quota_reservation_id=reservation_id,
    )
    session.add(job)
    session.flush()
    return job


def claim_next(session: Session, *, now: datetime | None = None) -> GenerationJob | None:
    """Claims the oldest queued job with SKIP LOCKED (§4.2).

    Two workers polling at once take different rows instead of blocking on the
    same one, and a crash between claim and completion leaves the row visible
    again once the transaction rolls back.
    """
    now = now or datetime.now(timezone.utc)

    job = session.execute(
        select(GenerationJob)
        .where(GenerationJob.status == "queued")
        .order_by(GenerationJob.created_at)
        .limit(1)
        .with_for_update(skip_locked=True)
    ).scalar_one_or_none()

    if job is None:
        return None

    job.status = "reading"
    job.started_at = now
    session.flush()
    return job


def advance(session: Session, job_id: str, status: str) -> None:
    if status not in STATUSES:
        raise ValueError(f"unknown status: {status}")
    session.execute(
        update(GenerationJob).where(GenerationJob.id == job_id).values(status=status)
    )
    session.flush()


def complete(
    session: Session,
    job_id: str,
    result: GeneratedCards,
    *,
    now: datetime | None = None,
) -> list[PendingCard]:
    """Stages the cards and commits the quota (§7.6, §7.7, §7.8)."""
    now = now or datetime.now(timezone.utc)

    job = session.get(GenerationJob, job_id)
    if job is None:
        raise JobNotFound(job_id)

    job.tokens_in = result.tokens_in
    job.tokens_out = result.tokens_out
    job.cache_read_tokens = result.cache_read
    job.cache_write_tokens = result.cache_write

    # §10 — a refusal is HTTP 200 with stop_reason "refusal", not an error.
    # Nothing is billed before output, so nothing is charged.
    if result.refused:
        return _fail(
            session, job, ErrorCode.MODEL_REFUSED, result.refusal_category, now, refund=True
        )

    # §7.5 — the model declining a vague topic is a real answer, not a failure,
    # but it produced no cards, so the allowance is returned.
    if result.status == "needs_specification":
        return _fail(session, job, ErrorCode.TOPIC_TOO_VAGUE, result.reason, now, refund=True)

    constrained = constrain(result.cards)

    if not constrained.kept:
        return _fail(
            session, job, ErrorCode.MATERIAL_INSUFFICIENT, "no card survived", now, refund=True
        )

    pending = [
        PendingCard(
            id=secrets.token_hex(18),
            job_id=job.id,
            user_id=job.user_id,
            deck_id=job.target_deck_id,
            front=card["front"],
            back=card["back"],
            tags=card.get("tags", []),
            position=index,
            decision=None,
        )
        for index, card in enumerate(constrained.kept)
    ]
    session.add_all(pending)

    job.status = "ready"
    job.finished_at = now
    if job.quota_reservation_id:
        quota.commit(session, job.quota_reservation_id)
    session.flush()
    return pending


def fail(
    session: Session,
    job_id: str,
    error_code: str,
    detail: str = "",
    *,
    refund: bool = True,
    now: datetime | None = None,
) -> None:
    job = session.get(GenerationJob, job_id)
    if job is None:
        raise JobNotFound(job_id)
    _fail(session, job, error_code, detail, now or datetime.now(timezone.utc), refund=refund)


def _fail(
    session: Session,
    job: GenerationJob,
    error_code: str,
    detail: str,
    now: datetime,
    *,
    refund: bool,
) -> list:
    job.status = "failed"
    job.finished_at = now
    job.error_code = str(error_code)
    job.error_detail = detail or None

    # §7.7 — the allowance comes back whenever the failure is not the user
    # spending it. With one generation per lifetime, getting this wrong means
    # taking away the only one they had.
    if refund and job.quota_reservation_id:
        quota.release(session, job.quota_reservation_id)

    session.flush()
    return []


# ---------------------------------------------------------------------------
# The approval queue (§7.8)
# ---------------------------------------------------------------------------


def open_jobs(session: Session, user_id: str) -> list[tuple[GenerationJob, int]]:
    """Every generation that still owes this user something, newest first.

    Two kinds are open, and they are open for different reasons:

    * still running — queued, reading, generating;
    * ready with undecided cards — the worker is done, the human is not.

    `failed` is closed: the quota was released and there is nothing to return
    to. A `ready` job whose cards have all been judged is closed too, which is
    why the count is a join and not a status: nothing marks a queue as emptied,
    and adding a status for it would be a second fact that can disagree with
    the rows.
    """
    pending = (
        select(PendingCard.job_id, func.count().label("n"))
        .where(PendingCard.user_id == user_id, PendingCard.decision.is_(None))
        .group_by(PendingCard.job_id)
        .subquery()
    )

    rows = session.execute(
        select(GenerationJob, func.coalesce(pending.c.n, 0))
        .outerjoin(pending, pending.c.job_id == GenerationJob.id)
        .where(
            GenerationJob.user_id == user_id,
            or_(
                GenerationJob.status.in_(("queued", "reading", "generating")),
                and_(GenerationJob.status == "ready", pending.c.n > 0),
            ),
        )
        .order_by(GenerationJob.created_at.desc())
    ).all()

    return [(job, count) for job, count in rows]


def queue_for(session: Session, user_id: str, job_id: str) -> list[PendingCard]:
    return list(
        session.execute(
            select(PendingCard)
            .where(PendingCard.job_id == job_id, PendingCard.user_id == user_id)
            .order_by(PendingCard.position)
        ).scalars()
    )


def decide(
    session: Session,
    user_id: str,
    pending_id: str,
    decision: str | None,
    *,
    now: datetime | None = None,
) -> PendingCard:
    """Approve, discard, or undo (`decision=None`).

    Approval writes a real card **reusing the pending row's id**, which makes
    it idempotent by construction: a replayed push cannot produce a second
    card, and the ownership question — does the client create it or does the
    server — has one answer instead of a duplicate.
    """
    if decision not in (None, "approved", "discarded"):
        raise ValueError(f"unknown decision: {decision}")

    now = now or datetime.now(timezone.utc)
    card = session.execute(
        select(PendingCard).where(
            PendingCard.id == pending_id, PendingCard.user_id == user_id
        )
    ).scalar_one_or_none()
    if card is None:
        raise JobNotFound(pending_id)

    card.decision = decision
    card.decided_at = now if decision else None
    session.flush()
    return card


def approve_remaining(
    session: Session, user_id: str, job_id: str, *, now: datetime | None = None
) -> int:
    """§5.7's "aprovar todos os restantes" — one bulk update."""
    now = now or datetime.now(timezone.utc)
    result = session.execute(
        update(PendingCard)
        .where(
            PendingCard.job_id == job_id,
            PendingCard.user_id == user_id,
            PendingCard.decision.is_(None),
        )
        .values(decision="approved", decided_at=now)
        .returning(PendingCard.id)
    ).all()
    session.flush()
    return len(result)


def materialise(
    session: Session,
    user_id: str,
    job_id: str,
    *,
    device_id: str,
    now: datetime | None = None,
) -> int:
    """Turns approved pending rows into real cards.

    Called when the queue is closed. Idempotent because the card reuses the
    pending id, so re-running inserts nothing new.
    """
    now = now or datetime.now(timezone.utc)
    approved = session.execute(
        select(PendingCard).where(
            PendingCard.job_id == job_id,
            PendingCard.user_id == user_id,
            PendingCard.decision == "approved",
        )
    ).scalars().all()

    from app.sync import service as sync  # local import: avoids a cycle

    rows = []
    for pending in approved:
        if session.get(Card, pending.id) is not None:
            continue
        rows.append(
            {
                "id": pending.id,
                "deck_id": pending.deck_id,
                "front": pending.front,
                "back": pending.back,
                "tags": pending.tags,
                "updated_at": now,
                "device_id": device_id,
            }
        )

    if not rows:
        return 0

    sync.push(session, user_id, "cards", rows)
    return len(rows)


__all__ = [
    "GeneratedCards",
    "JobNotFound",
    "QuotaExhausted",
    "TooManyJobsInFlight",
    "UnknownDeck",
    "advance",
    "approve_remaining",
    "claim_next",
    "complete",
    "decide",
    "enqueue",
    "fail",
    "materialise",
    "queue_for",
]
