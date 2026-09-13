from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy.orm import Session, sessionmaker

from app.db import engine
from app.models import User
from app.sync import service as sync_service
from app.terminal import service as terminal_service


SessionFactory = sessionmaker(
    bind=engine,
    expire_on_commit=False,
)

NOW = datetime(
    2026,
    8,
    29,
    12,
    0,
    tzinfo=timezone.utc,
)

PHONE = "11111111-1111-7111-8111-111111111111"


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

    db.add(User(id=user_id))
    db.flush()

    return user_id


def deck_row(
    deck_id: str,
    *,
    name: str,
    device_id: str = PHONE,
) -> dict:
    return {
        "id": deck_id,
        "name": name,
        "updated_at": NOW,
        "device_id": device_id,
        "origin": "own",
        "version": 1,
    }


def card_row(
    card_id: str,
    deck_id: str,
    *,
    front: str = "Pergunta",
    device_id: str = PHONE,
) -> dict:
    return {
        "id": card_id,
        "deck_id": deck_id,
        "front": front,
        "back": "Resposta",
        "tags": [],
        "updated_at": NOW,
        "device_id": device_id,
    }


def canonical_review(
    review_id: str,
    card_id: str,
    reviewed_at_ms: int,
    *,
    rating: int = 3,
) -> dict:
    return {
        "schema": "mnemos.review/v2",
        "id": review_id,
        "cardId": card_id,
        "reviewedAtMs": reviewed_at_ms,
        "schedulerRating": rating,
        "source": "standard",
        "responseTimeMs": 1200,
        "stabilityAfterDays": 3.2602,
        "difficultyAfter": 4.884631634813845,
        "affectsSchedule": True,
    }


def create_terminal_with_card(
    db: Session,
    user_id: str,
) -> tuple[object, str, str]:

    deck_id = uid()
    card_id = uid()

    sync_service.push(
        db,
        user_id,
        "decks",
        [
            deck_row(
                deck_id,
                name="Baralho T5",
            )
        ],
    )

    sync_service.push(
        db,
        user_id,
        "cards",
        [
            card_row(
                card_id,
                deck_id,
            )
        ],
    )

    terminal_id = uid()

    token = terminal_service.register_terminal(
        db,
        user_id,
        terminal_id,
        "LILYGO T5 4.7 S3",
        "0.6-test",
        [deck_id],
    )

    credential = (
        terminal_service.authenticate_terminal(
            db,
            token,
        )
    )

    return credential, deck_id, card_id


def test_terminal_review_v2_enters_canonical_history(
    db: Session,
    user: str,
):
    credential, _, card_id = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    review_id = uid()
    reviewed_at_ms = int(
        NOW.timestamp() * 1000
    )

    result = terminal_service.ingest_reviews(
        db,
        credential,
        [
            canonical_review(
                review_id,
                card_id,
                reviewed_at_ms,
            )
        ],
    )

    assert result["accepted"] == 1
    assert result["duplicates"] == 0

    rows, _ = sync_service.pull(
        db,
        user,
        "reviews",
        since_seq=0,
    )

    matching = [
        row
        for row in rows
        if row["id"] == review_id
    ]

    assert len(matching) == 1

    row = matching[0]

    assert row["card_id"] == card_id
    assert row["grade"] == 3
    assert row["source"] == "standard"
    assert row["device_id"] == credential.device_id
    assert row["reviewed_at"] == reviewed_at_ms
    assert row["scheduler_version"] == 6


def test_retrying_terminal_review_is_idempotent(
    db: Session,
    user: str,
):
    credential, _, card_id = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    review = canonical_review(
        uid(),
        card_id,
        int(NOW.timestamp() * 1000),
    )

    first = terminal_service.ingest_reviews(
        db,
        credential,
        [review],
    )

    second = terminal_service.ingest_reviews(
        db,
        credential,
        [review],
    )

    assert first["accepted"] == 1

    assert second["accepted"] == 0
    assert second["duplicates"] == 1

    rows, _ = sync_service.pull(
        db,
        user,
        "reviews",
        since_seq=0,
    )

    matching = [
        row
        for row in rows
        if row["id"] == review["id"]
    ]

    assert len(matching) == 1


