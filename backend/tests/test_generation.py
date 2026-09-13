"""Generation verification (§7, plan wave 3a).

The model API is mocked with recorded shapes. Live-model behaviour was the wave
0 spike's job; this tests our code, deterministically.
"""

from __future__ import annotations

import unicodedata
import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.contract import BACK_MAX_GRAPHEMES, FRONT_MAX_GRAPHEMES, ErrorCode
from app.generation import service as generation
from app.generation.service import GeneratedCards, UnknownDeck
from app.generation.text import constrain, grapheme_length, normalise
from app.models import Card, GenerationJob
from app.quota import service as quota
from app.quota.service import QuotaExhausted
from app.sync import service as sync
from tests.test_sync import SessionFactory

NOW = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
DEVICE = "11111111-1111-7111-8111-111111111111"

# Built at runtime, never written as a literal. A literal decomposed string is
# silently re-normalised to NFC by editors and formatters, which would make the
# comparison below compare a string with itself. That has now happened twice in
# this project, in two languages.
COMPOSED = unicodedata.normalize("NFC", "ção")
DECOMPOSED = unicodedata.normalize("NFD", COMPOSED)


def uid() -> str:
    return str(uuid.uuid4())


@pytest.fixture
def db():
    with SessionFactory() as session:
        yield session
        session.rollback()


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


def good_cards(n: int = 5) -> list[dict]:
    return [
        {"front": f"Pergunta {i}?", "back": f"Resposta {i}.", "tags": ["historia"]}
        for i in range(n)
    ]


# ---------------------------------------------------------------------------
# constrain (§7.6)
# ---------------------------------------------------------------------------


def test_grapheme_counting_matches_the_dart_fixture():
    """The same cases the Dart suite asserts (§7.6, §12)."""
    assert grapheme_length("") == 0
    assert grapheme_length(COMPOSED) == 3
    assert grapheme_length(DECOMPOSED) == 3
    assert grapheme_length("👍🏽") == 1        # skin-tone modifier
    assert grapheme_length("👨‍👩‍👧") == 1  # ZWJ family
    assert grapheme_length("guarda-chuva") == 12


def test_composed_and_decomposed_count_the_same():
    assert len(COMPOSED) != len(DECOMPOSED), "the fixture must exercise the difference"
    assert grapheme_length(COMPOSED) == grapheme_length(DECOMPOSED)


def test_normalisation_never_changes_the_count():
    """Why grapheme clusters are the unit: NFC is a storage concern, not a
    counting one."""
    for sample in [COMPOSED, DECOMPOSED, "👍🏽"]:
        assert grapheme_length(sample) == grapheme_length(normalise(sample))


def test_a_card_at_the_limit_is_kept_and_one_over_is_dropped():
    result = constrain(
        [
            {"front": "a" * FRONT_MAX_GRAPHEMES, "back": "b" * BACK_MAX_GRAPHEMES},
            {"front": "a" * (FRONT_MAX_GRAPHEMES + 1), "back": "ok"},
            {"front": "ok", "back": "b" * (BACK_MAX_GRAPHEMES + 1)},
        ]
    )
    assert len(result.kept) == 1
    assert len(result.dropped) == 2
    assert all(d["reason"] == "too_long" for d in result.dropped)


def test_oversized_cards_are_dropped_not_truncated():
    """Truncation gives an answer cut mid-sentence, worse than one fewer card."""
    long_back = "b" * (BACK_MAX_GRAPHEMES + 50)
    result = constrain([{"front": "ok", "back": long_back}])
    assert result.kept == []
    assert result.dropped[0]["back"] == long_back, "the text must not be altered"


def test_empty_cards_are_dropped():
    result = constrain([{"front": "  ", "back": "algo"}, {"front": "algo", "back": ""}])
    assert result.kept == []


def test_tags_are_normalised_and_capped():
    result = constrain(
        [{"front": "f", "back": "v", "tags": ["  História ", "REVOLUÇÃO", "a", "b", "c"]}]
    )
    assert result.kept[0]["tags"] == ["história", "revolução", "a"]


# ---------------------------------------------------------------------------
# The queue (§4.2, §7.3)
# ---------------------------------------------------------------------------


def test_enqueue_reserves_quota_in_the_same_transaction(db, user, deck):
    assert quota.remaining(db, user, at=NOW) == 1
    generation.enqueue(db, user, source_type="topic", target_deck_id=deck, topic="t", now=NOW)
    assert quota.remaining(db, user, at=NOW) == 0


