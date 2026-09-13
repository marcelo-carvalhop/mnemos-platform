from typing import Annotated

from fastapi import APIRouter, Header, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.deps import CurrentUser, DbSession
from app.terminal import service
from app.terminal.service import TerminalAuthError, TerminalCapacityError, TerminalScopeError
from app.sync.service import ResyncRequired

router = APIRouter(tags=["terminal"])


class RegisterTerminalRequest(BaseModel):
    device_id: str = Field(min_length=1, max_length=64)
    model: str = Field(default="Mnemos Terminal", max_length=80)
    firmware: str = Field(default="unknown", max_length=40)
    # Connection is not content selection. A freshly paired terminal therefore
    # starts with an empty desired library unless the caller explicitly says
    # otherwise.
    deck_ids: list[str] = Field(default_factory=list, max_length=32)


class RegisterTerminalResponse(BaseModel):
    device_id: str
    device_token: str
    protocol: int = 3


class TerminalSummary(BaseModel):
    device_id: str
    model: str
    firmware: str
    desired_deck_ids: list[str]
    reported_deck_ids: list[str]
    card_count: int
    max_cards: int
    connectivity: str | None = None
    wifi_ssid: str | None = None
    library_revision: int = 0
    revoked: bool
    last_seen_at: str | None = None
    last_sync_at: str | None = None


class TerminalDeckIntentRequest(BaseModel):
    deck_ids: list[str] = Field(default_factory=list, max_length=32)


class TerminalObservedRequest(BaseModel):
    reported_deck_ids: list[str] = Field(default_factory=list, max_length=32)
    card_count: int = Field(default=0, ge=0, le=100000)
    max_cards: int = Field(default=0, ge=0, le=100000)


class TerminalStatusRequest(BaseModel):
    reported_deck_ids: list[str] = Field(default_factory=list, max_length=32)
    card_count: int = Field(default=0, ge=0, le=100000)
    max_cards: int = Field(default=0, ge=0, le=100000)
    connectivity: str | None = Field(default=None, max_length=24)
    wifi_ssid: str | None = Field(default=None, max_length=32)
    library_revision: int = Field(default=0, ge=0)
    synced: bool = False


class TerminalActionResponse(BaseModel):
    device_id: str
    revoked: bool


class ReviewBatchRequest(BaseModel):
    schema: str
    reviews: list[dict] = Field(max_length=500)


def _summary(row) -> TerminalSummary:
    return TerminalSummary(
        device_id=row.device_id,
        model=row.model,
        firmware=row.firmware,
        desired_deck_ids=list(row.deck_ids or []),
        reported_deck_ids=list(row.reported_deck_ids or []),
        card_count=int(row.card_count or 0),
        max_cards=int(row.max_cards or 0),
        connectivity=row.connectivity,
        wifi_ssid=row.wifi_ssid,
        library_revision=int(row.library_revision or 0),
        revoked=row.revoked,
        last_seen_at=row.last_seen_at.isoformat() if row.last_seen_at else None,
        last_sync_at=row.last_sync_at.isoformat() if row.last_sync_at else None,
    )


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
    return [_summary(row) for row in service.list_terminals(session, user_id)]