def test_terminal_pulls_review_from_other_device(
    db: Session,
    user: str,
):
    credential, _, card_id = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    remote_id = uid()

    remote_time = (
        NOW +
        timedelta(minutes=5)
    )

    sync_service.push(
        db,
        user,
        "reviews",
        [
            {
                "id": remote_id,
                "card_id": card_id,
                "reviewed_at": remote_time,
                "grade": 4,
                "source": "standard",
                "elapsed_ms": 800,
                "device_id": PHONE,
                "interval_days_after": 15,
                "stability_after": 20.0,
                "difficulty_after": 4.0,
                "scheduler_version": 6,
                "app_version": "web-test",
            }
        ],
    )

    delta = terminal_service.pull_reviews(
        db,
        credential,
        since_seq=0,
        limit=500,
    )

    assert delta["schema"] == (
        "mnemos.review-delta/v2"
    )

    assert len(delta["reviews"]) == 1

    review = delta["reviews"][0]

    assert review["id"] == remote_id
    assert review["cardId"] == card_id
    assert review["schedulerRating"] == 4
    assert review["source"] == "standard"
    assert review["deviceId"] == PHONE
    assert review["affectsSchedule"] is True

    assert delta["cursor"] > 0


def test_terminal_does_not_receive_its_own_review_back(
    db: Session,
    user: str,
):
    credential, _, card_id = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    local = canonical_review(
        uid(),
        card_id,
        int(NOW.timestamp() * 1000),
    )

    terminal_service.ingest_reviews(
        db,
        credential,
        [local],
    )

    delta = terminal_service.pull_reviews(
        db,
        credential,
        since_seq=0,
        limit=500,
    )

    assert delta["reviews"] == []

    # O cursor precisa avançar mesmo pelo evento omitido,
    # senão o T5 puxaria a mesma página para sempre.
    assert delta["cursor"] > 0


def test_terminal_review_cursor_is_incremental(
    db: Session,
    user: str,
):
    credential, _, card_id = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    first_id = uid()

    sync_service.push(
        db,
        user,
        "reviews",
        [
            {
                "id": first_id,
                "card_id": card_id,
                "reviewed_at": NOW,
                "grade": 3,
                "source": "standard",
                "device_id": PHONE,
            }
        ],
    )

    first = terminal_service.pull_reviews(
        db,
        credential,
        since_seq=0,
        limit=500,
    )

    assert [
        row["id"]
        for row in first["reviews"]
    ] == [first_id]

    cursor = first["cursor"]

    second_id = uid()

    sync_service.push(
        db,
        user,
        "reviews",
        [
            {
                "id": second_id,
                "card_id": card_id,
                "reviewed_at":
                    NOW + timedelta(minutes=1),
                "grade": 2,
                "source": "standard",
                "device_id": PHONE,
            }
        ],
    )

    second = terminal_service.pull_reviews(
        db,
        credential,
        since_seq=cursor,
        limit=500,
    )

    assert [
        row["id"]
        for row in second["reviews"]
    ] == [second_id]

    assert second["cursor"] > cursor


def test_terminal_cannot_pull_review_outside_assigned_scope(
    db: Session,
    user: str,
):
    credential, _, _ = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    other_deck = uid()
    other_card = uid()
    review_id = uid()

    sync_service.push(
        db,
        user,
        "decks",
        [
            deck_row(
                other_deck,
                name="Fora do T5",
            )
        ],
    )

    sync_service.push(
        db,
        user,
        "cards",
        [
            card_row(
                other_card,
                other_deck,
            )
        ],
    )

    sync_service.push(
        db,
        user,
        "reviews",
        [
            {
                "id": review_id,
                "card_id": other_card,
                "reviewed_at": NOW,
                "grade": 3,
                "source": "standard",
                "device_id": PHONE,
            }
        ],
    )

    delta = terminal_service.pull_reviews(
        db,
        credential,
        since_seq=0,
        limit=500,
    )

    assert all(
        row["id"] != review_id
        for row in delta["reviews"]
    )

    # Ainda assim, o watermark global avança.
    assert delta["cursor"] > 0


def test_terminal_pulls_progress_reset_from_other_device(
    db: Session,
    user: str,
):
    credential, _, card_id = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    reset_id = uid()
    reset_at = NOW + timedelta(minutes=10)

    sync_service.push(
        db,
        user,
        "progress_resets",
        [
            {
                "id": reset_id,
                "card_id": card_id,
                "reset_at": reset_at,
                "device_id": PHONE,
            }
        ],
    )

    delta = terminal_service.pull_progress_resets(
        db,
        credential,
        since_seq=0,
        limit=500,
    )

    assert delta["schema"] == (
        "mnemos.progress-reset-delta/v2"
    )

    assert len(delta["resets"]) == 1

    reset = delta["resets"][0]

    assert reset["id"] == reset_id
    assert reset["cardId"] == card_id
    assert reset["deviceId"] == PHONE

    assert reset["resetAtMs"] == int(
        reset_at.timestamp() * 1000
    )

    assert reset["serverSeq"] > 0
    assert delta["cursor"] > 0


