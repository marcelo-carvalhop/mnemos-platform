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
from datetime import UTC, datetime, timedelta

import jwt
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
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


class InviteInvalid(AuthError):
    """Invite-only mode, and the code given is not the one configured."""


class EmailNotVerified(AuthError):
    """The password is right but the address never answered the link."""


class AccountRequired(AuthError):
    """Invite-only mode refuses anonymous accounts: only someone who signed up
    with the invite code and an email address gets in."""


class AttestationRequired(AuthError):
    """§8.1 — with one free generation per lifetime, a reinstall doubles the
    entire free allocation. The device token is the only thing in the way, so
    attestation is what makes that identity survive a reinstall."""


# A confirmation link outlives a weekend away from the inbox, and no more.
VERIFICATION_TTL = timedelta(days=7)
# Asking for the link again sooner than this sends nothing: a button pressed
# five times should not be five emails.
RESEND_INTERVAL = timedelta(seconds=60)


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
    now = now or datetime.now(UTC)

    if get_settings().invite_only:
        raise AccountRequired("this server only admits invited accounts")

    if require_attestation and not attested:
        raise AttestationRequired(
            "device attestation is required before an anonymous quota is granted"
        )

    existing = session.get(Device, device_id)
    if existing is not None and existing.user_id is not None:
        # Re-registering the same device returns to the same account rather
        # than minting a second free allowance.
        return _issue_pair(session, existing.user_id, device_id, now)

    if existing is None:
        # A first launch can register twice at once (the app's bootstrap and a
        # resume racing). Both requests see no device; the second insert then
        # hits the primary key. That loser must land on the winner's account —
        # exactly what a sequential retry gets above — not answer 500, and not
        # leave behind the orphan user it created.
        try:
            with session.begin_nested():
                user = User(id=secrets.token_hex(18), email=None)
                session.add(user)
                session.flush()
                session.add(
                    Device(id=device_id, user_id=user.id, platform=platform, attested=attested)
                )
                session.flush()
        except IntegrityError:
            winner = session.execute(
                select(Device).where(Device.id == device_id)
            ).scalar_one()
            return _issue_pair(session, winner.user_id, device_id, now)
        return _issue_pair(session, user.id, device_id, now)

    user = User(id=secrets.token_hex(18), email=None)
    session.add(user)
    session.flush()
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
    now = now or datetime.now(UTC)
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
    now = now or datetime.now(UTC)
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
    # After the password, never before: refusing an unconfirmed address
    # earlier would tell anyone which addresses are registered.
    if get_settings().require_email_verification and user.email_verified_at is None:
        raise EmailNotVerified("email not confirmed")

    return _issue_pair(session, user.id, device_id, now)


@dataclass(frozen=True)
class Registration:
    """What `register` produced: a session when no confirmation is needed, or
    the raw link token to email when it is. Never both."""

    email: str
    pair: TokenPair | None
    verification_token: str | None


def invite_matches(given: str | None) -> bool:
    configured = get_settings().invite_code.strip().lower()
    if not configured:
        return True
    return hmac.compare_digest((given or "").strip().lower().encode(), configured.encode())


def _new_verification(user: User, now: datetime) -> str:
    token = secrets.token_urlsafe(32)
    user.email_verification_hash = _hash_token(token)
    user.email_verification_sent_at = now
    return token


def register(
    session: Session,
    *,
    email: str,
    password: str,
    device_id: str,
    invite_code: str | None,
    now: datetime | None = None,
) -> Registration:
    """A new account with credentials from the start.

    The anonymous-first path (§8.1) stays for open servers; an invite-only
    server admits nobody without the code and an address, so the account is
    born with both. No device row: login never needed one, and the free
    allowance that devices guard is a per-account grant here, behind the
    invite.
    """
    now = now or datetime.now(UTC)
    settings = get_settings()
    email = email.strip().lower()

    # The invite first: without it, the endpoint answers nothing about which
    # addresses exist.
    if not invite_matches(invite_code):
        raise InviteInvalid("invalid invite code")

    user = session.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if user is not None:
        if not settings.require_email_verification or user.email_verified_at is not None:
            raise AuthError("email already registered")
        # Signed up before and never confirmed — typically a lost email or a
        # mistyped password. Take the new password and send a fresh link; the
        # old link stops working, so only the latest attempt can be confirmed.
        user.password_hash = hash_password(password)
        token = _new_verification(user, now)
        session.flush()
        return Registration(email=email, pair=None, verification_token=token)

    user = User(
        id=secrets.token_hex(18),
        email=email,
        password_hash=hash_password(password),
        email_verified_at=None if settings.require_email_verification else now,
    )
    session.add(user)
    token = _new_verification(user, now) if settings.require_email_verification else None
    try:
        with session.begin_nested():
            session.flush()
    except IntegrityError as exc:
        # The same address registering twice at once.
        raise AuthError("email already registered") from exc

    if token is not None:
        return Registration(email=email, pair=None, verification_token=token)
    return Registration(
        email=email, pair=_issue_pair(session, user.id, device_id, now), verification_token=None
    )


def verify_email(
    session: Session,
    *,
    token: str,
    device_id: str | None = None,
    now: datetime | None = None,
) -> tuple[str, TokenPair | None]:
    """Confirms the address behind a link. With a `device_id`, the browser
    that opened the link is signed in too — the link is proof of the inbox,
    and the inbox is what a password reset would trust anyway."""
    now = now or datetime.now(UTC)
    user = session.execute(
        select(User).where(User.email_verification_hash == _hash_token(token))
    ).scalar_one_or_none()
    if user is None or user.email is None:
        raise AuthError("invalid or already used link")
    sent = user.email_verification_sent_at
    if sent is None or sent + VERIFICATION_TTL <= now:
        raise AuthError("link expired")

    user.email_verified_at = now
    user.email_verification_hash = None
    session.flush()
    pair = _issue_pair(session, user.id, device_id, now) if device_id else None
    return user.email, pair


def resend_verification(
    session: Session, *, email: str, now: datetime | None = None
) -> str | None:
    """A fresh link for an unconfirmed address, or None. The caller answers
    the same either way, so this does not reveal who is registered."""
    now = now or datetime.now(UTC)
    user = session.execute(
        select(User).where(User.email == email.strip().lower())
    ).scalar_one_or_none()
    if user is None or user.email_verified_at is not None:
        return None
    sent = user.email_verification_sent_at
    if sent is not None and now - sent < RESEND_INTERVAL:
        return None
    token = _new_verification(user, now)
    session.flush()
    return token


def require_member(session: Session, user_id: str) -> None:
    """Invite-only mode: an account must have an email, confirmed when
    confirmation is on. Anonymous accounts from before the switch stop here."""
    settings = get_settings()
    if not settings.invite_only:
        return
    user = session.get(User, user_id)
    if user is None or user.email is None:
        raise AccountRequired("an invited account is required")
    if settings.require_email_verification and user.email_verified_at is None:
        raise AccountRequired("an invited account is required")


def refresh(
    session: Session,
    *,
    refresh_token: str,
    now: datetime | None = None,
) -> TokenPair:
    """Rotates the refresh token, detecting reuse (§8.2)."""
    now = now or datetime.now(UTC)
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
