"""Auth endpoints (§8.1, §8.2).

FastAPI stays in this file; the rules live in `service.py` (§4.2). Every route
declares an explicit `operation_id` and a response model, or the generated Dart
client is unusable (§4.3).
"""

from typing import Literal

from fastapi import APIRouter, BackgroundTasks, HTTPException, status
from pydantic import BaseModel, EmailStr, Field

from app.auth import attestation, mail, service
from app.auth.service import (
    AccountRequired,
    AttestationRequired,
    AuthError,
    EmailNotVerified,
    InviteInvalid,
    TokenReuseDetected,
)
from app.config import get_settings
from app.contract import ErrorCode
from app.deps import CurrentUser, DbSession

router = APIRouter(prefix="/v1/auth", tags=["auth"])


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    user_id: str
    expires_in: int
    token_type: str = "Bearer"


class ChallengeRequest(BaseModel):
    device_id: str = Field(description="Client-generated UUIDv7")


class ChallengeResponse(BaseModel):
    nonce: str
    expires_in: int


class DeviceRequest(BaseModel):
    device_id: str = Field(description="Client-generated UUIDv7")
    platform: str = Field(description="ios | android")
    attestation: str | None = Field(
        default=None,
        description="App Attest / Play Integrity assertion. Required in v1 (§8.1).",
    )
    nonce: str | None = Field(
        default=None,
        description="The challenge the assertion was made over. Single use.",
    )


class SignupRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)
    device_id: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    device_id: str


class RefreshRequest(BaseModel):
    refresh_token: str


class AuthOptionsResponse(BaseModel):
    invite_required: bool
    email_verification_required: bool


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)
    device_id: str
    invite_code: str | None = Field(
        default=None, description="Required when the server is invite-only."
    )


class RegisterResponse(BaseModel):
    status: Literal["verification_sent", "signed_in"]
    email: str
    tokens: TokenResponse | None = None


class VerifyEmailRequest(BaseModel):
    token: str
    device_id: str | None = Field(
        default=None, description="Signs this client in once the address is confirmed."
    )


class VerifyEmailResponse(BaseModel):
    email: str
    tokens: TokenResponse | None = None


class ResendVerificationRequest(BaseModel):
    email: EmailStr


class ResendVerificationResponse(BaseModel):
    status: Literal["sent_if_pending"] = "sent_if_pending"


def _as_response(pair: service.TokenPair) -> TokenResponse:
    return TokenResponse(
        access_token=pair.access_token,
        refresh_token=pair.refresh_token,
        user_id=pair.user_id,
        expires_in=pair.expires_in,
    )


@router.post(
    "/challenge",
    operation_id="createAttestationChallenge",
    response_model=ChallengeResponse,
    summary="A single-use nonce to attest over",
)
def create_challenge(body: ChallengeRequest, session: DbSession) -> ChallengeResponse:
    """§8.1 — the first half of registering.

    Unauthenticated, because it happens before any account exists. It hands
    out nothing but a random string, and the string is worthless without an
    attestation made over it.
    """
    nonce = attestation.issue_challenge(session, body.device_id)
    session.commit()
    return ChallengeResponse(
        nonce=nonce, expires_in=int(attestation.CHALLENGE_TTL.total_seconds())
    )


@router.post(
    "/device",
    operation_id="registerDevice",
    response_model=TokenResponse,
    summary="First launch — anonymous account bound to this device",
)
def register_device(body: DeviceRequest, session: DbSession) -> TokenResponse:
    """§8.1 — creates a real user with no credentials.

    Quota attaches here, before any account exists, which is what stops a
    reinstall from granting a second free generation.
    """
    settings = get_settings()

    # The assertion is checked before any account is created: a device that
    # cannot prove itself must not leave a row behind, or the next attempt
    # finds one and skips the check.
    if settings.require_attestation:
        if not body.attestation or not body.nonce:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="attestation and nonce are required (§8.1)",
            )
        try:
            attestation.verify(
                session,
                device_id=body.device_id,
                platform=body.platform,
                token=body.attestation,
                nonce=body.nonce,
            )
        except attestation.AttestationFailed as exc:
            # The challenge is spent either way — a failed attempt must not
            # leave a reusable nonce behind.
            session.commit()
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail=str(exc)
            ) from exc

    try:
        pair = service.register_device(
            session,
            device_id=body.device_id,
            platform=body.platform,
            attested=settings.require_attestation,
            require_attestation=settings.require_attestation,
        )
    except AccountRequired as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=ErrorCode.ACCOUNT_REQUIRED.value
        ) from exc
    except AttestationRequired as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc)) from exc
    session.commit()
    return _as_response(pair)


