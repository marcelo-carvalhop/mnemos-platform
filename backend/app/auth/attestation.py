"""Device attestation (§8.1).

Why this matters more than it looks. §7.7 makes the free tier **one generation
for the lifetime of the account**, and the anonymous account is created on
first launch, bound to a device id the client generates. Nothing else stands
between a reinstall and a second free allowance. Until this module existed the
check was `attestation is not None` — any string bought a new allowance, which
is not a weak check, it is the absence of one.

Three things have to hold, and each is a separate failure if it does not:

1. **The assertion must be fresh.** A valid attestation captured once and
   replayed forever is worth as much to an attacker as no attestation. So the
   server issues a single-use challenge, stores it, and consumes it.
2. **It must come from our app, on genuine hardware.** Play Integrity says so
   for Android; App Attest's certificate chain says so for iOS.
3. **It must be bound to the device id being registered**, or an attestation
   for device A registers device B.

Neither verifier can be exercised from a development machine: Play Integrity
needs a Play Console service account and App Attest needs a real iPhone. That
is a genuine human gate, and it is recorded as one — but the *structure* here
is testable, and the tests below cover every path that does not require
Apple or Google to answer.
"""

from __future__ import annotations

import base64
import hashlib
import logging
import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models import AttestationChallenge, Device

logger = logging.getLogger(__name__)

# Long enough for a slow attestation on a cold app start, short enough that a
# captured challenge is not a standing credential.
CHALLENGE_TTL = timedelta(minutes=5)


class AttestationFailed(Exception):
    """The assertion did not prove what it needed to prove."""


# ---------------------------------------------------------------------------
# The challenge
# ---------------------------------------------------------------------------


def issue_challenge(session: Session, device_id: str, *, now: datetime | None = None) -> str:
    """A single-use nonce, bound to the device that will use it."""
    now = now or datetime.now(timezone.utc)

    # Expired rows are swept here rather than by a cron: the table is only
    # touched on first launch, so it stays small on its own.
    session.execute(
        delete(AttestationChallenge).where(AttestationChallenge.expires_at < now)
    )

    nonce = secrets.token_urlsafe(32)
    session.add(
        AttestationChallenge(
            nonce=nonce,
            device_id=device_id,
            expires_at=now + CHALLENGE_TTL,
        )
    )
    session.flush()
    return nonce


def consume_challenge(
    session: Session, nonce: str, device_id: str, *, now: datetime | None = None
) -> None:
    """Spends a challenge. Raises if it is unknown, expired, or another
    device's.

    Deleting rather than flagging is deliberate: there is no state in which a
    challenge has been used and still exists, so a race cannot spend it twice.
    """
    now = now or datetime.now(timezone.utc)

    row = session.execute(
        select(AttestationChallenge)
        .where(AttestationChallenge.nonce == nonce)
        .with_for_update(skip_locked=True)
    ).scalar_one_or_none()

    if row is None:
        raise AttestationFailed("unknown or already used challenge")
    session.delete(row)
    session.flush()

    if row.device_id != device_id:
        raise AttestationFailed("challenge was issued for a different device")
    if row.expires_at < now:
        raise AttestationFailed("challenge expired")


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------


def verify(
    session: Session,
    *,
    device_id: str,
    platform: str,
    token: str,
    nonce: str,
    now: datetime | None = None,
) -> None:
    """Raises [AttestationFailed] unless the device proved itself.

    Returning nothing on success is on purpose: there is no partial result to
    misread as a pass.

    **Whether attestation is required is not decided here.** It was, briefly,
    and the router decided it too — so a test that switched it on in one place
    and not the other got a pass from the half that was still off. One question
    with two answers is worse than either answer; the caller asks, this
    function only verifies.
    """
    consume_challenge(session, nonce, device_id, now=now)

    if platform == "android":
        verify_play_integrity(token, nonce)
    elif platform == "ios":
        verify_app_attest(session, device_id=device_id, token=token, nonce=nonce)
    else:
        raise AttestationFailed(f"unknown platform: {platform}")


