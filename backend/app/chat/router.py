"""The study chat over HTTP.

    POST /v1/chat → one assistant reply to the conversation the client holds

Nothing is stored: the conversation lives in the client and is sent whole on
every turn, capped in size. Each failure the screen has to tell apart has its
own code in `detail`:

    403 chat_account_required   the account has no email
    422                         the conversation or the context is malformed
    429 chat_rate_limited       too many in the last minute (Retry-After)
    429 chat_daily_limit        the daily cap is spent (Retry-After)
    502 chat_model_unavailable  the model did not answer
    503 chat_not_configured     this server has no model key
"""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field, field_validator, model_validator

from app.chat import limits
from app.chat import model as chat_model
from app.config import get_settings
from app.deps import CurrentUser, DbSession
from app.models import User

router = APIRouter(prefix="/v1/chat", tags=["chat"])

MAX_MESSAGES = 20
MAX_MESSAGE_CHARS = 2000
MAX_CARD_FIELD_CHARS = 2000
MAX_DECK_NAME_CHARS = 200
MAX_DECKS = 30


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=MAX_MESSAGE_CHARS)

    @field_validator("content")
    @classmethod
    def not_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("message is blank")
        return value


class ChatContextIn(BaseModel):
    kind: Literal["home", "card"] = "home"
    deck: str | None = Field(default=None, max_length=MAX_DECK_NAME_CHARS)
    question: str | None = Field(default=None, max_length=MAX_CARD_FIELD_CHARS)
    answer: str | None = Field(default=None, max_length=MAX_CARD_FIELD_CHARS)
    revealed: bool = False
    decks: list[str] = Field(default_factory=list, max_length=MAX_DECKS)

    @field_validator("decks")
    @classmethod
    def short_names(cls, value: list[str]) -> list[str]:
        if any(len(name) > MAX_DECK_NAME_CHARS for name in value):
            raise ValueError("deck name too long")
        return value

    @model_validator(mode="after")
    def card_has_a_question(self) -> ChatContextIn:
        if self.kind == "card" and not (self.question or "").strip():
            raise ValueError("a card context needs the question")
        return self


class ChatRequest(BaseModel):
    messages: list[ChatMessage] = Field(min_length=1, max_length=MAX_MESSAGES)
    context: ChatContextIn = Field(default_factory=ChatContextIn)

    @model_validator(mode="after")
    def ends_with_the_question(self) -> ChatRequest:
        if self.messages[0].role != "user" or self.messages[-1].role != "user":
            raise ValueError("the conversation must start and end with a user message")
        return self


class ChatResponse(BaseModel):
    reply: str
    # Cut at the length ceiling: the client says so rather than pretending
    # the answer ended there.
    truncated: bool = False
    refused: bool = False


@router.post(
    "",
    operation_id="askChat",
    response_model=ChatResponse,
    summary="Ask the study tutor",
)
def chat(body: ChatRequest, user_id: CurrentUser, session: DbSession) -> ChatResponse:
    """One reply. The model call is synchronous; FastAPI runs it off the loop."""
    user = session.get(User, user_id)
    if user is None or not user.email:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "chat_account_required")

    settings = get_settings()
    if not settings.anthropic_api_key:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "chat_not_configured")

    try:
        limits.limiter.hit(
            user_id,
            per_minute=settings.chat_requests_per_minute,
            per_day=settings.chat_requests_per_day,
        )
    except limits.RateLimited as exc:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "chat_daily_limit" if exc.scope == "day" else "chat_rate_limited",
            headers={"Retry-After": str(exc.retry_after)},
        ) from exc

    context = chat_model.ChatContext(
        kind=body.context.kind,
        deck=body.context.deck,
        question=body.context.question,
        answer=body.context.answer,
        revealed=body.context.revealed,
        decks=tuple(body.context.decks),
    )
    messages = [m.model_dump() for m in body.messages]

    try:
        result = chat_model.reply(
            chat_model.client_for(settings.anthropic_api_key), messages, context
        )
    except chat_model.ChatUnavailable as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "chat_model_unavailable") from exc

    return ChatResponse(reply=result.text, truncated=result.truncated, refused=result.refused)
