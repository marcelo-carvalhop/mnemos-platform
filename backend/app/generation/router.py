"""Generation endpoints (§7).

The whole §7 flow, in the order the app walks it:

    POST /v1/generation/uploads   → a pre-signed PUT, for a PDF or a photo
    POST /v1/generation/jobs      → enqueue; the quota is reserved here
    GET  /v1/generation/jobs/{id} → poll: the named stage §5.5 shows
    GET  .../jobs/{id}/queue      → the cards, for approval (§7.8)
    POST .../pending/{id}         → approve, discard, or undo
    POST .../jobs/{id}/approve-all
    POST .../jobs/{id}/close      → approved rows become real cards

Nothing here talks to the model. The API enqueues and reports; the worker
generates (§4.2, §11.7). That is what keeps a request cheap and lets a
generation outlive the HTTP call that asked for it.
"""

from __future__ import annotations

import secrets
from typing import Literal

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

from app.contract import TOPIC_MAX_CHARS
from app.deps import CurrentUser, DbSession, Identity
from app.generation import service, storage
from app.models import GenerationJob
from app.quota.service import QuotaExhausted

router = APIRouter(prefix="/v1/generation", tags=["generation"])


# ---------------------------------------------------------------------------
# Uploads (§7.2)
# ---------------------------------------------------------------------------


class UploadRequest(BaseModel):
    content_type: str = Field(examples=["application/pdf"])


class UploadResponse(BaseModel):
    upload_key: str
    url: str
    expires_in: int


@router.post(
    "/uploads",
    operation_id="createUpload",
    response_model=UploadResponse,
    summary="A pre-signed URL to upload a PDF or photo",
)
def create_upload(
    body: UploadRequest, user_id: CurrentUser, _session: DbSession
) -> UploadResponse:
    """The file never passes through this process (§7.2).

    The client PUTs straight to the bucket and sends back only the key, so the
    API never holds a multi-megabyte body and the two containers scale apart.
    The key is namespaced by user so one account cannot hand another's object
    to its own job.
    """
    key = f"uploads/{user_id}/{secrets.token_hex(16)}"
    try:
        url = storage.presign_upload(key, body.content_type)
    except ValueError as exc:
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, str(exc)) from exc
    except storage.UploadUnavailable as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(exc)) from exc

    return UploadResponse(upload_key=key, url=url, expires_in=storage.UPLOAD_TTL_SECONDS)


# ---------------------------------------------------------------------------
# Jobs (§7.3)
# ---------------------------------------------------------------------------


class JobRequest(BaseModel):
    source_type: Literal["topic", "text", "pdf", "photo"]
    target_deck_id: str

    # Carrega o assunto ("topic") ou o material colado ("text"). O teto vem do
    # contrato porque as duas pontas precisam concordar sobre ele.
    topic: str | None = Field(default=None, max_length=TOPIC_MAX_CHARS)
    upload_key: str | None = None
    requested_count: int = Field(default=10, ge=1, le=50)
    level: Literal["basico", "intermediario", "avancado"] = "intermediario"


class JobResponse(BaseModel):
    id: str
    status: str
    stage: str
    error_code: str | None = None
    error_detail: str | None = None
    card_count: int = 0


# §5.5 — the progress screen names the stage rather than showing a bar that
# lies. The mapping lives here so the app does not invent copy from a status.
_STAGES = {
    "queued": "na fila",
    "reading": "lendo o material",
    "generating": "escrevendo os cards",
    "ready": "pronto",
    "failed": "falhou",
}


@router.post(
    "/jobs",
    operation_id="createGenerationJob",
    response_model=JobResponse,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Ask for a generation",
)
def create_job(body: JobRequest, user_id: CurrentUser, session: DbSession) -> JobResponse:
    """202, not 201: the work has been accepted, not done.

    The quota is reserved inside `enqueue`, in the same transaction that
    creates the row — §7.7's reason for the queue being a Postgres table and
    not Redis is precisely that these two cannot be allowed to disagree.
    """
    if body.source_type in ("pdf", "photo") and not body.upload_key:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"{body.source_type} needs an upload_key",
        )
    # `not body.topic` deixava passar "   ": espaço em branco é truthy. Um
    # assunto em branco chega ao modelo como um pedido sobre nada, gasta a
    # geração da conta e volta com cards sobre nada — §7.7.1 torna isso
    # irreversível no plano grátis.
    if body.source_type in ("topic", "text") and not (body.topic or "").strip():
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"{body.source_type} needs a topic",
        )
    # A key from another user's namespace is not theirs to generate from.
    if body.upload_key and not body.upload_key.startswith(f"uploads/{user_id}/"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "upload_key does not belong to you")

    try:
        job = service.enqueue(
            session,
            user_id,
            source_type=body.source_type,
            target_deck_id=body.target_deck_id,
            topic=body.topic,
            upload_key=body.upload_key,
            requested_count=body.requested_count,
            level=body.level,
        )
    except service.UnknownDeck as exc:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(exc)) from exc
    except QuotaExhausted as exc:
        # §7.7 — 402, so the client shows the paywall rather than an error.
        raise HTTPException(status.HTTP_402_PAYMENT_REQUIRED, str(exc)) from exc

    # `get_session` yields and does not commit; the router owns the boundary,
    # so a job that is not committed here is a job the worker never sees.
    session.commit()
    return _job_response(session, job)


