"""Quota endpoints (§5.13, §7.7)."""

from datetime import UTC, datetime

from fastapi import APIRouter
from pydantic import BaseModel

from app.deps import CurrentUser, DbSession
from app.quota import service

router = APIRouter(prefix="/v1/quota", tags=["quota"])


class QuotaResponse(BaseModel):
    remaining: int
    limit: int
    period_key: str
    plan: str


@router.get(
    "/",
    operation_id="getQuota",
    response_model=QuotaResponse,
    summary="Generations left",
)
def get_quota(user_id: CurrentUser, session: DbSession) -> QuotaResponse:
    """What the client's indicator mirrors. The server stays the authority
    (§7.7): this is a cache, and enforcement happens at reservation.

    `plan` is "beta" while generation is unlimited for accounts: clients show
    that instead of a count, since the ceiling is a safety net, not a number
    anyone is meant to see."""
    plan = service.plan_for(session, user_id)
    now = datetime.now(UTC)
    return QuotaResponse(
        remaining=service.remaining(session, user_id, plan=plan, at=now),
        limit=service.limit_for(plan),
        period_key=service.period_key_for(plan, now, "America/Sao_Paulo"),
        plan=plan,
    )
