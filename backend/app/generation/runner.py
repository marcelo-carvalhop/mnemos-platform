"""One job, start to finish (§7.3).

Separated from `worker.py` so the loop is a loop and the work is a function:
[run_one] is called by a test with an ordinary session and a fake client, and
by the worker with a real one.

The transaction boundary is the point of this module. The model call happens
**outside** the database transaction — a call that takes 10 to 24 seconds
(measured, §5.5) must not hold a row lock for its duration — while the claim
and the completion are each transactional. A crash in between leaves the job
`reading`, which the stale sweeper returns to the queue.
"""

from __future__ import annotations

import logging

from sqlalchemy.orm import Session

from app.contract import ErrorCode

from . import model as model_api
from . import service, storage

logger = logging.getLogger(__name__)

# Text uploads are read as UTF-8; anything else goes to the model as a document
# or an image.
_PDF = "application/pdf"


def run_one(session: Session, client: object) -> str | None:
    """Claims a job and carries it to `ready` or `failed`.

    Returns the job id it handled, or None if the queue was empty.
    """
    job = service.claim_next(session)
    if job is None:
        return None

    job_id = job.id
    source_type = job.source_type
    upload_key = job.upload_key
    topic = job.topic
    level = job.level
    requested = job.requested_count
    # The claim is committed on its own so that no other worker picks the job
    # up while the model is thinking, and so the row lock is not held across
    # the network call.
    session.commit()

    logger.info("job %s claimed (%s)", job_id, source_type)

    try:
        content = _build_content(source_type, upload_key, topic, level, requested)
    except storage.UploadUnavailable as exc:
        # Infrastructure, so the allowance comes back (§7.7).
        logger.warning("job %s: upload unavailable: %s", job_id, exc)
        service.fail(session, job_id, ErrorCode.NETWORK_UNAVAILABLE, str(exc), refund=True)
        session.commit()
        return job_id

    service.advance(session, job_id, "generating")
    session.commit()

    try:
        result = model_api.generate(client, content)  # type: ignore[arg-type]
    except model_api.ModelUnavailable as exc:
        logger.warning("job %s: model unavailable: %s", job_id, exc)
        service.fail(session, job_id, ErrorCode.NETWORK_UNAVAILABLE, str(exc), refund=True)
        session.commit()
        return job_id

    # `complete` decides between ready and failed, and owns the quota: a
    # refusal or a vague topic refunds, cards staged commit (§7.7).
    staged = service.complete(session, job_id, result)
    session.commit()

    if upload_key:
        # §8.4 — the source material is not kept once the cards exist. A
        # failure to delete must not undo a finished job; the bucket lifecycle
        # rule is the backstop.
        try:
            storage.delete(upload_key)
        except storage.UploadUnavailable as exc:  # noqa: BLE001
            logger.warning("job %s: could not delete %s: %s", job_id, upload_key, exc)

    logger.info("job %s finished with %d cards staged", job_id, len(staged))
    return job_id


def _build_content(
    source_type: str,
    upload_key: str | None,
    topic: str | None,
    level: str,
    requested_count: int,
) -> list[dict]:
    if source_type == "topic":
        return model_api.build_content(level=level, requested_count=requested_count, topic=topic)

    if source_type == "text":
        return model_api.build_content(
            level=level, requested_count=requested_count, material=topic
        )

    if upload_key is None:
        raise storage.UploadUnavailable(f"{source_type} job has no upload key")

    content_type, data = storage.fetch(upload_key)

    if source_type == "pdf" or content_type == _PDF:
        return model_api.build_content(level=level, requested_count=requested_count, pdf=data)

    return model_api.build_content(
        level=level, requested_count=requested_count, images=[(content_type, data)]
    )
