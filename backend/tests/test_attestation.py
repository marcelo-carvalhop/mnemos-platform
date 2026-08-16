"""§8.1 — what stands between a reinstall and a second free allowance.

The platform verifiers cannot run here: Play Integrity needs a Play Console
service account and App Attest needs a real iPhone. Those are human gates, and
they are recorded as such. Everything around them can be tested, and this file
tests it — including the specific hole that existed before, which is that any
string at all bought a fresh anonymous account.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import attestation
from app.auth.attestation import AttestationFailed
from app.config import Settings, get_settings
from app.main import app
from app.models import AttestationChallenge
from tests.test_sync import engine

NOW = datetime(2026, 8, 9, 12, 0, tzinfo=timezone.utc)


def uid() -> str:
    return str(uuid.uuid4())


@pytest.fixture
def db():
    connection = engine.connect()
    transaction = connection.begin()
    session = Session(bind=connection, join_transaction_mode="create_savepoint")
    try:
        yield session
    finally:
        session.close()
        transaction.rollback()
        connection.close()


# ---------------------------------------------------------------------------
# The challenge
# ---------------------------------------------------------------------------


def test_a_challenge_can_only_be_spent_once(db: Session):
    """The hole a nonce closes: a valid assertion, captured, is otherwise a
    permanent credential."""
    device = uid()
    nonce = attestation.issue_challenge(db, device, now=NOW)

    attestation.consume_challenge(db, nonce, device, now=NOW)

    with pytest.raises(AttestationFailed, match="already used"):
        attestation.consume_challenge(db, nonce, device, now=NOW)


def test_a_challenge_belongs_to_the_device_it_was_issued_for(db: Session):
    nonce = attestation.issue_challenge(db, uid(), now=NOW)

    with pytest.raises(AttestationFailed, match="different device"):
        attestation.consume_challenge(db, nonce, uid(), now=NOW)


def test_a_challenge_that_belonged_to_someone_else_is_still_spent(db: Session):
    """Rejecting must not leave the nonce reusable.

    Otherwise an attacker probes device ids until one matches, with the same
    nonce every time.
    """
    owner = uid()
    nonce = attestation.issue_challenge(db, owner, now=NOW)

    with pytest.raises(AttestationFailed):
        attestation.consume_challenge(db, nonce, uid(), now=NOW)

    with pytest.raises(AttestationFailed, match="already used"):
        attestation.consume_challenge(db, nonce, owner, now=NOW)


def test_an_expired_challenge_is_refused(db: Session):
    device = uid()
    nonce = attestation.issue_challenge(db, device, now=NOW)

    later = NOW + attestation.CHALLENGE_TTL + timedelta(seconds=1)
    with pytest.raises(AttestationFailed, match="expired"):
        attestation.consume_challenge(db, nonce, device, now=later)


def test_an_unknown_nonce_is_refused(db: Session):
    with pytest.raises(AttestationFailed, match="unknown"):
        attestation.consume_challenge(db, "not-a-nonce", uid(), now=NOW)


def test_issuing_sweeps_what_has_expired(db: Session):
    stale = uid()
    attestation.issue_challenge(db, stale, now=NOW - timedelta(hours=2))
    assert db.execute(select(AttestationChallenge)).scalars().all()

    attestation.issue_challenge(db, uid(), now=NOW)

    remaining = db.execute(select(AttestationChallenge)).scalars().all()
    assert all(row.device_id != stale for row in remaining)


def test_two_challenges_are_never_the_same(db: Session):
    device = uid()
    issued = {attestation.issue_challenge(db, device, now=NOW) for _ in range(20)}
    assert len(issued) == 20


# ---------------------------------------------------------------------------
# Verification refuses rather than passes when it cannot check
# ---------------------------------------------------------------------------


def test_an_unconfigured_server_refuses_instead_of_waving_through(db: Session, monkeypatch):
    """The failure mode that matters. A verifier with no credentials must not
    decide that everything is fine."""
    device = uid()
    nonce = attestation.issue_challenge(db, device, now=NOW)

    monkeypatch.setattr(
        "app.auth.attestation.get_settings",
        lambda: Settings(require_attestation=True),
    )

    with pytest.raises(AttestationFailed, match="not configured"):
        attestation.verify(
            db, device_id=device, platform="android", token="anything", nonce=nonce, now=NOW
        )


def test_an_unknown_platform_is_refused(db: Session, monkeypatch):
    device = uid()
    nonce = attestation.issue_challenge(db, device, now=NOW)
    monkeypatch.setattr(
        "app.auth.attestation.get_settings",
        lambda: Settings(require_attestation=True),
    )

    with pytest.raises(AttestationFailed, match="unknown platform"):
        attestation.verify(
            db, device_id=device, platform="web", token="x", nonce=nonce, now=NOW
        )


def test_verification_spends_the_challenge_before_calling_the_platform(
    db: Session, monkeypatch
):
    """A platform call that fails must not leave the nonce reusable, or the
    attacker simply retries until the network cooperates."""
    device = uid()
    nonce = attestation.issue_challenge(db, device, now=NOW)
    monkeypatch.setattr(
        "app.auth.attestation.get_settings",
        lambda: Settings(require_attestation=True),
    )

    with pytest.raises(AttestationFailed):
        attestation.verify(
            db, device_id=device, platform="android", token="x", nonce=nonce, now=NOW
        )

    with pytest.raises(AttestationFailed, match="already used"):
        attestation.consume_challenge(db, nonce, device, now=NOW)


# ---------------------------------------------------------------------------
# Play Integrity verdicts (the decode is stubbed; the judgement is not)
# ---------------------------------------------------------------------------


def _payload(nonce: str, **overrides) -> dict:
    import base64

    expected = (
        base64.urlsafe_b64encode(attestation.expected_nonce_hash(nonce)).decode().rstrip("=")
    )
    payload = {
        "requestDetails": {"requestHash": expected, "requestPackageName": "br.com.flashcards"},
        "appIntegrity": {"appRecognitionVerdict": "PLAY_RECOGNIZED"},
        "deviceIntegrity": {"deviceRecognitionVerdict": ["MEETS_DEVICE_INTEGRITY"]},
    }
    for key, value in overrides.items():
        payload[key] = {**payload.get(key, {}), **value}
    return payload


@pytest.fixture
def play_configured(monkeypatch):
    monkeypatch.setattr(
        "app.auth.attestation.get_settings",
        lambda: Settings(
            require_attestation=True,
            play_integrity_package="br.com.flashcards",
            google_credentials_json='{"type":"service_account"}',
        ),
    )


def test_a_genuine_verdict_passes(play_configured, monkeypatch):
    nonce = "abc"
    monkeypatch.setattr(
        "app.auth.attestation._decode_integrity_token", lambda *_: _payload(nonce)
    )
    attestation.verify_play_integrity("token", nonce)


def test_an_emulator_is_refused_even_with_basic_integrity(play_configured, monkeypatch):
    """MEETS_BASIC_INTEGRITY alone is what an emulator farm clears — and a
    free allowance per install is exactly what an emulator farm is for."""
    nonce = "abc"
    monkeypatch.setattr(
        "app.auth.attestation._decode_integrity_token",
        lambda *_: _payload(
            nonce, deviceIntegrity={"deviceRecognitionVerdict": ["MEETS_BASIC_INTEGRITY"]}
        ),
    )
    with pytest.raises(AttestationFailed, match="device integrity"):
        attestation.verify_play_integrity("token", nonce)


def test_a_build_google_does_not_recognise_is_refused(play_configured, monkeypatch):
    nonce = "abc"
    monkeypatch.setattr(
        "app.auth.attestation._decode_integrity_token",
        lambda *_: _payload(
            nonce, appIntegrity={"appRecognitionVerdict": "UNRECOGNIZED_VERSION"}
        ),
    )
    with pytest.raises(AttestationFailed, match="not recognised"):
        attestation.verify_play_integrity("token", nonce)


def test_a_token_minted_for_another_challenge_is_refused(play_configured, monkeypatch):
    monkeypatch.setattr(
        "app.auth.attestation._decode_integrity_token", lambda *_: _payload("some other nonce")
    )
    with pytest.raises(AttestationFailed, match="challenge"):
        attestation.verify_play_integrity("token", "ours")


def test_a_token_for_another_package_is_refused(play_configured, monkeypatch):
    nonce = "abc"
    payload = _payload(nonce)
    payload["requestDetails"]["requestPackageName"] = "com.someone.else"
    monkeypatch.setattr("app.auth.attestation._decode_integrity_token", lambda *_: payload)
    with pytest.raises(AttestationFailed, match="another package"):
        attestation.verify_play_integrity("token", nonce)


# ---------------------------------------------------------------------------
# App Attest — the parts that need no iPhone
# ---------------------------------------------------------------------------


def test_app_attest_refuses_an_unreadable_attestation(db: Session, monkeypatch):
    monkeypatch.setattr(
        "app.auth.attestation.get_settings",
        lambda: Settings(
            require_attestation=True,
            app_attest_app_id="TEAMID.br.com.flashcards",
            app_attest_root_pem="-----BEGIN CERTIFICATE-----\nnot a cert\n-----END CERTIFICATE-----",
        ),
    )
    with pytest.raises(AttestationFailed, match="not readable"):
        attestation.verify_app_attest(db, device_id=uid(), token="bm90IGNib3I=", nonce="abc")


def test_app_attest_refuses_an_unexpected_format(db: Session, monkeypatch):
    import base64

    import cbor2

    monkeypatch.setattr(
        "app.auth.attestation.get_settings",
        lambda: Settings(
            require_attestation=True,
            app_attest_app_id="TEAMID.br.com.flashcards",
            app_attest_root_pem="-----BEGIN CERTIFICATE-----\nx\n-----END CERTIFICATE-----",
        ),
    )
    token = base64.b64encode(
        cbor2.dumps({"fmt": "packed", "attStmt": {}, "authData": b""})
    ).decode()

    with pytest.raises(AttestationFailed, match="unexpected attestation format"):
        attestation.verify_app_attest(db, device_id=uid(), token=token, nonce="abc")


# ---------------------------------------------------------------------------
# Over HTTP
# ---------------------------------------------------------------------------


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def test_the_challenge_endpoint_needs_no_token(client):
    """It runs before any account exists, and hands out only a random string."""
    response = client.post("/v1/auth/challenge", json={"device_id": uid()})
    assert response.status_code == 200
    body = response.json()
    assert len(body["nonce"]) >= 32
    assert body["expires_in"] == int(attestation.CHALLENGE_TTL.total_seconds())


def test_with_attestation_on_a_bare_device_call_is_refused(client, monkeypatch):
    """The regression this whole module exists for.

    Before, `attestation: "anything"` was accepted and minted a free
    allowance; the check was for presence, not validity.
    """
    monkeypatch.setattr(
        "app.auth.router.get_settings",
        lambda: Settings(require_attestation=True),
    )

    without = client.post(
        "/v1/auth/device", json={"device_id": uid(), "platform": "android"}
    )
    assert without.status_code == 403

    with_junk = client.post(
        "/v1/auth/device",
        json={
            "device_id": uid(),
            "platform": "android",
            "attestation": "anything",
            "nonce": "made-up",
        },
    )
    assert with_junk.status_code == 403


def test_with_attestation_off_development_still_works(client):
    """`docker compose up` from a fresh clone must not need a Play Console."""
    assert get_settings().require_attestation is False

    response = client.post(
        "/v1/auth/device", json={"device_id": uid(), "platform": "android"}
    )
    assert response.status_code == 200


# ---------------------------------------------------------------------------
# Production configuration
# ---------------------------------------------------------------------------


def test_production_refuses_to_boot_with_attestation_on_and_nothing_configured():
    """Two ways of being wrong at once: verifies nothing, rejects everyone."""
    settings = Settings(
        environment="production",
        jwt_secret="a" * 40,
        require_attestation=True,
    )
    with pytest.raises(RuntimeError, match="neither Play Integrity nor App Attest"):
        settings.validate_for_production()


def test_production_boots_with_play_integrity_configured():
    Settings(
        environment="production",
        jwt_secret="a" * 40,
        require_attestation=True,
        play_integrity_package="br.com.flashcards",
        google_credentials_json='{"type":"service_account"}',
    ).validate_for_production()


def test_the_play_integrity_transport_actually_imports():
    """A dependency missing only on the verification path fails in production.

    Every other Play Integrity test stubs `_decode_integrity_token`, so none of
    them imports what it imports — and `google.auth.transport.requests` needs
    `requests`, which was not installed. The failure surfaced by hand, against
    a running container, on the one path no test walked.
    """
    import google.auth.transport.requests  # noqa: F401
    from google.oauth2 import service_account  # noqa: F401


def test_unusable_google_credentials_are_a_refusal_not_a_crash(play_configured):
    """Found by hand against a container: a malformed service account raised
    google.auth's MalformedError straight through, which is a 500. Our
    misconfiguration is still not a pass, and it should say so at 403."""
    with pytest.raises(AttestationFailed, match="credentials are unusable"):
        attestation.verify_play_integrity("token", "abc")
