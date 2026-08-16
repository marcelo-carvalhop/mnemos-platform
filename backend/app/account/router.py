"""Account endpoints (§8.4).

Export and deletion are LGPD rights, so they are here rather than behind a
support email.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

from app.account import service
from app.deps import CurrentUser, DbSession

router = APIRouter(prefix="/v1/account", tags=["account"])


class ExportResponse(BaseModel):
    exported_at: str
    format_version: int
    decks: list[dict[str, Any]]
    cards: list[dict[str, Any]]
    card_flags: list[dict[str, Any]]
    reviews: list[dict[str, Any]]
    progress_resets: list[dict[str, Any]]
    goal_history: list[dict[str, Any]]
    user_settings: list[dict[str, Any]]


class DeleteRequest(BaseModel):
    # Typed rather than tapped. Deletion is not undoable and the review log is
    # years of someone's work; a confirmation that can be produced by a
    # mis-tap is not a confirmation.
    confirm: str = Field(description='Must be exactly "APAGAR"')


class DeleteResponse(BaseModel):
    deleted: dict[str, int]


@router.get(
    "/export",
    operation_id="exportAccount",
    response_model=ExportResponse,
    summary="Everything this account holds, as JSON",
)
def export_account(user_id: CurrentUser, session: DbSession) -> ExportResponse:
    """§8.4 — and the honest answer to "what happens to my years of study if I
    stop paying"."""
    return ExportResponse(**service.export(session, user_id))


@router.post(
    "/delete",
    operation_id="deleteAccount",
    response_model=DeleteResponse,
    summary="Delete the account and everything it holds",
)
def delete_account(
    body: DeleteRequest, user_id: CurrentUser, session: DbSession
) -> DeleteResponse:
    if body.confirm != "APAGAR":
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            'confirmation must be exactly "APAGAR"',
        )

    removed = service.delete_account(session, user_id)
    session.commit()
    return DeleteResponse(deleted=removed)
