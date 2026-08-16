"""Quota (§7.7, §7.7.1). No FastAPI here — the worker calls this too (§4.2).

The free tier is **one generation for the lifetime of the account**, modelled
as a period that never ends. Paid plans use a monthly `period_key`, so both
run through one code path instead of two.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select, text, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.contract import FREE_GENERATIONS_LIFETIME, MAX_JOBS_IN_FLIGHT
from app.models import QuotaReservation, QuotaUsage

LIFETIME = "lifetime"

# §7.7 — a worker that dies between enqueue and start would otherwise leak the
# reservation forever, silently costing the user quota they never spent.
RESERVATION_TTL = timedelta(minutes=30)


class QuotaExhausted(Exception):
    """No allowance left (§5.13). Blocks generation only."""


class TooManyJobsInFlight(Exception):
    """§7.7 — so a whole allowance cannot be queued at once."""


@dataclass(frozen=True)
class Reservation:
    id: str
    period_key: str
    amount: int


def period_key_for(plan: str, at: datetime, timezone_name: str) -> str:
    """`lifetime` for the free tier; `YYYY-MM` in the user's timezone for paid.

    The month boundary is local, not UTC (§7.7): a user in São Paulo whose
    allowance reset at 21:00 on the last day of the month would reasonably
    call that a bug.
    """
    if plan == "free":
        return LIFETIME
    local = at.astimezone(ZoneInfo(timezone_name))
    return f"{local.year:04d}-{local.month:02d}"


def _ensure_row(session: Session, user_id: str, period_key: str, limit_count: int) -> None:
    session.execute(
        pg_insert(QuotaUsage)
        .values(
            user_id=user_id,
            period_key=period_key,
            used=0,
            reserved=0,
            limit_count=limit_count,
        )
        .on_conflict_do_nothing(index_elements=("user_id", "period_key"))
    )
    session.flush()


def mark_lifetime_spent(session: Session, user_id: str) -> None:
    """Starts an account with its free allowance already used (§8.4).

    For a device that spent its generation under a previous account. Written
    as a used quota row rather than as a flag on the user, so every path that
    already asks "how much is left" gets the right answer without knowing why.
    """
    _ensure_row(session, user_id, "lifetime", FREE_GENERATIONS_LIFETIME)
    session.execute(
        update(QuotaUsage)
        .where(QuotaUsage.user_id == user_id, QuotaUsage.period_key == "lifetime")
        .values(used=FREE_GENERATIONS_LIFETIME)
    )
    session.flush()


def reserve(
    session: Session,
    user_id: str,
    *,
    reservation_id: str,
    plan: str = "free",
    amount: int = 1,
    at: datetime | None = None,
    timezone_name: str = "America/Sao_Paulo",
    limit_count: int | None = None,
) -> Reservation:
    """Claims allowance before the model call. One statement, not read-then-write.

    Two simultaneous generations would otherwise both read the old total and
    both pass the limit. The guard lives in the WHERE clause, so the database
    decides.
    """
    at = at or datetime.now(timezone.utc)
    period_key = period_key_for(plan, at, timezone_name)
    limit_count = FREE_GENERATIONS_LIFETIME if limit_count is None else limit_count

    _ensure_row(session, user_id, period_key, limit_count)
    sweep_expired(session, user_id, at=at)

    in_flight = session.execute(
        select(QuotaReservation)
        .where(
            QuotaReservation.user_id == user_id,
            QuotaReservation.committed.is_(False),
            QuotaReservation.expires_at > at,
        )
    ).scalars().all()
    if len(in_flight) >= MAX_JOBS_IN_FLIGHT:
        raise TooManyJobsInFlight(f"at most {MAX_JOBS_IN_FLIGHT} jobs in flight")

    claimed = session.execute(
        update(QuotaUsage)
        .where(
            QuotaUsage.user_id == user_id,
            QuotaUsage.period_key == period_key,
            QuotaUsage.used + QuotaUsage.reserved + amount <= QuotaUsage.limit_count,
        )
        .values(reserved=QuotaUsage.reserved + amount)
        .returning(QuotaUsage.reserved)
    ).first()

    if claimed is None:
        raise QuotaExhausted(f"no generations left in period {period_key}")

    session.add(
        QuotaReservation(
            id=reservation_id,
            user_id=user_id,
            period_key=period_key,
            amount=amount,
            expires_at=at + RESERVATION_TTL,
            committed=False,
        )
    )
    session.flush()
    return Reservation(id=reservation_id, period_key=period_key, amount=amount)


def commit(session: Session, reservation_id: str) -> None:
    """Moves reserved allowance to used, once cards are staged."""
    reservation = session.get(QuotaReservation, reservation_id)
    if reservation is None or reservation.committed:
        return  # idempotent: a replayed commit is not an error

    session.execute(
        update(QuotaUsage)
        .where(
            QuotaUsage.user_id == reservation.user_id,
            QuotaUsage.period_key == reservation.period_key,
        )
        .values(
            used=QuotaUsage.used + reservation.amount,
            reserved=QuotaUsage.reserved - reservation.amount,
        )
    )
    reservation.committed = True
    session.flush()


def release(session: Session, reservation_id: str) -> None:
    """Returns allowance when a job fails for reasons that are not the user's.

    Infrastructure failure and a model refusal both land here — §10 charges
    nothing for a refusal, since a decline before any output is not billed.
    """
    reservation = session.get(QuotaReservation, reservation_id)
    if reservation is None or reservation.committed:
        return

    session.execute(
        update(QuotaUsage)
        .where(
            QuotaUsage.user_id == reservation.user_id,
            QuotaUsage.period_key == reservation.period_key,
        )
        .values(reserved=QuotaUsage.reserved - reservation.amount)
    )
    session.delete(reservation)
    session.flush()


def sweep_expired(session: Session, user_id: str | None = None, at: datetime | None = None) -> int:
    """Releases reservations whose worker died before starting."""
    at = at or datetime.now(timezone.utc)
    query = select(QuotaReservation).where(
        QuotaReservation.committed.is_(False),
        QuotaReservation.expires_at <= at,
    )
    if user_id is not None:
        query = query.where(QuotaReservation.user_id == user_id)

    stale = session.execute(query).scalars().all()
    for reservation in stale:
        session.execute(
            update(QuotaUsage)
            .where(
                QuotaUsage.user_id == reservation.user_id,
                QuotaUsage.period_key == reservation.period_key,
            )
            .values(reserved=QuotaUsage.reserved - reservation.amount)
        )
        session.delete(reservation)
    session.flush()
    return len(stale)


def remaining(
    session: Session,
    user_id: str,
    *,
    plan: str = "free",
    at: datetime | None = None,
    timezone_name: str = "America/Sao_Paulo",
) -> int:
    """What the client's quota indicator mirrors — never the authority (§7.7)."""
    at = at or datetime.now(timezone.utc)
    period_key = period_key_for(plan, at, timezone_name)
    row = session.execute(
        select(QuotaUsage).where(
            QuotaUsage.user_id == user_id, QuotaUsage.period_key == period_key
        )
    ).scalar_one_or_none()
    if row is None:
        return FREE_GENERATIONS_LIFETIME if plan == "free" else 0
    return max(0, row.limit_count - row.used - row.reserved)


__all__ = [
    "LIFETIME",
    "QuotaExhausted",
    "TooManyJobsInFlight",
    "Reservation",
    "commit",
    "period_key_for",
    "release",
    "remaining",
    "reserve",
    "sweep_expired",
    "text",
]
