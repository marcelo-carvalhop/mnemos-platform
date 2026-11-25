"""O "Avise-me" do plano com IA."""

from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.db import SessionLocal
from app.main import app
from app.models import WaitlistEntry
from app.waitlist import router as waitlist


@pytest.fixture
def client():
    waitlist._limiter = waitlist.SlidingWindowLimiter()
    with TestClient(app) as c:
        yield c


def address() -> str:
    return f"pessoa-{uuid.uuid4().hex[:10]}@exemplo.com"


def stored(email: str) -> list[WaitlistEntry]:
    with SessionLocal() as session:
        return list(session.scalars(select(WaitlistEntry).where(WaitlistEntry.email == email)))


def test_keeps_the_address_normalised(client):
    email = address()
    r = client.post("/v1/waitlist", json={"email": f"  {email.upper()} "})
    assert r.status_code == 202
    assert r.json() == {"status": "ok"}
    rows = stored(email)
    assert [(row.email, row.plan) for row in rows] == [(email, "ai")]


def test_asking_twice_answers_the_same_and_keeps_one_row(client):
    email = address()
    first = client.post("/v1/waitlist", json={"email": email})
    second = client.post("/v1/waitlist", json={"email": email})
    assert first.status_code == second.status_code == 202
    assert first.json() == second.json()
    assert len(stored(email)) == 1


def test_rejects_what_is_not_an_email(client):
    assert client.post("/v1/waitlist", json={"email": "não é e-mail"}).status_code == 422
    assert client.post("/v1/waitlist", json={"email": address(), "plan": "x"}).status_code == 422


def test_a_flood_is_stopped(client, monkeypatch):
    monkeypatch.setattr(waitlist, "PER_MINUTE", 2)
    assert client.post("/v1/waitlist", json={"email": address()}).status_code == 202
    assert client.post("/v1/waitlist", json={"email": address()}).status_code == 202
    blocked = client.post("/v1/waitlist", json={"email": address()})
    assert blocked.status_code == 429
    assert int(blocked.headers["Retry-After"]) > 0