def test_an_exhausted_quota_blocks_the_enqueue_and_writes_no_job(db, user, deck):
    generation.enqueue(db, user, source_type="topic", target_deck_id=deck, topic="t", now=NOW)

    with pytest.raises(QuotaExhausted):
        generation.enqueue(
            db, user, source_type="topic", target_deck_id=deck, topic="outro", now=NOW
        )

    jobs = db.query(GenerationJob).filter(GenerationJob.user_id == user).all()
    assert len(jobs) == 1, "a rejected generation must leave no job behind"


def test_generating_into_another_deck_is_refused(db, user):
    other_user = uid()
    db.execute(text("INSERT INTO users (id) VALUES (:id)"), {"id": other_user})
    other_deck = uid()
    sync.push(
        db,
        other_user,
        "decks",
        [
            {
                "id": other_deck,
                "name": "dele",
                "updated_at": NOW,
                "device_id": DEVICE,
                "origin": "own",
                "version": 1,
            }
        ],
    )

    with pytest.raises(UnknownDeck):
        generation.enqueue(
            db, user, source_type="topic", target_deck_id=other_deck, topic="t", now=NOW
        )


def test_claim_takes_the_oldest_queued_job(db, user, deck):
    # Other tests commit jobs, so the queue is shared. Drain it first or this
    # claims someone else's row and the assertion is about the wrong job.
    db.execute(text("UPDATE generation_jobs SET status='ready' WHERE status='queued'"))
    db.commit()

    first = generation.enqueue(
        db, user, source_type="topic", target_deck_id=deck, topic="a", now=NOW
    )
    db.commit()

    claimed = generation.claim_next(db, now=NOW)
    assert claimed is not None
    assert claimed.id == first.id
    assert claimed.status == "reading"
    assert claimed.started_at is not None
    db.rollback()


def test_an_empty_queue_returns_nothing(db):
    db.execute(text("DELETE FROM pending_cards"))
    db.execute(text("UPDATE generation_jobs SET status = 'ready' WHERE status = 'queued'"))
    db.flush()
    assert generation.claim_next(db, now=NOW) is None


# ---------------------------------------------------------------------------
# Completion, refusal and refunds (§7.6, §7.7, §10)
# ---------------------------------------------------------------------------


def test_a_successful_job_stages_cards_and_spends_the_quota(db, user, deck):
    job = generation.enqueue(
        db, user, source_type="topic", target_deck_id=deck, topic="t", now=NOW
    )
    pending = generation.complete(
        db, job.id, GeneratedCards(status="ok", cards=good_cards(5)), now=NOW
    )

    assert len(pending) == 5
    assert [p.position for p in pending] == [0, 1, 2, 3, 4]
    assert db.get(GenerationJob, job.id).status == "ready"
    assert quota.remaining(db, user, at=NOW) == 0, "a delivered generation is spent"


def test_a_model_refusal_costs_nothing(db, user, deck):
    """§10 — a decline before output is not billed, so it is not charged."""
    job = generation.enqueue(
        db, user, source_type="topic", target_deck_id=deck, topic="toxicologia", now=NOW
    )
    generation.complete(
        db,
        job.id,
        GeneratedCards(status="ok", cards=[], refused=True, refusal_category="bio"),
        now=NOW,
    )

    stored = db.get(GenerationJob, job.id)
    assert stored.status == "failed"
    assert stored.error_code == str(ErrorCode.MODEL_REFUSED)
    assert quota.remaining(db, user, at=NOW) == 1, "the only free generation must come back"


def test_a_vague_topic_costs_nothing(db, user, deck):
    """§7.5 — declining to guess is a real answer, but it produced no cards."""
    job = generation.enqueue(
        db, user, source_type="topic", target_deck_id=deck, topic="história", now=NOW
    )
    generation.complete(
        db,
        job.id,
        GeneratedCards(status="needs_specification", cards=[], reason="amplo demais"),
        now=NOW,
    )

    assert db.get(GenerationJob, job.id).error_code == str(ErrorCode.TOPIC_TOO_VAGUE)
    assert quota.remaining(db, user, at=NOW) == 1


def test_a_job_where_every_card_is_dropped_costs_nothing(db, user, deck):
    job = generation.enqueue(
        db, user, source_type="topic", target_deck_id=deck, topic="t", now=NOW
    )
    generation.complete(
        db,
        job.id,
        GeneratedCards(status="ok", cards=[{"front": "a" * 500, "back": "b"}]),
        now=NOW,
    )

    assert db.get(GenerationJob, job.id).error_code == str(ErrorCode.MATERIAL_INSUFFICIENT)
    assert quota.remaining(db, user, at=NOW) == 1


def test_token_usage_is_recorded_even_on_failure(db, user, deck):
    """§7.7 — without real figures, repricing is guesswork plus a migration."""
    job = generation.enqueue(
        db, user, source_type="photo", target_deck_id=deck, upload_key="k", now=NOW
    )
    generation.complete(
        db,
        job.id,
        GeneratedCards(status="ok", cards=[], refused=True, tokens_in=4784, tokens_out=0),
        now=NOW,
    )
    stored = db.get(GenerationJob, job.id)
    assert stored.tokens_in == 4784