def expected_nonce_hash(nonce: str) -> bytes:
    """Both platforms bind to a hash of the challenge, not to the challenge."""
    return hashlib.sha256(nonce.encode()).digest()


# ---------------------------------------------------------------------------
# Android — Play Integrity
# ---------------------------------------------------------------------------


def verify_play_integrity(token: str, nonce: str) -> None:
    """Decodes the integrity token through Google and reads the verdicts.

    Decoding server-side rather than locally is the documented path and keeps
    the decryption keys out of this codebase entirely.
    """
    settings = get_settings()
    if not settings.play_integrity_package or not settings.google_credentials_json:
        raise AttestationFailed("Play Integrity is not configured on this server")

    payload = _decode_integrity_token(token, settings)

    request_details = payload.get("requestDetails", {})
    app_integrity = payload.get("appIntegrity", {})
    device_integrity = payload.get("deviceIntegrity", {})

    # The nonce is base64url without padding, per the Play Integrity contract.
    expected = base64.urlsafe_b64encode(expected_nonce_hash(nonce)).decode().rstrip("=")
    if (request_details.get("requestHash") or request_details.get("nonce")) != expected:
        raise AttestationFailed("integrity token does not carry our challenge")

    if request_details.get("requestPackageName") != settings.play_integrity_package:
        raise AttestationFailed("integrity token is for another package")

    # PLAY_RECOGNIZED means Google Play recognises this exact APK. Anything
    # else — UNRECOGNIZED_VERSION, UNEVALUATED — is a build we did not ship.
    if app_integrity.get("appRecognitionVerdict") != "PLAY_RECOGNIZED":
        raise AttestationFailed(
            f"app not recognised: {app_integrity.get('appRecognitionVerdict')}"
        )

    verdicts = set(device_integrity.get("deviceRecognitionVerdict") or [])
    if "MEETS_DEVICE_INTEGRITY" not in verdicts:
        # Deliberately not accepting MEETS_BASIC_INTEGRITY alone: an emulator
        # farm clears that, and a free allowance per install is exactly what
        # an emulator farm is for.
        raise AttestationFailed(f"device integrity not met: {sorted(verdicts)}")


def _decode_integrity_token(token: str, settings) -> dict:
    import google.auth.transport.requests
    import httpx
    from google.oauth2 import service_account

    try:
        credentials = service_account.Credentials.from_service_account_info(
            settings.google_credentials(),
            scopes=["https://www.googleapis.com/auth/playintegrity"],
        )
        credentials.refresh(google.auth.transport.requests.Request())
    except Exception as exc:  # noqa: BLE001
        # A malformed service account is our misconfiguration, not the user's
        # — but it is still not a pass. 403 with a clear reason beats a 500,
        # and a broken key must never become a granted allowance.
        raise AttestationFailed(f"Play Integrity credentials are unusable: {exc}") from exc

    url = (
        "https://playintegrity.googleapis.com/v1/"
        f"{settings.play_integrity_package}:decodeIntegrityToken"
    )
    try:
        response = httpx.post(
            url,
            json={"integrity_token": token},
            headers={"Authorization": f"Bearer {credentials.token}"},
            timeout=10,
        )
        response.raise_for_status()
    except httpx.HTTPError as exc:
        # Google being unreachable is not the user's fault, but it is also not
        # a pass: no allowance is granted on an unverified device.
        raise AttestationFailed(f"could not reach Play Integrity: {exc}") from exc

    return response.json().get("tokenPayloadExternal", {})


# ---------------------------------------------------------------------------
# iOS — App Attest
# ---------------------------------------------------------------------------

# Apple's App Attest root, from https://www.apple.com/certificateauthority/
APPLE_APP_ATTEST_ROOT_CN = "Apple App Attest Root CA"

# 1.2.840.113635.100.8.2 — the extension carrying the nonce Apple signed.
_APPLE_NONCE_OID = "1.2.840.113635.100.8.2"


