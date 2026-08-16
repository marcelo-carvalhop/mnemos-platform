from typing import Annotated

from fastapi import APIRouter, Header, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.deps import CurrentUser, DbSession
from app.terminal import service
from app.terminal.service import TerminalAuthError, TerminalCapacityError, TerminalScopeError

router = APIRouter(tags=["terminal"])


class RegisterTerminalRequest(BaseModel):
    device_id: str = Field(min_length=1, max_length=64)
    model: str = Field(default="Mnemos Terminal", max_length=80)
    firmware: str = Field(default="unknown", max_length=40)
    deck_ids: list[str] = Field(min_length=1, max_length=32)


class RegisterTerminalResponse(BaseModel):
    device_id: str
    device_token: str
    protocol: int = 2


class TerminalSummary(BaseModel):
    device_id: str
    model: str
    firmware: str
    deck_ids: list[str]
    revoked: bool
    last_seen_at: str | None = None


class TerminalActionResponse(BaseModel):
    device_id: str
    revoked: bool


class ReviewBatchRequest(BaseModel):
    schema: str
    reviews: list[dict] = Field(max_length=500)


def _terminal_credential(session, authorization: str | None):
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="missing terminal bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        return service.authenticate_terminal(session, authorization.split(" ", 1)[1].strip())
    except TerminalAuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


@router.post(
    "/v1/terminals/register",
    operation_id="registerTerminal",
    response_model=RegisterTerminalResponse,
    summary="Registers or rotates a dedicated terminal credential",
)
def register_terminal(
    body: RegisterTerminalRequest,
    user_id: CurrentUser,
    session: DbSession,
) -> RegisterTerminalResponse:
    try:
        token = service.register_terminal(
            session, user_id, body.device_id, body.model, body.firmware, body.deck_ids
        )
    except TerminalAuthError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except TerminalScopeError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return RegisterTerminalResponse(device_id=body.device_id, device_token=token)


@router.get(
    "/v1/terminals",
    operation_id="listTerminals",
    response_model=list[TerminalSummary],
    summary="Lists dedicated terminals registered to the account",
)
def list_terminals(user_id: CurrentUser, session: DbSession) -> list[TerminalSummary]:
    return [
        TerminalSummary(
            device_id=row.device_id,
            model=row.model,
            firmware=row.firmware,
            deck_ids=list(row.deck_ids or []),
            revoked=row.revoked,
            last_seen_at=row.last_seen_at.isoformat() if row.last_seen_at else None,
        )
        for row in service.list_terminals(session, user_id)
    ]


@router.post(
    "/v1/terminals/{device_id}/revoke",
    operation_id="revokeTerminal",
    response_model=TerminalActionResponse,
    summary="Revokes one dedicated terminal credential",
)
def revoke_terminal(
    device_id: str,
    user_id: CurrentUser,
    session: DbSession,
) -> TerminalActionResponse:
    try:
        service.revoke_terminal(session, user_id, device_id)
    except TerminalScopeError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return TerminalActionResponse(device_id=device_id, revoked=True)


@router.get(
    "/v1/terminal/snapshot",
    operation_id="getTerminalSnapshot",
    response_model=dict,
    summary="Returns a canonical Mnemos full snapshot for a terminal",
)
def terminal_snapshot(
    session: DbSession,
    authorization: Annotated[str | None, Header()] = None,
    limit: Annotated[int, Query(ge=1, le=256)] = 48,
) -> dict:
    credential = _terminal_credential(session, authorization)
    try:
        return service.snapshot(session, credential, limit=limit)
    except TerminalCapacityError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post(
    "/v1/terminal/reviews",
    operation_id="pushTerminalReviews",
    response_model=dict,
    summary="Accepts canonical review events emitted by a terminal",
)
def terminal_reviews(
    body: ReviewBatchRequest,
    session: DbSession,
    authorization: Annotated[str | None, Header()] = None,
) -> dict:
    if body.schema != "mnemos.review-batch/v1":
        raise HTTPException(status_code=422, detail="unsupported review batch schema")
    credential = _terminal_credential(session, authorization)
    try:
        return service.ingest_reviews(session, credential, body.reviews)
    except TerminalScopeError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except (ValueError, KeyError, TypeError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
