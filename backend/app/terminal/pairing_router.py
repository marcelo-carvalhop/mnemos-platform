"""Pairing a terminal by a code typed on the site. Rules in `pairing.py`."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, HTTPException, Response, status
from pydantic import BaseModel, Field

from app.chat.limits import RateLimited, SlidingWindowLimiter
from app.config import get_settings
from app.deps import CurrentUser, DbSession
from app.terminal import pairing

router = APIRouter(tags=["terminal"])

# The start is unauthenticated (the terminal has no account yet), so it gets
# a global ceiling. The claim is per account: it is the side that guesses.
_starts = SlidingWindowLimiter()
_claims = SlidingWindowLimiter()


def _limit(limiter: SlidingWindowLimiter, key: str, per_minute: int, per_day: int) -> None:
    try:
        limiter.hit(key, per_minute=per_minute, per_day=per_day)
    except RateLimited as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="rate_limited",
            headers={"Retry-After": str(exc.retry_after)},
        ) from exc


class PairingStartRequest(BaseModel):
    device_id: str = Field(min_length=1, max_length=64)
    model: str = Field(default="Mnemos Terminal", max_length=80)
    firmware: str = Field(default="unknown", max_length=40)
    # The credential the terminal holds now, if any. Proves it is the terminal
    # asking, so the code may move it from another account.
    current_token: str | None = Field(default=None, max_length=128)


class PairingStartResponse(BaseModel):
    code: str
    poll_token: str
    expires_in: int
    interval: int
    verify_url: str


class PairingPollRequest(BaseModel):
    poll_token: str = Field(min_length=16, max_length=128)


class PairingPollResponse(BaseModel):
    status: Literal["pending", "claimed", "expired"]
    device_id: str | None = None
    device_token: str | None = None


class PairingClaimRequest(BaseModel):
    code: str = Field(min_length=4, max_length=16)
    deck_ids: list[str] = Field(default_factory=list, max_length=32)


class PairingClaimResponse(BaseModel):
    device_id: str
    model: str


@router.post(
    "/v1/terminal/pairing/start",
    operation_id="startTerminalPairing",
    response_model=PairingStartResponse,
    summary="A terminal asks for a code to show",
)
def start(body: PairingStartRequest, session: DbSession) -> PairingStartResponse:
    _limit(_starts, "global", per_minute=30, per_day=2000)
    started = pairing.start(
        session,
        device_id=body.device_id,
        model=body.model,
        firmware=body.firmware,
        current_token=body.current_token,
    )
    session.commit()
    base = get_settings().public_web_url.rstrip("/")
    return PairingStartResponse(
        code=started.code,
        poll_token=started.poll_token,
        expires_in=started.expires_in,
        interval=started.interval,
        verify_url=f"{base}/dispositivo?codigo={started.code}",
    )


@router.post(
    "/v1/terminal/pairing/poll",
    operation_id="pollTerminalPairing",
    response_model=PairingPollResponse,
    summary="The terminal asks whether its code was claimed",
)
def poll(body: PairingPollRequest, session: DbSession, response: Response) -> PairingPollResponse:
    try:
        result = pairing.poll(session, body.poll_token)
    except pairing.PairingNotFound as exc:
        raise HTTPException(status_code=404, detail="pairing_not_found") from exc
    except pairing.PairingConflict as exc:
        session.rollback()
        raise HTTPException(status_code=409, detail="terminal_owned_elsewhere") from exc
    session.commit()
    if result.status == "pending":
        response.headers["Retry-After"] = str(pairing.POLL_INTERVAL_SECONDS)
    return PairingPollResponse(
        status=result.status, device_id=result.device_id, device_token=result.device_token
    )


@router.post(
    "/v1/terminals/pairing/claim",
    operation_id="claimTerminalPairing",
    response_model=PairingClaimResponse,
    summary="Someone signed in claims the code a terminal shows",
)
def claim(
    body: PairingClaimRequest, user_id: CurrentUser, session: DbSession
) -> PairingClaimResponse:
    _limit(_claims, user_id, per_minute=10, per_day=100)
    try:
        row = pairing.claim(session, user_id, body.code, body.deck_ids)
    except pairing.PairingNotFound as exc:
        raise HTTPException(status_code=404, detail="pairing_not_found") from exc
    except pairing.PairingConflict as exc:
        raise HTTPException(status_code=409, detail="terminal_owned_elsewhere") from exc
    session.commit()
    return PairingClaimResponse(device_id=row.device_id, model=row.model)
