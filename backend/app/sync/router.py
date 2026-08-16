"""Sync endpoints (§6).

The `user_id` always comes from the token, never from the payload (§5.5).
"""

from typing import Any

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.deps import CurrentUser, DbSession, Identity
from app.sync import service
from app.sync.service import OwnershipError, ResyncRequired

router = APIRouter(prefix="/v1/sync", tags=["sync"])


class PushRequest(BaseModel):
    table: str = Field(description="decks | cards | card_flags | user_settings | reviews | progress_resets | goal_history")
    rows: list[dict[str, Any]]
    idempotency_key: str | None = Field(
        default=None,
        description=(
            "Accepted and deliberately not used. Idempotency here is "
            "structural, not key-based: history unions with ON CONFLICT DO "
            "NOTHING and entities resolve by last-writer-wins, so replaying a "
            "chunk changes nothing (§6.4). The client derives a key from the "
            "chunk's content and sends it so a future server-side dedupe has "
            "one to work with; declaring the field keeps it visible in the "
            "OpenAPI schema instead of silently dropped."
        ),
    )


class PushResponse(BaseModel):
    applied: int
    skipped_stale: int
    high_water: int
    # Row key → server_seq. Without it the client cannot mark a row synced,
    # and `server_seq IS NULL` keeps it in the outbox forever (§6.2).
    assigned: dict[str, int] = {}


class PullResponse(BaseModel):
    table: str
    rows: list[dict[str, Any]]
    cursor: int
    has_more: bool


@router.post(
    "/push",
    operation_id="pushChanges",
    response_model=PushResponse,
    summary="Upload a chunk of local changes",
)
def push(body: PushRequest, user_id: CurrentUser, session: DbSession) -> PushResponse:
    """Idempotent (§6.4): replaying a chunk after a timeout changes nothing."""
    try:
        result = service.push(session, user_id, body.table, body.rows)
    except OwnershipError as exc:
        # Not 404: the row exists, it just is not theirs. Saying so plainly is
        # fine — they supplied the id.
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    session.commit()
    return PushResponse(
        applied=result.applied,
        skipped_stale=result.skipped_stale,
        high_water=result.high_water,
        assigned=result.assigned,
    )


@router.get(
    "/pull",
    operation_id="pullChanges",
    response_model=PullResponse,
    summary="Keyset delta since a cursor",
)
def pull(
    user_id: CurrentUser,
    session: DbSession,
    table: str = Query(description="Table to pull"),
    since: int = Query(default=0, ge=0, description="server_seq cursor; 0 bootstraps"),
    limit: int = Query(default=500, ge=1, le=2000),
) -> PullResponse:
    try:
        rows, cursor = service.pull(session, user_id, table, since_seq=since, limit=limit)
    except ResyncRequired as exc:
        # §6.3 — the client discards its mirror and pulls from zero. A distinct
        # status, because it is not an error the user can act on and not a
        # retry the client should make with the same cursor.
        raise HTTPException(status_code=status.HTTP_410_GONE, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return PullResponse(
        table=table,
        rows=rows,
        cursor=cursor,
        has_more=len(rows) == limit,
    )


@router.get(
    "/tables",
    operation_id="listSyncTables",
    response_model=list[str],
    summary="Tables this protocol version syncs",
)
def list_tables(identity: Identity) -> list[str]:
    """Lets a client detect a protocol skew before it starts pushing."""
    return sorted(service.TABLES)