@router.get(
    "/options",
    operation_id="authOptions",
    response_model=AuthOptionsResponse,
    summary="What signing up asks for on this server",
)
def options() -> AuthOptionsResponse:
    """Lets a client show the invite field only where it is needed. Says
    nothing about the code itself."""
    settings = get_settings()
    return AuthOptionsResponse(
        invite_required=settings.invite_only,
        email_verification_required=settings.require_email_verification,
    )


@router.post(
    "/register",
    operation_id="register",
    response_model=RegisterResponse,
    summary="Create an account with email and password",
)
def register(
    body: RegisterRequest, session: DbSession, background: BackgroundTasks
) -> RegisterResponse:
    """The invite-only way in. With confirmation on, nothing is signed in
    until the emailed link is opened; the response says so."""
    try:
        result = service.register(
            session,
            email=body.email,
            password=body.password,
            device_id=body.device_id,
            invite_code=body.invite_code,
        )
    except InviteInvalid as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=ErrorCode.INVITE_INVALID.value
        ) from exc
    except AuthError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    session.commit()

    if result.verification_token is not None:
        # After the commit and after the response: the email carries a token
        # that must already be valid, and SMTP latency is not the client's.
        background.add_task(mail.send_verification, result.email, result.verification_token)
        return RegisterResponse(status="verification_sent", email=result.email)
    assert result.pair is not None
    return RegisterResponse(
        status="signed_in", email=result.email, tokens=_as_response(result.pair)
    )


@router.post(
    "/verify-email",
    operation_id="verifyEmail",
    response_model=VerifyEmailResponse,
    summary="Confirm the address from the emailed link",
)
def verify_email(body: VerifyEmailRequest, session: DbSession) -> VerifyEmailResponse:
    try:
        email, pair = service.verify_email(
            session, token=body.token, device_id=body.device_id
        )
    except AuthError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    session.commit()
    return VerifyEmailResponse(email=email, tokens=_as_response(pair) if pair else None)


@router.post(
    "/resend-verification",
    operation_id="resendVerification",
    response_model=ResendVerificationResponse,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Send the confirmation link again",
)
def resend_verification(
    body: ResendVerificationRequest, session: DbSession, background: BackgroundTasks
) -> ResendVerificationResponse:
    """The same answer whether or not the address is registered or pending."""
    token = service.resend_verification(session, email=body.email)
    session.commit()
    if token is not None:
        background.add_task(mail.send_verification, str(body.email).strip().lower(), token)
    return ResendVerificationResponse()


@router.post(
    "/signup",
    operation_id="signup",
    response_model=TokenResponse,
    summary="Give the current anonymous account credentials",
)
def signup(body: SignupRequest, user_id: CurrentUser, session: DbSession) -> TokenResponse:
    """Nothing moves: the rows already belong to this user (§8.1)."""
    try:
        pair = service.attach_credentials(
            session,
            user_id=user_id,
            email=body.email,
            password=body.password,
            device_id=body.device_id,
        )
    except AuthError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    session.commit()
    return _as_response(pair)


@router.post(
    "/login",
    operation_id="login",
    response_model=TokenResponse,
    summary="Sign in from another device",
)
def login(body: LoginRequest, session: DbSession) -> TokenResponse:
    try:
        pair = service.login(
            session, email=body.email, password=body.password, device_id=body.device_id
        )
    except EmailNotVerified as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=ErrorCode.EMAIL_NOT_VERIFIED.value
        ) from exc
    except AuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc)
        ) from exc
    session.commit()
    return _as_response(pair)


@router.post(
    "/refresh",
    operation_id="refreshToken",
    response_model=TokenResponse,
    summary="Rotate the refresh token",
)
def refresh(body: RefreshRequest, session: DbSession) -> TokenResponse:
    try:
        pair = service.refresh(session, refresh_token=body.refresh_token)
    except TokenReuseDetected as exc:
        session.commit()  # the revocation must persist
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc)) from exc
    except AuthError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc)) from exc
    session.commit()
    return _as_response(pair)
