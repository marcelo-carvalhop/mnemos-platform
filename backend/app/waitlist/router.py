"""O "Avise-me" do plano com IA, na landing.

Sem conta: qualquer um deixa o e-mail. A resposta é a mesma para um e-mail
novo e para um repetido, ou o formulário viraria um jeito de descobrir quem já
pediu. Um teto global por minuto e por dia segura um script que tente encher
a tabela; quem passa dele recebe 429 e tenta de novo depois.
"""

from typing import Literal

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy.dialects.postgresql import insert

from app.chat.limits import RateLimited, SlidingWindowLimiter
from app.deps import DbSession
from app.models import WaitlistEntry

router = APIRouter(prefix="/v1/waitlist", tags=["waitlist"])

_limiter = SlidingWindowLimiter()
PER_MINUTE = 30
PER_DAY = 2000


class WaitlistRequest(BaseModel):
    email: EmailStr
    plan: Literal["ai"] = "ai"


class WaitlistResponse(BaseModel):
    status: Literal["ok"] = "ok"


@router.post(
    "",
    operation_id="joinWaitlist",
    response_model=WaitlistResponse,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Ask to be told when a plan opens",
)
def join(body: WaitlistRequest, session: DbSession) -> WaitlistResponse:
    try:
        _limiter.hit("waitlist", per_minute=PER_MINUTE, per_day=PER_DAY)
    except RateLimited as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="rate_limited",
            headers={"Retry-After": str(exc.retry_after)},
        ) from exc

    email = str(body.email).strip().lower()
    session.execute(
        insert(WaitlistEntry)
        .values(email=email, plan=body.plan)
        .on_conflict_do_nothing(index_elements=["email"])
    )
    session.commit()
    return WaitlistResponse()
