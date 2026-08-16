"""The worker's job, without a worker and without a network (§7.3, §7.4).

`runner.run_one` commits — that is the point of it, since the model call must
not happen inside a transaction holding a row lock. So these tests bind the
session to a connection with `join_transaction_mode="create_savepoint"`: every
commit inside the code under test releases a savepoint, and the outer
transaction is rolled back at the end. The commits are real to the code and
invisible to the next test.
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import text, update
from sqlalchemy.orm import Session

from app.contract import ErrorCode
from app.generation import model as model_api
from app.generation import runner
from app.generation import service as generation
from app.models import GenerationJob, PendingCard
from app.quota import service as quota
from app.sync import service as sync
from tests.test_sync import engine

NOW = datetime(2026, 8, 9, 12, 0, tzinfo=timezone.utc)
DEVICE = "11111111-1111-7111-8111-111111111111"


def uid() -> str:
    return str(uuid.uuid4())


@pytest.fixture
def db():
    connection = engine.connect()
    transaction = connection.begin()
    session = Session(bind=connection, join_transaction_mode="create_savepoint")
    try:
        yield session
    finally:
        session.close()
        transaction.rollback()
        connection.close()


@pytest.fixture(autouse=True)
def empty_queue(db: Session):
    """Hides any job queued before this test ran.

    `run_one` deliberately has no filter — a worker takes whatever is oldest,
    which is the whole point of the queue. That makes these tests sensitive to
    whatever the database already held, and a suite that passes on a fresh CI
    database and fails on a developer's is worse than one that fails on both.
    The update rolls back with the rest of the transaction.
    """
    db.execute(
        update(GenerationJob)
        .where(GenerationJob.status == "queued")
        .values(status="failed", error_code="test_fixture")
    )
    db.flush()


@pytest.fixture
def user(db: Session) -> str:
    user_id = uid()
    db.execute(text("INSERT INTO users (id) VALUES (:id)"), {"id": user_id})
    db.flush()
    return user_id


@pytest.fixture
def deck(db: Session, user: str) -> str:
    deck_id = uid()
    sync.push(
        db,
        user,
        "decks",
        [
            {
                "id": deck_id,
                "name": "História",
                "updated_at": NOW,
                "device_id": DEVICE,
                "origin": "own",
                "version": 1,
            }
        ],
    )
    return deck_id


# ---------------------------------------------------------------------------
# A response, shaped like the SDK's
# ---------------------------------------------------------------------------


class _Usage:
    def __init__(self, tokens_in: int, tokens_out: int, cache_read: int = 0, cache_write: int = 0):
        self.input_tokens = tokens_in
        self.output_tokens = tokens_out
        self.cache_read_input_tokens = cache_read
        self.cache_creation_input_tokens = cache_write


class _TextBlock:
    """Structured output comes back as JSON inside a text block.

    Shaped from what the wave 0 spike observed against the live API, not from
    what the SDK's type hints suggest — the first version of this fake had a
    `.parsed` attribute, and the worker's first real call proved it wrong.
    """

    type = "text"

    def __init__(self, payload):
        self.text = json.dumps(payload, ensure_ascii=False)


class _StopDetails:
    def __init__(self, category: str):
        self.category = category


class _Response:
    def __init__(self, parsed=None, stop_reason="end_turn", refusal_category=None, **extra):
        self.usage = _Usage(1200, 900, cache_read=800, cache_write=0)
        self.stop_reason = stop_reason
        self.content = [_TextBlock(parsed)] if parsed is not None else []
        self.stop_details = _StopDetails(refusal_category) if refusal_category else None
        for key, value in extra.items():
            setattr(self, key, value)


class FakeClient:
    """Records what it was asked and answers with what it was given."""

    def __init__(self, response=None, error: Exception | None = None):
        self._response = response
        self._error = error
        self.calls: list[dict] = []
        self.messages = self

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if self._error is not None:
            raise self._error
        return self._response


def ok_payload(n: int = 4) -> dict:
    return {
        "status": "ok",
        "reason": "",
        "cards": [
            {"front": f"Pergunta {i}?", "back": f"Resposta {i}.", "tags": ["historia"]}
            for i in range(n)
        ],
    }


def enqueue_topic(db: Session, user: str, deck: str, topic: str = "Revolução Gloriosa") -> str:
    job = generation.enqueue(
        db,
        user,
        source_type="topic",
        target_deck_id=deck,
        topic=topic,
        requested_count=4,
        now=NOW,
    )
    db.flush()
    return job.id


# ---------------------------------------------------------------------------
# The happy path
# ---------------------------------------------------------------------------


def test_a_queued_job_is_carried_to_ready(db: Session, user: str, deck: str):
    job_id = enqueue_topic(db, user, deck)
    client = FakeClient(_Response(parsed=ok_payload()))

    assert runner.run_one(db, client) == job_id

    job = db.get(GenerationJob, job_id)
    assert job.status == "ready"
    assert job.finished_at is not None
    assert job.tokens_in == 1200 and job.tokens_out == 900
    # §7.4 — recorded apart from tokens_in, because a cache read is billed at
    # a tenth of the price and folding them together makes the cost wrong.
    assert job.cache_read_tokens == 800

    staged = db.query(PendingCard).filter_by(job_id=job_id).all()
    assert len(staged) == 4
    assert all(card.decision is None for card in staged), "§7.8 — nothing is auto-approved"


def test_the_call_carries_the_cacheable_prefix_and_medium_effort(
    db: Session, user: str, deck: str
):
    enqueue_topic(db, user, deck)
    client = FakeClient(_Response(parsed=ok_payload()))
    runner.run_one(db, client)

    call = client.calls[0]
    assert call["model"] == model_api.MODEL
    # §7.4 — the prefix is marked cacheable, and nothing that varies per
    # request is inside it.
    assert call["system"][0]["cache_control"] == {"type": "ephemeral"}
    assert "Nível" not in call["system"][0]["text"]
    # The spike measured `high` at +94% cost and 68% slower, for no better
    # cards.
    assert call["output_config"]["effort"] == "medium"
    assert call["output_config"]["format"]["type"] == "json_schema"


def test_an_empty_queue_is_not_an_error(db: Session):
    assert runner.run_one(db, FakeClient(_Response(parsed=ok_payload()))) is None


def test_two_workers_do_not_take_the_same_job(db: Session, user: str, deck: str):
    job_id = enqueue_topic(db, user, deck)
    client = FakeClient(_Response(parsed=ok_payload()))

    assert runner.run_one(db, client) == job_id
    # The second pass finds nothing queued: the first claim moved it on.
    assert runner.run_one(db, client) is None


# ---------------------------------------------------------------------------
# The four ways it does not produce cards (§7.7, §10)
# ---------------------------------------------------------------------------


def test_a_refusal_fails_the_job_and_returns_the_allowance(db: Session, user: str, deck: str):
    job_id = enqueue_topic(db, user, deck)
    client = FakeClient(_Response(stop_reason="refusal", refusal_category="unsafe"))

    runner.run_one(db, client)

    job = db.get(GenerationJob, job_id)
    assert job.status == "failed"
    assert job.error_code == str(ErrorCode.MODEL_REFUSED)
    # §7.7 — with one generation for the lifetime of the account, failing to
    # refund takes away the only one they had.
    assert quota.remaining(db, user) == 1


def test_a_vague_topic_is_an_answer_and_still_refunds(db: Session, user: str, deck: str):
    job_id = enqueue_topic(db, user, deck, topic="história")
    client = FakeClient(
        _Response(
            parsed={
                "status": "needs_specification",
                "reason": "Especifique o período e o recorte geográfico.",
                "cards": [],
            }
        )
    )

    runner.run_one(db, client)

    job = db.get(GenerationJob, job_id)
    assert job.status == "failed"
    assert job.error_code == str(ErrorCode.TOPIC_TOO_VAGUE)
    assert "Especifique" in job.error_detail
    assert quota.remaining(db, user) == 1


def test_the_api_being_down_refunds_and_does_not_crash_the_loop(
    db: Session, user: str, deck: str
):
    import anthropic

    job_id = enqueue_topic(db, user, deck)
    client = FakeClient(
        error=anthropic.APIConnectionError(request=None)  # type: ignore[arg-type]
    )

    runner.run_one(db, client)

    job = db.get(GenerationJob, job_id)
    assert job.status == "failed"
    assert job.error_code == str(ErrorCode.NETWORK_UNAVAILABLE)
    assert quota.remaining(db, user) == 1


def test_a_pdf_job_with_no_upload_key_fails_before_the_model_is_called(
    db: Session, user: str, deck: str
):
    job = generation.enqueue(
        db,
        user,
        source_type="pdf",
        target_deck_id=deck,
        upload_key=None,
        requested_count=4,
        now=NOW,
    )
    db.flush()
    client = FakeClient(_Response(parsed=ok_payload()))

    runner.run_one(db, client)

    assert db.get(GenerationJob, job.id).status == "failed"
    assert client.calls == [], "nothing should be sent when there is nothing to send"
    assert quota.remaining(db, user) == 1


# ---------------------------------------------------------------------------
# parse — the mapping, without a network
# ---------------------------------------------------------------------------


def test_truncated_output_is_unavailable_rather_than_partially_used():
    # Structured output cut mid-object is not half a set of cards.
    with pytest.raises(model_api.ModelUnavailable):
        model_api.parse(_Response(parsed=ok_payload(), stop_reason="max_tokens"))


def test_a_response_with_no_text_block_is_unavailable():
    with pytest.raises(model_api.ModelUnavailable):
        model_api.parse(_Response())


def test_output_that_is_not_json_is_unavailable_rather_than_half_read():
    broken = _Response(parsed={})
    broken.content[0].text = "{\"status\": \"ok\", \"cards\": ["
    with pytest.raises(model_api.ModelUnavailable):
        model_api.parse(broken)


def test_a_refusal_still_reports_its_tokens():
    result = model_api.parse(_Response(stop_reason="refusal", refusal_category="unsafe"))
    assert result.refused is True
    assert result.refusal_category == "unsafe"
    assert (result.tokens_in, result.tokens_out) == (1200, 900)


# ---------------------------------------------------------------------------
# build_content — material first, instruction after
# ---------------------------------------------------------------------------


def test_a_pdf_is_sent_natively_and_the_instruction_follows_it():
    content = model_api.build_content(
        level="intermediario", requested_count=10, pdf=b"%PDF-1.7 fake"
    )
    assert content[0]["type"] == "document"
    # §7.1 — native PDF, no OCR stage.
    assert content[0]["source"]["media_type"] == "application/pdf"
    assert content[1]["type"] == "text"
    assert "10 flashcards" in content[1]["text"]


def test_photos_are_sent_as_images_in_order():
    content = model_api.build_content(
        level="basico",
        requested_count=6,
        images=[("image/jpeg", b"one"), ("image/png", b"two")],
    )
    assert [b["type"] for b in content] == ["image", "image", "text"]
    assert content[0]["source"]["media_type"] == "image/jpeg"
    assert content[1]["source"]["media_type"] == "image/png"


def test_a_topic_prompt_carries_the_level_the_user_chose():
    content = model_api.build_content(
        level="avancado", requested_count=12, topic="Ciclo de Krebs"
    )
    assert content[0]["type"] == "text"
    assert "Ciclo de Krebs" in content[0]["text"]
    assert "avancado" in content[0]["text"]


# ---------------------------------------------------------------------------
# storage — the parts that decide something (§7.2)
# ---------------------------------------------------------------------------


def test_an_upload_url_is_only_signed_for_types_we_accept():
    from app.generation import storage

    # The content type is baked into the signature, so a client cannot ask for
    # a key as a PDF and then put a video there.
    with pytest.raises(ValueError):
        storage.presign_upload("uploads/x", "video/mp4")

    assert "application/pdf" in storage.ALLOWED_CONTENT_TYPES
    assert "image/jpeg" in storage.ALLOWED_CONTENT_TYPES


def test_the_upload_window_is_short():
    from app.generation import storage

    # Long enough for a phone on mobile data to finish a PDF, short enough
    # that a leaked URL is not a standing write grant.
    assert 300 <= storage.UPLOAD_TTL_SECONDS <= 3600


def test_the_client_uploads_to_an_address_it_can_resolve(monkeypatch):
    """§7.2 — the pre-signed URL is signed against a host, and `minio` is a
    container name no phone can resolve. Server and client reach storage at
    different addresses, and only the client's is in the signature."""
    from app.config import Settings
    from app.generation import storage

    monkeypatch.setattr(
        "app.generation.storage.get_settings",
        lambda: Settings(
            s3_endpoint_url="http://minio:9000",
            s3_public_endpoint_url="http://10.0.2.2:9000",
        ),
    )

    url = storage.presign_upload("uploads/u/abc", "application/pdf")
    assert url.startswith("http://10.0.2.2:9000/")
    assert "minio:9000" not in url


def test_without_a_public_endpoint_the_internal_one_is_used(monkeypatch):
    """Right for a single-host deployment, and wrong loudly everywhere else:
    the upload fails with a DNS error naming the container."""
    from app.config import Settings
    from app.generation import storage

    monkeypatch.setattr(
        "app.generation.storage.get_settings",
        # Empty, not absent: inside the container the environment supplies
        # one, and the contract being tested is "empty means fall back".
        lambda: Settings(
            s3_endpoint_url="http://storage.internal:9000",
            s3_public_endpoint_url="",
        ),
    )

    assert storage.presign_upload("uploads/u/abc", "image/jpeg").startswith(
        "http://storage.internal:9000/"
    )
