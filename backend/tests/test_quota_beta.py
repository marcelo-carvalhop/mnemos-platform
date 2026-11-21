"""The beta plan: unlimited generation for accounts with an email."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import get_settings
from app.contract import FREE_GENERATIONS_LIFETIME
from app.quota import service as quota
from app.quota.service import QuotaExhausted, TooManyJobsInFlight
from tests.test_sync import SessionFactory

NOW = datetime(2026, 11, 21, 12, 0, tzinfo=UTC)


def uid() -> str:
    return str(uuid.uuid4())


@pytest.fixture
def db():
    with SessionFactory() as session:
        yield session
        session.rollback()


@pytest.fixture
def beta(monkeypatch):
    monkeypatch.setattr(get_settings(), "beta_unlimited_generation", True)


def make_user(db: Session, *, email: str | None) -> str:
    user_id = uid()
    db.execute(
        text("INSERT INTO users (id, email) VALUES (:id, :email)"),
        {"id": user_id, "email": email},
    )
    db.flush()
    return user_id


def reserve_as_the_app_does(db: Session, user_id: str) -> None:
    plan = quota.plan_for(db, user_id)
    reservation_id = uid()
    quota.reserve(
        db,
        user_id,
        reservation_id=reservation_id,
        plan=plan,
        limit_count=quota.limit_for(plan),
        at=NOW,
    )
    quota.commit(db, reservation_id)


def test_an_account_generates_past_the_free_allowance(db, beta):
    user = make_user(db, email=f"{uid()}@example.com")
    assert quota.plan_for(db, user) == "beta"

    for _ in range(FREE_GENERATIONS_LIFETIME + 4):
        reserve_as_the_app_does(db, user)

    assert quota.remaining(db, user, plan="beta", at=NOW) == quota.BETA_MONTHLY_CEILING - 5


def test_without_an_email_the_free_rule_stands(db, beta):
    """The beta is for accounts; an anonymous device keeps its one generation."""
    user = make_user(db, email=None)
    assert quota.plan_for(db, user) == "free"

    reserve_as_the_app_does(db, user)
    with pytest.raises(QuotaExhausted):
        reserve_as_the_app_does(db, user)


def test_the_switch_off_means_the_free_rule(db):
    user = make_user(db, email=f"{uid()}@example.com")
    assert quota.plan_for(db, user) == "free"


def test_concurrency_is_still_bounded(db, beta):
    """Unlimited is about the count, not about running many jobs at once."""
    user = make_user(db, email=f"{uid()}@example.com")
    with pytest.raises(TooManyJobsInFlight):
        for _ in range(50):
            quota.reserve(
                db,
                user,
                reservation_id=uid(),
                plan="beta",
                limit_count=quota.BETA_MONTHLY_CEILING,
                at=NOW,
            )


def test_a_new_account_sees_the_whole_ceiling(db, beta):
    user = make_user(db, email=f"{uid()}@example.com")
    assert quota.remaining(db, user, plan="beta", at=NOW) == quota.BETA_MONTHLY_CEILING