def test_terminal_progress_reset_respects_deck_scope(
    db: Session,
    user: str,
):
    credential, _, _ = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    other_deck = uid()
    other_card = uid()
    reset_id = uid()

    sync_service.push(
        db,
        user,
        "decks",
        [
            deck_row(
                other_deck,
                name="Reset fora do T5",
            )
        ],
    )

    sync_service.push(
        db,
        user,
        "cards",
        [
            card_row(
                other_card,
                other_deck,
            )
        ],
    )

    sync_service.push(
        db,
        user,
        "progress_resets",
        [
            {
                "id": reset_id,
                "card_id": other_card,
                "reset_at": NOW,
                "device_id": PHONE,
            }
        ],
    )

    delta = terminal_service.pull_progress_resets(
        db,
        credential,
        since_seq=0,
        limit=500,
    )

    assert all(
        row["id"] != reset_id
        for row in delta["resets"]
    )

    # O cursor global continua avançando.
    assert delta["cursor"] > 0


def test_terminal_progress_reset_cursor_is_incremental(
    db: Session,
    user: str,
):
    credential, _, card_id = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    first_id = uid()

    sync_service.push(
        db,
        user,
        "progress_resets",
        [
            {
                "id": first_id,
                "card_id": card_id,
                "reset_at": NOW,
                "device_id": PHONE,
            }
        ],
    )

    first = terminal_service.pull_progress_resets(
        db,
        credential,
        since_seq=0,
        limit=500,
    )

    assert [
        row["id"]
        for row in first["resets"]
    ] == [first_id]

    cursor = first["cursor"]

    second_id = uid()

    sync_service.push(
        db,
        user,
        "progress_resets",
        [
            {
                "id": second_id,
                "card_id": card_id,
                "reset_at":
                    NOW + timedelta(minutes=1),
                "device_id": PHONE,
            }
        ],
    )

    second = terminal_service.pull_progress_resets(
        db,
        credential,
        since_seq=cursor,
        limit=500,
    )

    assert [
        row["id"]
        for row in second["resets"]
    ] == [second_id]

    assert second["cursor"] > cursor



def test_terminal_pulls_desired_retention(
    db: Session,
    user: str,
):
    credential, _, _ = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    sync_service.push(
        db,
        user,
        "user_settings",
        [
            {
                "key": "desired_retention",
                "value": "0.93",
                "updated_at": NOW,
                "device_id": PHONE,
            }
        ],
    )

    delta = terminal_service.pull_user_settings(
        db,
        credential,
        since_seq=0,
        limit=500,
    )

    assert delta["schema"] == (
        "mnemos.user-setting-delta/v2"
    )

    assert len(delta["settings"]) == 1

    setting = delta["settings"][0]

    assert setting["key"] == (
        "desired_retention"
    )

    assert setting["value"] == "0.93"

    assert setting["serverSeq"] > 0
    assert delta["cursor"] > 0


def test_terminal_ignores_non_pedagogical_setting(
    db: Session,
    user: str,
):
    credential, _, _ = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    sync_service.push(
        db,
        user,
        "user_settings",
        [
            {
                "key": "timezone",
                "value": "America/Sao_Paulo",
                "updated_at": NOW,
                "device_id": PHONE,
            }
        ],
    )

    delta = terminal_service.pull_user_settings(
        db,
        credential,
        since_seq=0,
        limit=500,
    )

    assert delta["settings"] == []

    # O cursor precisa avançar mesmo por uma preferência
    # que o terminal deliberadamente não consome.
    assert delta["cursor"] > 0


def test_terminal_desired_retention_is_incremental_lww(
    db: Session,
    user: str,
):
    credential, _, _ = (
        create_terminal_with_card(
            db,
            user,
        )
    )

    sync_service.push(
        db,
        user,
        "user_settings",
        [
            {
                "key": "desired_retention",
                "value": "0.90",
                "updated_at": NOW,
                "device_id": PHONE,
            }
        ],
    )

    first = terminal_service.pull_user_settings(
        db,
        credential,
        since_seq=0,
        limit=500,
    )

    assert (
        first["settings"][0]["value"]
        == "0.90"
    )

    cursor = first["cursor"]

    sync_service.push(
        db,
        user,
        "user_settings",
        [
            {
                "key": "desired_retention",
                "value": "0.94",
                "updated_at":
                    NOW + timedelta(minutes=1),
                "device_id": PHONE,
            }
        ],
    )

    second = terminal_service.pull_user_settings(
        db,
        credential,
        since_seq=cursor,
        limit=500,
    )

    assert len(second["settings"]) == 1

    assert (
        second["settings"][0]["value"]
        == "0.94"
    )

    assert second["cursor"] > cursor