@router.get(
    "/v1/terminals/{device_id}/summary",
    operation_id="getTerminalSummary",
    response_model=TerminalSummary,
    summary="Returns desired and last reported terminal state",
)
def terminal_summary(device_id: str, user_id: CurrentUser, session: DbSession) -> TerminalSummary:
    try:
        return _summary(service.terminal_for_user(session, user_id, device_id))
    except TerminalScopeError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.post(
    "/v1/terminals/{device_id}/decks",
    operation_id="setTerminalDeckIntent",
    response_model=TerminalSummary,
    summary="Sets the desired deck presence for a terminal",
)
def set_terminal_decks(
    device_id: str,
    body: TerminalDeckIntentRequest,
    user_id: CurrentUser,
    session: DbSession,
) -> TerminalSummary:
    try:
        row = service.update_desired_decks(session, user_id, device_id, body.deck_ids)
        return _summary(row)
    except TerminalScopeError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.post(
    "/v1/terminals/{device_id}/observed",
    operation_id="reportDirectTerminalObservation",
    response_model=TerminalSummary,
    summary="Records state observed by the authenticated app after direct BLE sync",
)
def observe_terminal(
    device_id: str,
    body: TerminalObservedRequest,
    user_id: CurrentUser,
    session: DbSession,
) -> TerminalSummary:
    try:
        return _summary(
            service.observe_direct_sync(
                session,
                user_id,
                device_id,
                reported_deck_ids=body.reported_deck_ids,
                card_count=body.card_count,
                max_cards=body.max_cards,
            )
        )
    except TerminalScopeError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


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
    schema: Annotated[str, Query()] = "mnemos.sync/v2",
) -> dict:
    if schema != "mnemos.sync/v2":
        raise HTTPException(
            status_code=422,
            detail="unsupported terminal snapshot schema",
        )

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
    if body.schema != "mnemos.review-batch/v2":
        raise HTTPException(status_code=422, detail="unsupported review batch schema")
    credential = _terminal_credential(session, authorization)
    try:
        return service.ingest_reviews(session, credential, body.reviews)
    except TerminalScopeError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except (ValueError, KeyError, TypeError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.get(
    "/v1/terminal/reviews",
    operation_id="pullTerminalReviews",
    response_model=dict,
    summary="Returns review deltas visible to a dedicated terminal",
)
def pull_terminal_reviews(
    session: DbSession,
    authorization: Annotated[str | None, Header()] = None,
    since: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=2000)] = 500,
) -> dict:
    credential = _terminal_credential(
        session,
        authorization,
    )

    try:
        return service.pull_reviews(
            session,
            credential,
            since_seq=since,
            limit=limit,
        )
    except ResyncRequired as exc:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail=str(exc),
        ) from exc


@router.get(
    "/v1/terminal/progress-resets",
    operation_id="pullTerminalProgressResets",
    response_model=dict,
    summary="Returns schedule-reset deltas visible to a dedicated terminal",
)
def pull_terminal_progress_resets(
    session: DbSession,
    authorization: Annotated[str | None, Header()] = None,
    since: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=2000)] = 500,
) -> dict:
    credential = _terminal_credential(
        session,
        authorization,
    )

    try:
        return service.pull_progress_resets(
            session,
            credential,
            since_seq=since,
            limit=limit,
        )
    except ResyncRequired as exc:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail=str(exc),
        ) from exc


@router.get(
    "/v1/terminal/settings",
    operation_id="pullTerminalUserSettings",
    response_model=dict,
    summary="Returns pedagogical settings visible to a dedicated terminal",
)
def pull_terminal_user_settings(
    session: DbSession,
    authorization: Annotated[str | None, Header()] = None,
    since: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=2000)] = 500,
) -> dict:
    credential = _terminal_credential(
        session,
        authorization,
    )

    try:
        return service.pull_user_settings(
            session,
            credential,
            since_seq=since,
            limit=limit,
        )
    except ResyncRequired as exc:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail=str(exc),
        ) from exc


@router.post(
    "/v1/terminal/status",
    operation_id="reportTerminalStatus",
    response_model=dict,
    summary="Stores last physical state reported by a terminal",
)
def terminal_status(
    body: TerminalStatusRequest,
    session: DbSession,
    authorization: Annotated[str | None, Header()] = None,
) -> dict:
    credential = _terminal_credential(session, authorization)
    row = service.report_status(
        session,
        credential,
        reported_deck_ids=body.reported_deck_ids,
        card_count=body.card_count,
        max_cards=body.max_cards,
        connectivity=body.connectivity,
        wifi_ssid=body.wifi_ssid,
        library_revision=body.library_revision,
        synced=body.synced,
    )
    return {"ok": True, "device_id": row.device_id}
