"""Convites como linhas: quantas contas cada um trouxe."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.auth import mail
from app.auth.service import invite_hash
from app.config import get_settings
from app.db import SessionLocal
from app.invites.__main__ import main as cli
from app.main import app
from app.models import Invite, User

client = TestClient(app)


@pytest.fixture(autouse=True)
def invite_only(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "invite_code", "")
    monkeypatch.setattr(settings, "require_invite", True)
    monkeypatch.setattr(settings, "require_email_verification", True)
    monkeypatch.setattr(settings, "smtp_host", "")
    monkeypatch.setattr(mail, "send_verification", lambda to, token: None)


def email() -> str:
    return f"pessoa-{uuid.uuid4().hex[:10]}@example.com"


def code() -> str:
    return f"T-{uuid.uuid4().hex[:8]}"


def register(address: str, invite: str | None):
    return client.post(
        "/v1/auth/register",
        json={
            "email": address,
            "password": "senha-forte-1",
            "device_id": str(uuid.uuid4()),
            "invite_code": invite,
        },
    )


def make_invite(raw: str, *, label: str = "Turma", max_uses: int | None = None, revoked=False):
    with SessionLocal() as session:
        invite = Invite(
            id=uuid.uuid4().hex,
            code_hash=invite_hash(raw),
            code_hint=raw.lower()[:4],
            label=label,
            max_uses=max_uses,
            created_at=datetime.now(UTC),
            revoked_at=datetime.now(UTC) if revoked else None,
        )
        session.add(invite)
        session.commit()
        return invite.id


def invite_of(address: str) -> str | None:
    with SessionLocal() as session:
        return session.execute(select(User.invite_id).where(User.email == address)).scalar_one()


def test_the_account_remembers_its_invite():
    raw = code()
    invite_id = make_invite(raw)
    address = email()
    assert register(address, f"  {raw.upper()} ").status_code == 200
    assert invite_of(address) == invite_id


def test_a_listed_code_becomes_a_row_on_first_use(monkeypatch):
    raw = code()
    monkeypatch.setattr(get_settings(), "invite_code", f"outro,{raw}")
    first, second = email(), email()
    assert register(first, raw).status_code == 200
    assert register(second, raw).status_code == 200
    with SessionLocal() as session:
        invite = session.execute(
            select(Invite).where(Invite.code_hash == invite_hash(raw))
        ).scalar_one()
    assert invite.label == "INVITE_CODE nº 2"
    assert invite_of(first) == invite_of(second) == invite.id


def test_revoked_and_full_invites_open_nothing():
    revoked = code()
    make_invite(revoked, revoked=True)
    assert register(email(), revoked).status_code == 403

    limited = code()
    make_invite(limited, max_uses=1)
    assert register(email(), limited).status_code == 200
    refused = register(email(), limited)
    assert refused.status_code == 403
    assert refused.json()["detail"] == "invite_invalid"


def test_unknown_or_missing_code_is_refused():
    assert register(email(), "nao-existe").status_code == 403
    assert register(email(), None).status_code == 403


def test_the_cli_creates_counts_and_reassigns(capsys):
    label = f"Turma {uuid.uuid4().hex[:6]}"
    cli(["criar", label, "--limite", "5"])
    out = capsys.readouterr().out
    raw = next(line for line in out.splitlines() if line.startswith("Código: "))[8:]

    address = email()
    assert register(address, raw).status_code == 200
    cli(["listar"])
    listing = capsys.readouterr().out
    row = next(line for line in listing.splitlines() if line.startswith(label))
    assert row.split()[3:5] == ["1", "0"]  # uma conta, nenhuma confirmada ainda

    other = f"Outra {uuid.uuid4().hex[:6]}"
    cli(["criar", other])
    capsys.readouterr()
    cli(["atribuir", other, address])
    with SessionLocal() as session:
        target = session.execute(select(Invite.id).where(Invite.label == other)).scalar_one()
    assert invite_of(address) == target
