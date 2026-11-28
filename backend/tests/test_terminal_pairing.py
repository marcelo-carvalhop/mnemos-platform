"""Pairing a terminal from the site: code on the terminal, claim on the web."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import update

from app.auth import service as auth
from app.db import SessionLocal
from app.main import app
from app.models import TerminalPairing
from app.terminal import pairing_router

client = TestClient(app)


@pytest.fixture(autouse=True)
def fresh_limits():
    pairing_router._starts = pairing_router.SlidingWindowLimiter()
    pairing_router._claims = pairing_router.SlidingWindowLimiter()


def account() -> dict:
    with SessionLocal() as session:
        pair = auth.register_device(
            session, device_id=str(uuid.uuid4()), platform="android", attested=True
        )
        session.commit()
    return {"Authorization": f"Bearer {pair.access_token}"}


def start(device_id: str | None = None) -> dict:
    r = client.post(
        "/v1/terminal/pairing/start",
        json={"device_id": device_id or f"T5S3-{uuid.uuid4().hex[:6]}", "firmware": "0.9.0"},
    )
    assert r.status_code == 200, r.text
    return r.json()


def poll(token: str):
    return client.post("/v1/terminal/pairing/poll", json={"poll_token": token})


def test_code_typed_on_the_site_hands_the_terminal_its_credential():
    started = start()
    assert len(started["code"]) == 9 and started["code"][4] == "-"
    assert started["verify_url"].endswith(f"/dispositivo?codigo={started['code']}")
    assert poll(started["poll_token"]).json()["status"] == "pending"

    headers = account()
    # Lower case, no dash: typed on a phone, it still matches.
    claimed = client.post(
        "/v1/terminals/pairing/claim",
        headers=headers,
        json={"code": started["code"].replace("-", "").lower()},
    )
    assert claimed.status_code == 200, claimed.text

    done = poll(started["poll_token"]).json()
    assert done["status"] == "claimed"
    token = done["device_token"]
    assert token

    # The credential works as the app's does.
    status = client.get("/v1/terminal/snapshot", headers={"Authorization": f"Bearer {token}"})
    assert status.status_code == 200
    listed = client.get("/v1/terminals", headers=headers).json()
    assert done["device_id"] in [t["device_id"] for t in listed]

    # Handed over once.
    assert poll(started["poll_token"]).status_code == 404


def test_a_code_opens_once_and_not_after_it_expires():
    started = start()
    first, second = account(), account()
    body = {"code": started["code"]}
    assert client.post("/v1/terminals/pairing/claim", headers=first, json=body).status_code == 200
    again = client.post("/v1/terminals/pairing/claim", headers=second, json=body)
    assert again.status_code == 404

    late = start()
    with SessionLocal() as session:
        session.execute(
            update(TerminalPairing)
            .where(TerminalPairing.device_id == late_device(late))
            .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
        )
        session.commit()
    expired = client.post("/v1/terminals/pairing/claim", headers=first, json={"code": late["code"]})
    assert expired.status_code == 404
    assert poll(late["poll_token"]).json()["status"] == "expired"


def late_device(started: dict) -> str:
    from app.terminal.pairing import _digest, normalise_code

    with SessionLocal() as session:
        row = (
            session.query(TerminalPairing)
            .filter(TerminalPairing.code_hash == _digest(normalise_code(started["code"])))
            .one()
        )
        return row.device_id


def test_a_terminal_of_another_account_is_not_taken():
    device = f"T5S3-{uuid.uuid4().hex[:6]}"
    owner, other = account(), account()
    first = start(device)
    client.post("/v1/terminals/pairing/claim", headers=owner, json={"code": first["code"]})
    assert poll(first["poll_token"]).json()["status"] == "claimed"

    second = start(device)
    taken = client.post("/v1/terminals/pairing/claim", headers=other, json={"code": second["code"]})
    assert taken.status_code == 409
    assert taken.json()["detail"] == "terminal_owned_elsewhere"


def test_the_same_account_can_pair_its_terminal_again():
    device = f"T5S3-{uuid.uuid4().hex[:6]}"
    owner = account()
    for _ in range(2):
        started = start(device)
        r = client.post(
            "/v1/terminals/pairing/claim", headers=owner, json={"code": started["code"]}
        )
        assert r.status_code == 200
        assert poll(started["poll_token"]).json()["status"] == "claimed"


def test_guessing_is_rate_limited(monkeypatch):
    headers = account()
    codes = [
        client.post("/v1/terminals/pairing/claim", headers=headers, json={"code": "AAAA-AAAA"})
    ]
    for _ in range(10):
        codes.append(
            client.post("/v1/terminals/pairing/claim", headers=headers, json={"code": "AAAA-AAAA"})
        )
    assert codes[0].status_code == 404
    assert codes[-1].status_code == 429
