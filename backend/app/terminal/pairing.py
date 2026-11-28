"""Pairing a terminal from the site, by a code it shows (device flow).

The app pairs through the terminal's own Wi-Fi, which a web page cannot do:
a browser neither switches networks nor talks plain HTTP to 192.168.4.1 from
an HTTPS page. So the terminal, already on Wi-Fi, asks the server for a code
and shows it; someone signed in types it on the site; the terminal, polling
with a secret only it holds, then receives its own credential.

Rules this file keeps:

* The code is short-lived (ten minutes) and single-use, and only its hash is
  stored. Eight characters from a 31-letter alphabet are ~10^12 options;
  with the claim rate-limited per account, guessing one in ten minutes is
  not a plan.
* No terminal token is stored. It is minted on the poll that follows a claim,
  through the same `register_terminal` the app uses, and returned once.
* A terminal tied to another account moves to the account that claims the
  code — but only when, asking for the code, it sent the credential it holds
  now. That is the terminal itself asking (the person has it in hand), not
  someone who read its device_id. Without that proof it stays where it is.
"""

from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import TerminalCredential, TerminalPairing
from app.terminal import service

LIFETIME = timedelta(minutes=10)
POLL_INTERVAL_SECONDS = 3
# Sem 0/O e 1/I/L: o código é lido de uma tela de tinta e digitado no celular.
ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


class PairingNotFound(Exception):
    """Unknown, expired, already claimed or already used."""


class PairingConflict(Exception):
    """The terminal belongs to another account."""


@dataclass(frozen=True)
class Started:
    code: str
    poll_token: str
    expires_in: int
    interval: int


@dataclass(frozen=True)
class Polled:
    status: str  # pending | claimed | expired
    device_id: str | None = None
    device_token: str | None = None


def normalise_code(code: str) -> str:
    return "".join(ch for ch in code.upper() if ch.isalnum())


def _digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def _new_code() -> str:
    raw = "".join(secrets.choice(ALPHABET) for _ in range(8))
    return f"{raw[:4]}-{raw[4:]}"


def start(
    session: Session,
    *,
    device_id: str,
    model: str,
    firmware: str,
    current_token: str | None = None,
    now: datetime | None = None,
) -> Started:
    now = now or datetime.now(UTC)
    takeover = False
    if current_token:
        existing = session.get(TerminalCredential, device_id)
        takeover = (
            existing is not None
            and not existing.revoked
            and existing.token_hash == service._hash(current_token)
        )
    code = _new_code()
    poll_token = secrets.token_urlsafe(32)
    session.add(
        TerminalPairing(
            id=secrets.token_hex(18),
            code_hash=_digest(normalise_code(code)),
            poll_hash=_digest(poll_token),
            device_id=device_id,
            model=model,
            firmware=firmware,
            created_at=now,
            expires_at=now + LIFETIME,
            deck_ids=[],
            takeover_allowed=takeover,
        )
    )
    session.flush()
    return Started(
        code=code,
        poll_token=poll_token,
        expires_in=int(LIFETIME.total_seconds()),
        interval=POLL_INTERVAL_SECONDS,
    )


def claim(
    session: Session,
    user_id: str,
    code: str,
    deck_ids: list[str],
    *,
    now: datetime | None = None,
) -> TerminalPairing:
    now = now or datetime.now(UTC)
    row = session.execute(
        select(TerminalPairing)
        .where(TerminalPairing.code_hash == _digest(normalise_code(code)))
        .with_for_update()
    ).scalar_one_or_none()
    if row is None or row.claimed_at is not None or row.expires_at <= now:
        raise PairingNotFound("code not found")

    existing = session.get(TerminalCredential, row.device_id)
    if (
        existing is not None
        and existing.user_id != user_id
        and not existing.revoked
        and not row.takeover_allowed
    ):
        raise PairingConflict("terminal belongs to another account")

    row.claimed_by = user_id
    row.claimed_at = now
    row.deck_ids = list(dict.fromkeys(deck_ids))
    session.flush()
    return row


def poll(session: Session, poll_token: str, *, now: datetime | None = None) -> Polled:
    now = now or datetime.now(UTC)
    row = session.execute(
        select(TerminalPairing)
        .where(TerminalPairing.poll_hash == _digest(poll_token))
        .with_for_update()
    ).scalar_one_or_none()
    if row is None or row.consumed_at is not None:
        raise PairingNotFound("pairing not found")
    if row.claimed_at is None:
        if row.expires_at <= now:
            return Polled(status="expired")
        return Polled(status="pending")

    existing = session.get(TerminalCredential, row.device_id)
    if existing is not None and existing.user_id != row.claimed_by:
        if not (existing.revoked or row.takeover_allowed):
            raise PairingConflict("terminal belongs to another account")
        # The previous account lets go: its credential is gone, and the row
        # is made again for the account that just claimed the code. What the
        # terminal already synced stays in the previous account.
        session.delete(existing)
        session.flush()

    assert row.claimed_by is not None
    row.consumed_at = now
    try:
        # Commits: register_terminal owns its transaction, as in the app path.
        token = service.register_terminal(
            session,
            row.claimed_by,
            row.device_id,
            row.model,
            row.firmware,
            list(row.deck_ids or []),
        )
    except service.TerminalAuthError as exc:
        raise PairingConflict(str(exc)) from exc
    return Polled(status="claimed", device_id=row.device_id, device_token=token)