class OpenJobResponse(BaseModel):
    id: str
    status: str
    stage: str
    target_deck_id: str
    topic: str | None = None

    """Cards still waiting for a yes or no. Zero while the job is running."""
    pending: int = 0


class OpenJobsResponse(BaseModel):
    """An envelope, not a bare array — so a count or a cursor can be added
    later without every client having to change shape on the same day."""

    jobs: list[OpenJobResponse]


@router.get(
    "/jobs",
    operation_id="listOpenGenerations",
    response_model=OpenJobsResponse,
    summary="Generations still owed an answer",
)
def list_open(user_id: CurrentUser, session: DbSession) -> OpenJobsResponse:
    """What the progress screen promises when it says the work continues.

    Leaving the generation screen is allowed — the worker does not care whether
    a phone is watching. But a queue reachable only from the screen that
    launched it is lost the moment someone backgrounds the app, and on the free
    plan that is the one generation the account will ever get (§7.7.1). The
    server knows what is owed; this is it saying so.
    """
    return OpenJobsResponse(
        jobs=[
            OpenJobResponse(
                id=job.id,
                status=job.status,
                stage=_STAGES.get(job.status, job.status),
                target_deck_id=job.target_deck_id,
                topic=job.topic,
                pending=pending,
            )
            for job, pending in service.open_jobs(session, user_id)
        ]
    )


@router.get(
    "/jobs/{job_id}",
    operation_id="getGenerationJob",
    response_model=JobResponse,
    summary="How the generation is going",
)
def get_job(job_id: str, user_id: CurrentUser, session: DbSession) -> JobResponse:
    return _job_response(session, _own_job(session, user_id, job_id))


# ---------------------------------------------------------------------------
# The approval queue (§7.8)
# ---------------------------------------------------------------------------


class PendingCardResponse(BaseModel):
    id: str
    front: str
    back: str
    tags: list[str]
    position: int
    decision: str | None


class QueueResponse(BaseModel):
    job_id: str
    cards: list[PendingCardResponse]
    decided: int
    total: int


class DecisionRequest(BaseModel):
    # None is the undo §5.7 makes mandatory, not a missing value.
    decision: Literal["approved", "discarded"] | None = None


class CloseResponse(BaseModel):
    created: int


@router.get(
    "/jobs/{job_id}/queue",
    operation_id="getApprovalQueue",
    response_model=QueueResponse,
    summary="The generated cards, for approval",
)
def get_queue(job_id: str, user_id: CurrentUser, session: DbSession) -> QueueResponse:
    """§7.8 — nothing generated becomes a card without a human saying so."""
    _own_job(session, user_id, job_id)
    cards = service.queue_for(session, user_id, job_id)
    return QueueResponse(
        job_id=job_id,
        cards=[
            PendingCardResponse(
                id=c.id,
                front=c.front,
                back=c.back,
                tags=list(c.tags or []),
                position=c.position,
                decision=c.decision,
            )
            for c in cards
        ],
        decided=sum(1 for c in cards if c.decision is not None),
        total=len(cards),
    )


@router.post(
    "/pending/{pending_id}",
    operation_id="decidePendingCard",
    response_model=PendingCardResponse,
    summary="Approve, discard, or undo one card",
)
def decide(
    pending_id: str,
    body: DecisionRequest,
    user_id: CurrentUser,
    session: DbSession,
) -> PendingCardResponse:
    try:
        card = service.decide(session, user_id, pending_id, body.decision)
    except service.JobNotFound as exc:
        raise HTTPException(status.HTTP_404_NOT_FOUND, str(exc)) from exc

    session.commit()
    return PendingCardResponse(
        id=card.id,
        front=card.front,
        back=card.back,
        tags=list(card.tags or []),
        position=card.position,
        decision=card.decision,
    )


@router.post(
    "/jobs/{job_id}/approve-all",
    operation_id="approveRemaining",
    response_model=CloseResponse,
    summary="Approve everything still undecided",
)
def approve_all(job_id: str, user_id: CurrentUser, session: DbSession) -> CloseResponse:
    _own_job(session, user_id, job_id)
    created = service.approve_remaining(session, user_id, job_id)
    session.commit()
    return CloseResponse(created=created)


@router.post(
    "/jobs/{job_id}/close",
    operation_id="closeGenerationJob",
    response_model=CloseResponse,
    summary="Turn approved cards into real ones",
)
def close(job_id: str, identity: Identity, session: DbSession) -> CloseResponse:
    """Idempotent: a card reuses its pending row's id, so a retried close
    inserts nothing new (§7.8). The device id comes from the token, never
    from the body — an id in a payload proves identity, not authority.
    """
    user_id, device_id = identity
    _own_job(session, user_id, job_id)
    created = service.materialise(session, user_id, job_id, device_id=device_id)
    session.commit()
    return CloseResponse(created=created)


# ---------------------------------------------------------------------------


def _own_job(session: DbSession, user_id: str, job_id: str):
    job = session.get(GenerationJob, job_id)
    # 404 rather than 403 for someone else's job: whether it exists is not
    # theirs to learn.
    if job is None or job.user_id != user_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "job not found")
    return job


def _job_response(session: DbSession, job) -> JobResponse:
    return JobResponse(
        id=job.id,
        status=job.status,
        stage=_STAGES.get(job.status, job.status),
        error_code=job.error_code,
        error_detail=job.error_detail,
        card_count=len(service.queue_for(session, job.user_id, job.id))
        if job.status == "ready"
        else 0,
    )
