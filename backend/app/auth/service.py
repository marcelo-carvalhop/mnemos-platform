"""Authentication (§8.1, §8.2). No FastAPI here (§4.2).

The shape follows one decision that removes most of the usual complexity:
**the anonymous period creates a real user row with no credentials.** §8.1 says
account creation comes after the first generation, and the naive reading is
that anonymous data lives somewhere else and is migrated later. It does not
have to. Every row already carries `user_id` (§5.5), so if the anonymous
device owns a real user from first launch, "signup" is that user gaining an
email and a password — zero rows move, and there is no migration to get wrong.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import jwt
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models import Device, RefreshToken, User
from app.quota import service as quota

# §8.2 — "long-lived enough that a week in the subway changes nothing".
# The whole app works offline; expiring the session because sync could not
# reach the server is the worst possible bug in an offline-first product.
ACCESS_TOKEN_TTL = timedelta(days=30)
REFRESH_TOKEN_TTL = timedelta(days=365)

_ALGORITHM = "HS256"
_PBKDF2_ROUNDS = 600_000


class AuthError(Exception):
    """Credentials rejected."""


class TokenReuseDetected(AuthError):
    """A rotated refresh token was presented again (§8.2).

    Either the token leaked or a client is retrying blindly. Both are handled
    the same way: every token in that family is revoked, because we cannot tell
    the attacker from the legitimate holder.
    """


class AttestationRequired(AuthError):
    """§8.1 — with one free generation per lifetime, a reinstall doubles the
    entire free allocation. The device token is the only thing in the way, so
    attestation is what makes that identity survive a reinstall."""


@dataclass(frozen=True)
class TokenPair:
    access_token: str
    refresh_token: str
    user_id: str
    expires_in: int


def _secret() -> str:
    settings = get_settings()
    secret = settings.jwt_secret
    if not secret:
        raise RuntimeError("JWT_SECRET is not configured")
    return secret


def hash_password(password: str, *, salt: bytes | None = None) -> str:
    """PBKDF2-SHA256. Stdlib, so no extra dependency for one call site."""
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _PBKDF2_ROUNDS)
    return f"pbkdf2_sha256${_PBKDF2_ROUNDS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, encoded: str) -> bool:
    try:
        _, rounds, salt_hex, digest_hex = encoded.split("$")
        digest = hashlib.pbkdf2_hmac(
            "sha256", password.encode(), bytes.fromhex(salt_hex), int(rounds)
        )
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(digest.hex(), digest_hex)


def _hash_token(token: str) -> str:
    """Refresh tokens are stored hashed (§8.2).

    Plain SHA-256 rather than a password hash: these are 256 bits of CSPRNG
    output, so there is no dictionary to defend against and the cost of a slow
    hash would buy nothing.
    """
    return hashlib.sha256(token.encode()).hexdigest()


def _issue_access_token(user_id: str, device_id: str, now: datetime) -> str:
    payload = {
        "sub": user_id,
        "did": device_id,
        "iat": int(now.timestamp()),
        "exp": int((now + ACCESS_TOKEN_TTL).timestamp()),
    }
    return jwt.encode(payload, _secret(), algorithm=_ALGORITHM)


def verify_access_token(token: str) -> tuple[str, str]:
    """Returns `(user_id, device_id)` or raises."""
    try:
        payload = jwt.decode(token, _secret(), algorithms=[_ALGORITHM])
    except jwt.ExpiredSignatureError as exc:
        raise AuthError("access token expired") from exc
    except jwt.InvalidTokenError as exc:
        raise AuthError("invalid access token") from exc
    return payload["sub"], payload["did"]


def _issue_pair(
    session: Session,
    user_id: str,
    device_id: str,
    now: datetime,
    *,
    family_id: str | None = None,
) -> TokenPair:
    raw_refresh = secrets.token_urlsafe(32)
    session.add(
        RefreshToken(
            id=secrets.token_hex(16),
            user_id=user_id,
            device_id=device_id,
            family_id=family_id or secrets.token_hex(16),
            token_hash=_hash_token(raw_refresh),
            issued_at=now,
            expires_at=now + REFRESH_TOKEN_TTL,
            used_at=None,
            revoked=False,
        )
    )
    session.flush()
    return TokenPair(
        access_token=_issue_access_token(user_id, device_id, now),
        refresh_token=raw_refresh,
        user_id=user_id,
        expires_in=int(ACCESS_TOKEN_TTL.total_seconds()),
    )


def register_device(
    session: Session,
    *,
    device_id: str,
    platform: str,
    attested: bool,
    now: datetime | None = None,
    require_attestation: bool = True,
) -> TokenPair:
    """First launch: a real user with no credentials, plus the device (§8.1)."""
    now = now or datetime.now(timezone.utc)

    if require_attestation and not attested:
        raise AttestationRequired(
            "device attestation is required before an anonymous quota is granted"
        )

    existing = session.get(Device, device_id)
    if existing is not None and existing.user_id is not None:
        # Re-registering the same device returns to the same account rather
        # than minting a second free allowance.
        return _issue_pair(session, existing.user_id, device_id, now)

    user = User(id=secrets.token_hex(18), email=None)
    session.add(user)
    session.flush()

    if existing is None:
        session.add(
            Device(id=device_id, user_id=user.id, platform=platform, attested=attested)
        )
    else:
        existing.user_id = user.id
        existing.attested = attested
    session.flush()

    # §8.4 against §8.1. A device whose free generation was already spent
    # carries that across account deletion, so deleting and registering again
    # does not mint a second one — the same attack a reinstall is, with an
    # extra step. The new account starts with its lifetime allowance used.
    if existing is not None and existing.free_grant_spent:
        quota.mark_lifetime_spent(session, user.id)

    return _issue_pair(session, user.id, device_id, now)


def attach_credentials(
    session: Session,
    *,
    user_id: str,
    email: str,
    password: str,
    device_id: str,
    now: datetime | None = None,
) -> TokenPair:
    """Signup for a device that already has an anonymous account (§8.1).

    Nothing moves: the rows already belong to this `user_id`. The account
    simply gains a way to sign in from somewhere else.
    """
    now = now or datetime.now(timezone.utc)
    email = email.strip().lower()

    taken = session.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if taken is not None:
        raise AuthError("email already registered")

    user = session.get(User, user_id)
    if user is None:
        raise AuthError("unknown user")
    if user.email is not None:
        raise AuthError("this account already has credentials")

    user.email = email
    user.password_hash = hash_password(password)
    session.flush()

    return _issue_pair(session, user.id, device_id, now)


def login(
    session: Session,
    *,
    email: str,
    password: str,
    device_id: str,
    now: datetime | None = None,
) -> TokenPair:
    now = now or datetime.now(timezone.utc)
    user = session.execute(
        select(User).where(User.email == email.strip().lower())
    ).scalar_one_or_none()

    # Same error and comparable work whether the address exists or not, so the
    # endpoint does not answer "is this email registered?".
    if user is None or user.password_hash is None:
        hash_password(password)
        raise AuthError("invalid credentials")
    if not verify_password(password, user.password_hash):
        raise AuthError("invalid credentials")

    return _issue_pair(session, user.id, device_id, now)


def refresh(
    session: Session,
    *,
    refresh_token: str,
    now: datetime | None = None,
) -> TokenPair:
    """Rotates the refresh token, detecting reuse (§8.2)."""
    now = now or datetime.now(timezone.utc)
    token_hash = _hash_token(refresh_token)

    record = session.execute(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    ).scalar_one_or_none()

    if record is None:
        raise AuthError("unknown refresh token")

    if record.used_at is not None or record.revoked:
        # Already rotated. Either it leaked or a client replayed it; we cannot
        # tell, so the whole family goes.
        session.execute(
            RefreshToken.__table__.update()
            .where(RefreshToken.family_id == record.family_id)
            .values(revoked=True)
        )
        session.flush()
        raise TokenReuseDetected("refresh token reuse detected; family revoked")

    if record.expires_at <= now:
        raise AuthError("refresh token expired")

    record.used_at = now
    session.flush()

    return _issue_pair(
        session, record.user_id, record.device_id, now, family_id=record.family_id
    )
