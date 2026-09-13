"""Quota verification (§7.7, §7.7.1)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.contract import FREE_GENERATIONS_LIFETIME
from app.quota import service as quota
from app.quota.service import QuotaExhausted, TooManyJobsInFlight
from tests.test_sync import SessionFactory  # same engine and fixtures

NOW = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)


def uid() -> str:
    return str(uuid.uuid4())


@pytest.fixture
def db():
    with SessionFactory() as session:
        yield session
        session.rollback()


@pytest.fixture
def user(db: Session) -> str:
    user_id = uid()
    db.execute(text("INSERT INTO users (id) VALUES (:id)"), {"id": user_id})
    db.flush()
    return user_id


def test_the_free_tier_is_one_generation_ever(db, user):
    assert FREE_GENERATIONS_LIFETIME == 1

    quota.reserve(db, user, reservation_id=uid(), at=NOW)
    with pytest.raises(QuotaExhausted):
        quota.reserve(db, user, reservation_id=uid(), at=NOW)


def test_the_free_period_never_rolls_over(db, user):
    """A monthly reset would give a second free generation (§7.7.1).

    The generation must be *committed*: an uncommitted reservation is
    correctly released once it expires, which is the point of the sweeper.
    """
    reservation_id = uid()
    quota.reserve(db, user, reservation_id=reservation_id, at=NOW)
    quota.commit(db, reservation_id)

    much_later = NOW + timedelta(days=400)
    with pytest.raises(QuotaExhausted):
        quota.reserve(db, user, reservation_id=uid(), at=much_later)


def test_a_committed_generation_stays_spent(db, user):
    reservation_id = uid()
    quota.reserve(db, user, reservation_id=reservation_id, at=NOW)
    quota.commit(db, reservation_id)

    assert quota.remaining(db, user, at=NOW) == 0
    with pytest.raises(QuotaExhausted):
        quota.reserve(db, user, reservation_id=uid(), at=NOW)


def test_committing_twice_does_not_double_charge(db, user):
    reservation_id = uid()
    quota.reserve(db, user, reservation_id=reservation_id, at=NOW)
    quota.commit(db, reservation_id)
    quota.commit(db, reservation_id)

    row = db.execute(
        text("SELECT used, reserved FROM quota_usage WHERE user_id = :u"), {"u": user}
    ).one()
    assert row.used == 1
    assert row.reserved == 0


def test_a_released_reservation_gives_the_allowance_back(db, user):
    """§10 — a model refusal charges nothing, since it is not billed."""
    reservation_id = uid()
    quota.reserve(db, user, reservation_id=reservation_id, at=NOW)
    quota.release(db, reservation_id)

    assert quota.remaining(db, user, at=NOW) == 1
    quota.reserve(db, user, reservation_id=uid(), at=NOW)


def test_a_dead_worker_does_not_leak_the_allowance(db, user):
    """§7.7 — without expiry the user loses quota they never spent."""
    quota.reserve(db, user, reservation_id=uid(), at=NOW)
    assert quota.remaining(db, user, at=NOW) == 0

    after_ttl = NOW + quota.RESERVATION_TTL + timedelta(minutes=1)
    swept = quota.sweep_expired(db, user, at=after_ttl)
    assert swept == 1
    assert quota.remaining(db, user, at=after_ttl) == 1


def test_concurrent_reservations_cannot_exceed_the_limit(db, user):
    """The guard is in the WHERE clause, so the database decides.

    Read-then-write would let two simultaneous generations both see the old
    total and both pass.
    """
    limit = 3
    reserved = 0
    for _ in range(10):
        try:
            quota.reserve(db, user, reservation_id=uid(), at=NOW, limit_count=limit)
            reserved += 1
        except (QuotaExhausted, TooManyJobsInFlight):
            break
    assert reserved <= limit


def test_a_whole_allowance_cannot_be_queued_at_once(db, user):
    """§7.7 — at most two jobs in flight."""
    quota.reserve(db, user, reservation_id=uid(), at=NOW, limit_count=10)
    quota.reserve(db, user, reservation_id=uid(), at=NOW, limit_count=10)

    with pytest.raises(TooManyJobsInFlight):
        quota.reserve(db, user, reservation_id=uid(), at=NOW, limit_count=10)


def test_paid_periods_are_monthly_in_the_users_timezone(db, user):
    """§7.7 — a São Paulo user whose month resets at 21:00 would call that a bug."""
    last_moment = datetime(2026, 8, 31, 23, 30, tzinfo=UTC)  # 20:30 in SP
    assert quota.period_key_for("paid", last_moment, "America/Sao_Paulo") == "2026-08"

    just_after = datetime(2026, 9, 1, 4, 0, tzinfo=UTC)  # 01:00 in SP
    assert quota.period_key_for("paid", just_after, "America/Sao_Paulo") == "2026-09"


def test_the_free_period_key_is_not_a_month(db, user):
    assert quota.period_key_for("free", NOW, "America/Sao_Paulo") == quota.LIFETIME


def test_remaining_reflects_reservations_not_just_commits(db, user):
    """The client's indicator mirrors this; the server stays the authority."""
    assert quota.remaining(db, user, at=NOW) == 1
    quota.reserve(db, user, reservation_id=uid(), at=NOW)
    assert quota.remaining(db, user, at=NOW) == 0
