"""Quota endpoints (§5.13, §7.7)."""

from fastapi import APIRouter
from pydantic import BaseModel

from app.contract import FREE_GENERATIONS_LIFETIME
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
    (§7.7): this is a cache, and enforcement happens at reservation."""
    plan = "free"
    return QuotaResponse(
        remaining=service.remaining(session, user_id, plan=plan),
        limit=FREE_GENERATIONS_LIFETIME,
        period_key=service.period_key_for(plan, __import__("datetime").datetime.now(
            __import__("datetime").timezone.utc), "America/Sao_Paulo"),
        plan=plan,
    )
