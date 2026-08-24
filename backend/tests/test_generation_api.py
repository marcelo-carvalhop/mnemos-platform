"""The §7 flow over HTTP.

The service layer is tested in `test_generation.py` and the worker in
`test_runner.py`; what is left to prove here is the part only a router can get
wrong — who is allowed to see what, which status code the client branches on,
and whether the flow can actually be walked end to end.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text, update

from app.auth import service as auth
from app.db import SessionLocal
from app.generation import service as generation
from app.main import app
from app.models import GenerationJob
from app.sync import service as sync

NOW = datetime(2026, 8, 9, 12, 0, tzinfo=timezone.utc)
DEVICE = "11111111-1111-7111-8111-111111111111"


def uid() -> str:
    return str(uuid.uuid4())


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


class Account:
    """A user, a device token and a deck — the state a real client has."""

    def __init__(self, user_id: str, token: str, deck_id: str):
        self.user_id = user_id
        self.token = token
        self.deck_id = deck_id

    @property
    def headers(self) -> dict:
        return {"Authorization": f"Bearer {self.token}"}


def make_account() -> Account:
    with SessionLocal() as session:
        pair = auth.register_device(
            session,
            device_id=uid(),
            platform="android",
            attested=True,
        )
        user_id, _ = auth.verify_access_token(pair.access_token)

        deck_id = uid()
        sync.push(
            session,
            user_id,
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
        session.commit()
    return Account(user_id, pair.access_token, deck_id)


@pytest.fixture
def account() -> Account:
    return make_account()


def finish(job_id: str, cards: list[dict]) -> None:
    """Stands in for the worker, so the API test needs no model."""
    with SessionLocal() as session:
        generation.complete(
            session,
            job_id,
            generation.GeneratedCards(status="ok", cards=cards, tokens_in=10, tokens_out=20),
        )
        session.commit()


def sample_cards(n: int = 3) -> list[dict]:
    return [
        {"front": f"Pergunta {i}?", "back": f"Resposta {i}.", "tags": ["historia"]}
        for i in range(n)
    ]


# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------


def test_nothing_in_generation_is_reachable_without_a_token(client):
    for method, path in [
        ("post", "/v1/generation/uploads"),
        ("post", "/v1/generation/jobs"),
        ("get", "/v1/generation/jobs"),
        ("get", "/v1/generation/jobs/whatever"),
        ("get", "/v1/generation/jobs/whatever/queue"),
        ("post", "/v1/generation/pending/whatever"),
        ("post", "/v1/generation/jobs/whatever/close"),
    ]:
        response = (
            client.get(path) if method == "get" else client.post(path, json={})
        )
        assert response.status_code == 401, f"{method.upper()} {path}"


# ---------------------------------------------------------------------------
# The flow, walked
# ---------------------------------------------------------------------------


def test_the_whole_flow_from_request_to_real_cards(client, account: Account):
    created = client.post(
        "/v1/generation/jobs",
        headers=account.headers,
        json={
            "source_type": "topic",
            "target_deck_id": account.deck_id,
            "topic": "Revolução Gloriosa",
            "requested_count": 3,
        },
    )
    # 202: accepted, not done. The app polls from here.
    assert created.status_code == 202
    job_id = created.json()["id"]
    assert created.json()["stage"] == "na fila"

    finish(job_id, sample_cards(3))

    polled = client.get(f"/v1/generation/jobs/{job_id}", headers=account.headers).json()
    assert polled["status"] == "ready"
    # §5.5 — a named stage, not a bar that lies.
    assert polled["stage"] == "pronto"
    assert polled["card_count"] == 3

    queue = client.get(f"/v1/generation/jobs/{job_id}/queue", headers=account.headers).json()
    assert queue["total"] == 3 and queue["decided"] == 0
    assert all(card["decision"] is None for card in queue["cards"])

    first = queue["cards"][0]["id"]
    client.post(
        f"/v1/generation/pending/{first}",
        headers=account.headers,
        json={"decision": "discarded"},
    )
    remaining = client.post(
        f"/v1/generation/jobs/{job_id}/approve-all", headers=account.headers
    ).json()
    assert remaining["created"] == 2, "the discarded one is not approved by approve-all"

    closed = client.post(f"/v1/generation/jobs/{job_id}/close", headers=account.headers).json()
    assert closed["created"] == 2

    # §7.8 — idempotent, because a card reuses its pending row's id.
    again = client.post(f"/v1/generation/jobs/{job_id}/close", headers=account.headers).json()
    assert again["created"] == 0


def test_undo_is_a_real_state_not_a_missing_one(client, account: Account):
    created = client.post(
        "/v1/generation/jobs",
        headers=account.headers,
        json={
            "source_type": "topic",
            "target_deck_id": account.deck_id,
            "topic": "Revolução Gloriosa",
        },
    )
    job_id = created.json()["id"]
    finish(job_id, sample_cards(2))

    queue = client.get(f"/v1/generation/jobs/{job_id}/queue", headers=account.headers).json()
    pending_id = queue["cards"][0]["id"]

    client.post(
        f"/v1/generation/pending/{pending_id}",
        headers=account.headers,
        json={"decision": "discarded"},
    )
    # §5.7 makes undo mandatory: null is a decision to un-decide.
    undone = client.post(
        f"/v1/generation/pending/{pending_id}", headers=account.headers, json={"decision": None}
    )
    assert undone.status_code == 200
    assert undone.json()["decision"] is None


# ---------------------------------------------------------------------------
# What one account may learn about another
# ---------------------------------------------------------------------------


def test_another_users_job_is_not_found_rather_than_forbidden(client, account: Account):
    stranger = make_account()
    created = client.post(
        "/v1/generation/jobs",
        headers=stranger.headers,
        json={
            "source_type": "topic",
            "target_deck_id": stranger.deck_id,
            "topic": "Revolução Gloriosa",
        },
    )
    job_id = created.json()["id"]

    # 404, not 403: whether someone else's job exists is not theirs to learn.
    assert client.get(f"/v1/generation/jobs/{job_id}", headers=account.headers).status_code == 404
    assert (
        client.get(f"/v1/generation/jobs/{job_id}/queue", headers=account.headers).status_code
        == 404
    )
    assert (
        client.post(f"/v1/generation/jobs/{job_id}/close", headers=account.headers).status_code
        == 404
    )


def test_an_upload_key_from_another_namespace_is_refused(client, account: Account):
    stranger = make_account()
    response = client.post(
        "/v1/generation/jobs",
        headers=account.headers,
        json={
            "source_type": "pdf",
            "target_deck_id": account.deck_id,
            "upload_key": f"uploads/{stranger.user_id}/deadbeef",
        },
    )
    assert response.status_code == 403


def test_a_deck_that_is_not_yours_is_not_a_target(client, account: Account):
    stranger = make_account()
    response = client.post(
        "/v1/generation/jobs",
        headers=account.headers,
        json={
            "source_type": "topic",
            "target_deck_id": stranger.deck_id,
            "topic": "Revolução Gloriosa",
        },
    )
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# Getting back to an abandoned queue
# ---------------------------------------------------------------------------


def test_an_unfinished_queue_can_be_found_again(client, account: Account):
    """The progress screen says the work continues if you leave. This is what
    makes that true: on the free plan the abandoned queue holds the only
    generation the account will ever get, and a queue reachable solely from the
    screen that launched it is lost the moment the app is backgrounded.
    """
    created = client.post(
        "/v1/generation/jobs",
        headers=account.headers,
        json={
            "source_type": "topic",
            "target_deck_id": account.deck_id,
            "topic": "Revolução Gloriosa",
        },
    )
    job_id = created.json()["id"]

    # Still running: open, with nothing to decide yet.
    running = client.get("/v1/generation/jobs", headers=account.headers).json()["jobs"]
    assert [j["id"] for j in running] == [job_id]
    assert running[0]["pending"] == 0

    finish(job_id, sample_cards(3))

    waiting = client.get("/v1/generation/jobs", headers=account.headers).json()["jobs"]
    assert waiting[0]["pending"] == 3
    # The deck is how the app knows where to send the person back to.
    assert waiting[0]["target_deck_id"] == account.deck_id
    assert waiting[0]["topic"] == "Revolução Gloriosa"

    client.post(f"/v1/generation/jobs/{job_id}/approve-all", headers=account.headers)

    # Nothing is owed any more. Note that `close` never changes the status —
    # the count is what closes the job, which is why this is a join.
    assert client.get("/v1/generation/jobs", headers=account.headers).json()["jobs"] == []


def test_an_open_queue_belongs_to_one_account(client, account: Account):
    client.post(
        "/v1/generation/jobs",
        headers=account.headers,
        json={
            "source_type": "topic",
            "target_deck_id": account.deck_id,
            "topic": "Revolução Gloriosa",
        },
    )
    other = make_account()
    assert client.get("/v1/generation/jobs", headers=other.headers).json()["jobs"] == []


def test_a_failed_generation_is_not_something_to_come_back_to(client, account: Account):
    """The quota was released and there is no queue. Listing it would send
    someone back to a screen with nothing on it.
    """
    created = client.post(
        "/v1/generation/jobs",
        headers=account.headers,
        json={
            "source_type": "topic",
            "target_deck_id": account.deck_id,
            "topic": "Revolução Gloriosa",
        },
    )
    with SessionLocal() as session:
        generation.fail(session, created.json()["id"], "topic_too_vague")
        session.commit()

    assert client.get("/v1/generation/jobs", headers=account.headers).json()["jobs"] == []


# ---------------------------------------------------------------------------
# Refusals the client branches on
# ---------------------------------------------------------------------------


def test_the_second_generation_is_402_so_the_app_shows_the_paywall(client, account: Account):
    body = {
        "source_type": "topic",
        "target_deck_id": account.deck_id,
        "topic": "Revolução Gloriosa",
    }
    first = client.post("/v1/generation/jobs", headers=account.headers, json=body)
    assert first.status_code == 202
    finish(first.json()["id"], sample_cards(2))

    second = client.post("/v1/generation/jobs", headers=account.headers, json=body)
    # §7.7 — one generation for the lifetime of the account. 402, not 403 and
    # not 429: the client shows the paywall, which is the conversion moment.
    assert second.status_code == 402


def test_a_pdf_job_without_a_key_is_rejected_before_the_quota_is_touched(
    client, account: Account
):
    response = client.post(
        "/v1/generation/jobs",
        headers=account.headers,
        json={"source_type": "pdf", "target_deck_id": account.deck_id},
    )
    assert response.status_code == 422

    # The allowance must survive a malformed request.
    assert client.get("/v1/quota/", headers=account.headers).json()["remaining"] == 1


def test_a_topic_job_with_no_topic_is_rejected(client, account: Account):
    response = client.post(
        "/v1/generation/jobs",
        headers=account.headers,
        json={"source_type": "topic", "target_deck_id": account.deck_id},
    )
    assert response.status_code == 422


def test_an_upload_url_is_refused_for_a_type_we_do_not_accept(client, account: Account):
    response = client.post(
        "/v1/generation/uploads",
        headers=account.headers,
        json={"content_type": "video/mp4"},
    )
    assert response.status_code == 415


def test_an_upload_key_is_namespaced_by_user(client, account: Account):
    response = client.post(
        "/v1/generation/uploads",
        headers=account.headers,
        json={"content_type": "application/pdf"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["upload_key"].startswith(f"uploads/{account.user_id}/")
    assert body["expires_in"] > 0


def test_a_failed_job_reports_its_code_so_the_app_maps_it_to_copy(client, account: Account):
    created = client.post(
        "/v1/generation/jobs",
        headers=account.headers,
        json={
            "source_type": "topic",
            "target_deck_id": account.deck_id,
            "topic": "história",
        },
    )
    job_id = created.json()["id"]

    with SessionLocal() as session:
        generation.complete(
            session,
            job_id,
            generation.GeneratedCards(
                status="needs_specification", cards=[], reason="Especifique o período."
            ),
        )
        session.commit()

    polled = client.get(f"/v1/generation/jobs/{job_id}", headers=account.headers).json()
    assert polled["status"] == "failed"
    # §10 — a machine-readable code, so the client maps it to copy rather than
    # matching on server prose.
    assert polled["error_code"] == "topic_too_vague"
    assert polled["stage"] == "falhou"

    # §7.7 — a vague topic is an answer, not a spend.
    assert client.get("/v1/quota/", headers=account.headers).json()["remaining"] == 1


@pytest.fixture(autouse=True)
def _drain_queue():
    """These tests enqueue real rows; the worker must not pick them up.

    They are committed, unlike the savepoint-isolated suites, because a
    TestClient request runs in its own session and cannot see an uncommitted
    one. So the queue is emptied afterwards instead.
    """
    yield
    with SessionLocal() as session:
        session.execute(
            update(GenerationJob)
            .where(GenerationJob.status.in_(("queued", "reading", "generating")))
            .values(status="failed", error_code="test_teardown")
        )
        session.commit()