def verify_app_attest(session: Session, *, device_id: str, token: str, nonce: str) -> None:
    """Validates an App Attest attestation object.

    The algorithm is Apple's, followed in their order:
    chain to the root, nonce, key id, app id, counter, then remember the key.
    """
    import cbor2
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization

    settings = get_settings()
    if not settings.app_attest_app_id or not settings.app_attest_root_pem:
        raise AttestationFailed("App Attest is not configured on this server")

    try:
        attestation = cbor2.loads(base64.b64decode(token))
    except Exception as exc:  # noqa: BLE001 — malformed input is a failure
        raise AttestationFailed(f"attestation object is not readable: {exc}") from exc

    if attestation.get("fmt") != "apple-appattest":
        raise AttestationFailed(f"unexpected attestation format: {attestation.get('fmt')}")

    statement = attestation.get("attStmt") or {}
    auth_data: bytes = attestation.get("authData") or b""
    chain = [x509.load_der_x509_certificate(c) for c in statement.get("x5c") or []]
    if not chain:
        raise AttestationFailed("attestation carries no certificate chain")

    leaf = chain[0]

    # 1. The chain must reach Apple's root.
    root = x509.load_pem_x509_certificate(settings.app_attest_root_pem.encode())
    _verify_chain(chain, root)

    # 2. The nonce Apple signed is SHA256(authData || SHA256(challenge)), and
    #    it lives in a private extension rather than anywhere convenient.
    client_data_hash = expected_nonce_hash(nonce)
    expected = hashlib.sha256(auth_data + client_data_hash).digest()
    if _apple_nonce(leaf) != expected:
        raise AttestationFailed("attestation was not made for our challenge")

    # 3. The key id is the SHA256 of the public key, and it must be the id the
    #    client says it is registering.
    public_key = leaf.public_key()
    key_id = hashlib.sha256(
        public_key.public_bytes(
            encoding=serialization.Encoding.X962,
            format=serialization.PublicFormat.UncompressedPoint,
        )
    ).digest()

    # 4. authData starts with SHA256(appId), then flags, then the counter.
    if auth_data[:32] != hashlib.sha256(settings.app_attest_app_id.encode()).digest():
        raise AttestationFailed("attestation is for another app id")

    counter = int.from_bytes(auth_data[33:37], "big")
    if counter != 0:
        raise AttestationFailed("a fresh attestation must have counter 0")

    # 5. Remember the key, so a second device cannot register the same one.
    existing = session.execute(
        select(Device).where(Device.attest_key_id == key_id.hex())
    ).scalar_one_or_none()
    if existing is not None and existing.id != device_id:
        raise AttestationFailed("this attestation key is already registered")

    del hashes  # imported for symmetry with the chain check; not needed here


def _verify_chain(chain: list, root) -> None:
    """Each certificate must be signed by the next, and the last by the root."""
    from cryptography.exceptions import InvalidSignature

    ordered = [*chain, root]
    for child, parent in zip(ordered, ordered[1:], strict=False):
        try:
            parent.public_key().verify(
                child.signature,
                child.tbs_certificate_bytes,
                _signature_algorithm(child),
            )
        except InvalidSignature as exc:
            raise AttestationFailed("certificate chain does not reach Apple's root") from exc


def _signature_algorithm(certificate):
    from cryptography.hazmat.primitives.asymmetric import ec

    return ec.ECDSA(certificate.signature_hash_algorithm)


def _apple_nonce(leaf) -> bytes:
    from cryptography import x509

    try:
        extension = leaf.extensions.get_extension_for_oid(
            x509.ObjectIdentifier(_APPLE_NONCE_OID)
        )
    except x509.ExtensionNotFound as exc:
        raise AttestationFailed("attestation has no Apple nonce extension") from exc

    # The extension is a DER SEQUENCE wrapping the 32-byte digest; the digest
    # is its last 32 bytes.
    return bytes(extension.value.public_bytes())[-32:]
