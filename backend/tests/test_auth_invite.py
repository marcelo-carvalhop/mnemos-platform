"""Invite-only accounts with email confirmation — end to end through the API."""

from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.auth import mail
from app.config import get_settings
from app.db import SessionLocal
from app.main import app
from app.models import User

client = TestClient(app)
INVITE = "abc123def456"


@pytest.fixture
def invite_only(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "invite_code", INVITE)
    monkeypatch.setattr(settings, "require_email_verification", True)
    monkeypatch.setattr(settings, "smtp_host", "")


@pytest.fixture
def outbox(monkeypatch):
    sent: list[tuple[str, str]] = []
    monkeypatch.setattr(mail, "send_verification", lambda to, token: sent.append((to, token)))
    return sent


def email() -> str:
    return f"pessoa-{uuid.uuid4().hex[:10]}@example.com"


def did() -> str:
    return str(uuid.uuid4())


def register(address: str, *, invite: str | None = INVITE, password: str = "senha-forte-1"):
    return client.post(
        "/v1/auth/register",
        json={
            "email": address,
            "password": password,
            "device_id": did(),
            "invite_code": invite,
        },
    )


def login(address: str, password: str = "senha-forte-1"):
    return client.post(
        "/v1/auth/login", json={"email": address, "password": password, "device_id": did()}
    )


def test_options_say_what_signing_up_needs(invite_only):
    body = client.get("/v1/auth/options").json()
    assert body == {"invite_required": True, "email_verification_required": True}


def test_a_wrong_invite_is_refused_before_anything_else(invite_only, outbox):
    response = register(email(), invite="errado")
    assert response.status_code == 403
    assert response.json()["detail"] == "invite_invalid"
    assert outbox == []


def test_the_invite_ignores_case_and_spaces(invite_only, outbox):
    response = register(email(), invite=f"  {INVITE.upper()} ")
    assert response.status_code == 200, response.text


def test_signup_sends_a_link_and_login_waits_for_it(invite_only, outbox):
    address = email()
    response = register(address)
    assert response.status_code == 200, response.text
    assert response.json() == {"status": "verification_sent", "email": address, "tokens": None}
    assert [to for to, _ in outbox] == [address]

    refused = login(address)
    assert refused.status_code == 403
    assert refused.json()["detail"] == "email_not_verified"

    # A wrong password must not reveal that the address is pending.
    assert login(address, "outra-senha-9").status_code == 401

    token = outbox[0][1]
    confirmed = client.post("/v1/auth/verify-email", json={"token": token, "device_id": did()})
    assert confirmed.status_code == 200, confirmed.text
    assert confirmed.json()["email"] == address
    assert confirmed.json()["tokens"]["access_token"]

    assert login(address).status_code == 200
    # Single use.
    again = client.post("/v1/auth/verify-email", json={"token": token})
    assert again.status_code == 400


def test_a_confirmed_address_cannot_be_registered_again(invite_only, outbox):
    address = email()
    register(address)
    client.post("/v1/auth/verify-email", json={"token": outbox[0][1]})
    assert register(address).status_code == 409


def test_registering_an_unconfirmed_address_again_replaces_the_link(invite_only, outbox):
    address = email()
    register(address, password="primeira-senha")
    register(address, password="segunda-senha")
    first, second = outbox[0][1], outbox[1][1]

    assert client.post("/v1/auth/verify-email", json={"token": first}).status_code == 400
    assert client.post("/v1/auth/verify-email", json={"token": second}).status_code == 200
    assert login(address, "segunda-senha").status_code == 200
    assert login(address, "primeira-senha").status_code == 401


def test_resend_answers_the_same_for_anyone(invite_only, outbox):
    address = email()
    register(address)
    outbox.clear()

    with SessionLocal() as db:
        user = db.execute(select(User).where(User.email == address)).scalar_one()
        user.email_verification_sent_at = user.email_verification_sent_at.replace(year=2000)
        db.commit()

    pending = client.post("/v1/auth/resend-verification", json={"email": address})
    unknown = client.post("/v1/auth/resend-verification", json={"email": email()})
    assert pending.status_code == unknown.status_code == 202
    assert pending.json() == unknown.json()
    assert [to for to, _ in outbox] == [address]

    # Pressed again right away: nothing more is sent.
    client.post("/v1/auth/resend-verification", json={"email": address})
    assert len(outbox) == 1


def test_an_expired_link_is_refused(invite_only, outbox):
    address = email()
    register(address)
    with SessionLocal() as db:
        user = db.execute(select(User).where(User.email == address)).scalar_one()
        user.email_verification_sent_at = user.email_verification_sent_at.replace(year=2000)
        db.commit()
    response = client.post("/v1/auth/verify-email", json={"token": outbox[0][1]})
    assert response.status_code == 400


def test_anonymous_accounts_are_refused_and_existing_ones_locked_out(monkeypatch):
    # Created while the server was still open.
    open_account = client.post(
        "/v1/auth/device", json={"device_id": did(), "platform": "android"}
    ).json()

    settings = get_settings()
    monkeypatch.setattr(settings, "invite_code", INVITE)
    monkeypatch.setattr(settings, "require_email_verification", True)

    refused = client.post("/v1/auth/device", json={"device_id": did(), "platform": "android"})
    assert refused.status_code == 403
    assert refused.json()["detail"] == "account_required"

    locked = client.get(
        "/v1/quota/", headers={"Authorization": f"Bearer {open_account['access_token']}"}
    )
    assert locked.status_code == 403
    assert locked.json()["detail"] == "account_required"


def test_a_confirmed_member_uses_the_api(invite_only, outbox):
    address = email()
    register(address)
    tokens = client.post(
        "/v1/auth/verify-email", json={"token": outbox[0][1], "device_id": did()}
    ).json()["tokens"]
    quota = client.get("/v1/quota/", headers={"Authorization": f"Bearer {tokens['access_token']}"})
    assert quota.status_code == 200


def test_an_open_server_signs_in_on_register(monkeypatch, outbox):
    settings = get_settings()
    monkeypatch.setattr(settings, "invite_code", "")
    monkeypatch.setattr(settings, "require_email_verification", False)
    response = register(email(), invite=None)
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "signed_in"
    assert response.json()["tokens"]["access_token"]
    assert outbox == []


def test_the_link_points_at_the_web_confirmation_route(monkeypatch):
    monkeypatch.setattr(get_settings(), "public_web_url", "https://exemplo.test/")
    assert mail.verification_link("a b") == "https://exemplo.test/confirmar?token=a%20b"


def test_sender_keeps_only_the_address(monkeypatch):
    """MAIL_FROM as a bare address or as "Name <address>" gives the same From."""
    from app.auth import mail
    from app.config import get_settings

    settings = get_settings()
    for value in ("eu@example.com", "Mnemos <eu@example.com>", "Outro Nome <eu@example.com>"):
        monkeypatch.setattr(settings, "mail_from", value)
        assert mail.sender() == "Mnemos <eu@example.com>"
    monkeypatch.setattr(settings, "mail_from", "")
    monkeypatch.setattr(settings, "smtp_user", "conta@example.com")
    assert mail.sender() == "Mnemos <conta@example.com>"