def test_an_infrastructure_failure_returns_the_allowance(db, user, deck):
    job = generation.enqueue(
        db, user, source_type="topic", target_deck_id=deck, topic="t", now=NOW
    )
    generation.fail(db, job.id, ErrorCode.NETWORK_UNAVAILABLE, "timeout", now=NOW)
    assert quota.remaining(db, user, at=NOW) == 1


# ---------------------------------------------------------------------------
# The approval queue (§5.7, §7.8)
# ---------------------------------------------------------------------------


@pytest.fixture
def ready_job(db: Session, user: str, deck: str):
    job = generation.enqueue(
        db, user, source_type="topic", target_deck_id=deck, topic="t", now=NOW
    )
    generation.complete(db, job.id, GeneratedCards(status="ok", cards=good_cards(4)), now=NOW)
    return job


def test_nothing_reaches_cards_without_a_decision(db, user, ready_job):
    """§2.2 — enforced structurally, not by convention."""
    created = generation.materialise(db, user, ready_job.id, device_id=DEVICE, now=NOW)
    assert created == 0


def test_approving_creates_a_card_reusing_the_pending_id(db, user, ready_job):
    queue = generation.queue_for(db, user, ready_job.id)
    generation.decide(db, user, queue[0].id, "approved", now=NOW)

    created = generation.materialise(db, user, ready_job.id, device_id=DEVICE, now=NOW)
    assert created == 1

    card = db.get(Card, queue[0].id)
    assert card is not None, "the card must reuse the pending id"
    assert card.front == queue[0].front


def test_materialising_twice_does_not_duplicate(db, user, ready_job):
    """Idempotent by construction, because the id is reused."""
    queue = generation.queue_for(db, user, ready_job.id)
    generation.decide(db, user, queue[0].id, "approved", now=NOW)

    generation.materialise(db, user, ready_job.id, device_id=DEVICE, now=NOW)
    again = generation.materialise(db, user, ready_job.id, device_id=DEVICE, now=NOW)
    assert again == 0


def test_discarding_never_creates_a_card(db, user, ready_job):
    queue = generation.queue_for(db, user, ready_job.id)
    for pending in queue:
        generation.decide(db, user, pending.id, "discarded", now=NOW)

    assert generation.materialise(db, user, ready_job.id, device_id=DEVICE, now=NOW) == 0


def test_undo_restores_the_undecided_state(db, user, ready_job):
    """§5.7 — undo is mandatory, because the gesture errs."""
    queue = generation.queue_for(db, user, ready_job.id)
    generation.decide(db, user, queue[0].id, "discarded", now=NOW)
    generation.decide(db, user, queue[0].id, None)

    restored = generation.queue_for(db, user, ready_job.id)[0]
    assert restored.decision is None
    assert restored.decided_at is None


def test_approve_remaining_only_touches_undecided_cards(db, user, ready_job):
    queue = generation.queue_for(db, user, ready_job.id)
    generation.decide(db, user, queue[0].id, "discarded", now=NOW)

    approved = generation.approve_remaining(db, user, ready_job.id, now=NOW)
    assert approved == 3, "the discarded card must stay discarded"

    decisions = [p.decision for p in generation.queue_for(db, user, ready_job.id)]
    assert decisions.count("approved") == 3
    assert decisions.count("discarded") == 1


def test_an_abandoned_queue_survives(db, user, ready_job):
    """§5.7 — leaving mid-triage must not discard silently."""
    queue = generation.queue_for(db, user, ready_job.id)
    generation.decide(db, user, queue[0].id, "approved", now=NOW)

    resumed = generation.queue_for(db, user, ready_job.id)
    assert sum(1 for p in resumed if p.decision is None) == 3
    assert len(resumed) == 4, "the counter needs the full total, not just what is left"


def test_one_account_cannot_decide_on_anothers_queue(db, user, ready_job):
    intruder = uid()
    db.execute(text("INSERT INTO users (id) VALUES (:id)"), {"id": intruder})
    queue = generation.queue_for(db, user, ready_job.id)

    # `JobNotFound` e não `Exception`: a asserção genérica passaria também se
    # `decide` estourasse por qualquer outro motivo — um erro de digitação no
    # id, um schema fora de sincronia. Nomear a exceção é o que prova que a
    # recusa veio da checagem de dono.
    with pytest.raises(generation.JobNotFound):
        generation.decide(db, intruder, queue[0].id, "approved", now=NOW)

    assert generation.queue_for(db, intruder, ready_job.id) == []
