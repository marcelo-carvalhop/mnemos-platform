"""Sync verification (§6, plan wave 2c).

Runs against the real Postgres, because the things under test — ON CONFLICT
semantics, FOR UPDATE serialisation, the append-only triggers — are database
behaviour, not Python behaviour. A SQLite double would pass while production
failed.
"""

from __future__ import annotations

import os
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from app.sync import service
from app.sync.service import OwnershipError, ResyncRequired

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg://flashcards:change-me-locally@postgres:5432/flashcards",
)

engine = create_engine(DATABASE_URL, future=True)
SessionFactory = sessionmaker(bind=engine, expire_on_commit=False)

NOW = datetime(2026, 8, 9, 12, 0, tzinfo=UTC)
PHONE = "11111111-1111-7111-8111-111111111111"
TABLET = "22222222-2222-7222-8222-222222222222"


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


def deck_row(deck_id: str, name: str, at: datetime, device: str) -> dict:
    return {
        "id": deck_id,
        "name": name,
        "updated_at": at,
        "device_id": device,
        "origin": "own",
        "version": 1,
    }


def card_row(card_id: str, deck_id: str, front: str, at: datetime, device: str) -> dict:
    return {
        "id": card_id,
        "deck_id": deck_id,
        "front": front,
        "back": "verso",
        "tags": [],
        "updated_at": at,
        "device_id": device,
    }


def review_row(review_id: str, card_id: str, at: datetime, device: str, grade: int = 3) -> dict:
    return {
        "id": review_id,
        "card_id": card_id,
        "reviewed_at": at,
        "grade": grade,
        "source": "standard",
        "device_id": device,
    }


# ---------------------------------------------------------------------------
# The cursor (§6.2)
# ---------------------------------------------------------------------------


def test_server_seq_is_monotonic_and_assigned_by_the_server(db, user):
    ids = [uid() for _ in range(5)]
    result = service.push(
        db, user, "decks", [deck_row(i, f"b{n}", NOW, PHONE) for n, i in enumerate(ids)]
    )
    assert result.applied == 5

    rows, cursor = service.pull(db, user, "decks", since_seq=0)
    seqs = [r["server_seq"] for r in rows]
    assert seqs == sorted(seqs)
    assert len(set(seqs)) == 5
    assert cursor == max(seqs)


def test_pull_is_a_delta_not_a_full_dump(db, user):
    first = uid()
    service.push(db, user, "decks", [deck_row(first, "um", NOW, PHONE)])
    _, cursor = service.pull(db, user, "decks", since_seq=0)

    second = uid()
    service.push(db, user, "decks", [deck_row(second, "dois", NOW, PHONE)])

    rows, _ = service.pull(db, user, "decks", since_seq=cursor)
    assert [r["id"] for r in rows] == [second]


def test_a_slow_device_clock_does_not_lose_rows(db, user):
    """§6.2 — the reason the cursor is not `updated_at`.

    The second device's clock is ten minutes behind. With a timestamp cursor
    its row sorts below a watermark the first device already passed and is
    never pulled again. With server_seq the row is simply newer.
    """
    _, cursor = service.pull(db, user, "decks", since_seq=0)

    service.push(db, user, "decks", [deck_row(uid(), "pontual", NOW, PHONE)])
    _, cursor = service.pull(db, user, "decks", since_seq=cursor)

    behind = uid()
    stale_clock = NOW - timedelta(minutes=10)
    service.push(db, user, "decks", [deck_row(behind, "atrasado", stale_clock, TABLET)])

    rows, _ = service.pull(db, user, "decks", since_seq=cursor)
    assert [r["id"] for r in rows] == [behind]


# ---------------------------------------------------------------------------
# History is a union (§6.1)
# ---------------------------------------------------------------------------


def test_history_merges_by_union_and_replay_is_harmless(db, user):
    deck_id, card_id = uid(), uid()
    service.push(db, user, "decks", [deck_row(deck_id, "b", NOW, PHONE)])
    service.push(db, user, "cards", [card_row(card_id, deck_id, "f", NOW, PHONE)])

    rows = [review_row(uid(), card_id, NOW, PHONE) for _ in range(3)]
    first = service.push(db, user, "reviews", rows)
    assert first.applied == 3

    # A retry after a timeout must not double-insert (§6.4).
    again = service.push(db, user, "reviews", rows)
    assert again.applied == 0
    assert again.skipped_stale == 3

    pulled, _ = service.pull(db, user, "reviews", since_seq=0)
    assert len(pulled) == 3


def test_two_devices_reviewing_offline_converge_to_the_union(db, user):
    deck_id, card_id = uid(), uid()
    service.push(db, user, "decks", [deck_row(deck_id, "b", NOW, PHONE)])
    service.push(db, user, "cards", [card_row(card_id, deck_id, "f", NOW, PHONE)])

    phone = [review_row(uid(), card_id, NOW + timedelta(minutes=i), PHONE) for i in range(3)]
    tablet = [review_row(uid(), card_id, NOW + timedelta(minutes=i), TABLET) for i in range(3, 6)]

    service.push(db, user, "reviews", phone)
    service.push(db, user, "reviews", tablet)

    pulled, _ = service.pull(db, user, "reviews", since_seq=0)
    assert len(pulled) == 6, "no review may be lost — this is the irreplaceable data"


def test_history_is_pullable_at_all(db, user):
    """The defect the technical review caught: reviews were push-only.

    A second device never learned what the first had studied, and a reinstall
    lost everything. If this test disappears, that regression is silent.
    """
    deck_id, card_id = uid(), uid()
    service.push(db, user, "decks", [deck_row(deck_id, "b", NOW, PHONE)])
    service.push(db, user, "cards", [card_row(card_id, deck_id, "f", NOW, PHONE)])
    service.push(db, user, "reviews", [review_row(uid(), card_id, NOW, PHONE)])

    pulled, _ = service.pull(db, user, "reviews", since_seq=0)
    assert len(pulled) == 1


def test_reviews_reject_update_and_delete(db, user):
    """§5.2 / §12.1 — enforced by the database, not by convention."""
    deck_id, card_id, review_id = uid(), uid(), uid()
    service.push(db, user, "decks", [deck_row(deck_id, "b", NOW, PHONE)])
    service.push(db, user, "cards", [card_row(card_id, deck_id, "f", NOW, PHONE)])
    service.push(db, user, "reviews", [review_row(review_id, card_id, NOW, PHONE)])
    db.commit()

    with SessionFactory() as other:
        with pytest.raises(Exception, match="append-only"):
            other.execute(text("UPDATE reviews SET grade = 1 WHERE id = :i"), {"i": review_id})
            other.commit()

    with SessionFactory() as other:
        with pytest.raises(Exception, match="append-only"):
            other.execute(text("DELETE FROM reviews WHERE id = :i"), {"i": review_id})
            other.commit()


# ---------------------------------------------------------------------------
# Entities are last-writer-wins (§6.1)
# ---------------------------------------------------------------------------


def test_the_later_edit_wins(db, user):
    deck_id = uid()
    service.push(db, user, "decks", [deck_row(deck_id, "antigo", NOW, PHONE)])
    service.push(
        db, user, "decks", [deck_row(deck_id, "novo", NOW + timedelta(minutes=5), TABLET)]
    )

    rows, _ = service.pull(db, user, "decks", since_seq=0)
    assert [r["name"] for r in rows] == ["novo"]


def test_a_stale_edit_is_rejected(db, user):
    deck_id = uid()
    service.push(db, user, "decks", [deck_row(deck_id, "novo", NOW, PHONE)])
    result = service.push(
        db, user, "decks", [deck_row(deck_id, "velho", NOW - timedelta(minutes=5), TABLET)]
    )

    assert result.applied == 0
    rows, _ = service.pull(db, user, "decks", since_seq=0)
    assert rows[0]["name"] == "novo"


def test_the_same_millisecond_resolves_deterministically(db, user):
    """Ties break on device_id, so both devices reach the same answer."""
    deck_id = uid()
    service.push(db, user, "decks", [deck_row(deck_id, "do-phone", NOW, PHONE)])
    service.push(db, user, "decks", [deck_row(deck_id, "do-tablet", NOW, TABLET)])

    rows, _ = service.pull(db, user, "decks", since_seq=0)
    # TABLET sorts above PHONE, so it wins — the point is that it is decided,
    # not that a particular device wins.
    assert rows[0]["name"] == "do-tablet"

    # And the reverse order reaches the same state.
    other = uid()
    service.push(db, user, "decks", [deck_row(other, "do-tablet", NOW, TABLET)])
    service.push(db, user, "decks", [deck_row(other, "do-phone", NOW, PHONE)])
    rows, _ = service.pull(db, user, "decks", since_seq=0)
    assert {r["id"]: r["name"] for r in rows}[other] == "do-tablet"


def test_a_deleted_row_syncs_as_a_tombstone(db, user):
    deck_id = uid()
    service.push(db, user, "decks", [deck_row(deck_id, "b", NOW, PHONE)])

    tombstone = deck_row(deck_id, "b", NOW + timedelta(minutes=1), PHONE)
    tombstone["deleted_at"] = NOW + timedelta(minutes=1)
    service.push(db, user, "decks", [tombstone])

    rows, _ = service.pull(db, user, "decks", since_seq=0)
    assert rows[0]["deleted_at"] is not None, "deletion must travel, not just vanish"


def test_flags_and_content_do_not_overwrite_each_other(db, user):
    """§5.1 — why card_flags is a separate row.

    Burying on the phone while fixing a typo on the tablet must not discard
    either. In one row with row-level LWW, one of the two would be lost.
    """
    deck_id, card_id = uid(), uid()
    service.push(db, user, "decks", [deck_row(deck_id, "b", NOW, PHONE)])
    service.push(db, user, "cards", [card_row(card_id, deck_id, "original", NOW, PHONE)])

    service.push(
        db,
        user,
        "card_flags",
        [
            {
                "card_id": card_id,
                "status": "buried",
                "buried_until": NOW + timedelta(days=1),
                "updated_at": NOW + timedelta(minutes=1),
                "device_id": PHONE,
            }
        ],
    )
    service.push(
        db,
        user,
        "cards",
        [card_row(card_id, deck_id, "corrigido", NOW + timedelta(minutes=2), TABLET)],
    )

    cards, _ = service.pull(db, user, "cards", since_seq=0)
    flags, _ = service.pull(db, user, "card_flags", since_seq=0)
    assert cards[0]["front"] == "corrigido"
    assert flags[0]["status"] == "buried"


def test_tags_removed_offline_stay_removed(db, user):
    """§5.1 — tags as a column, not a join table.

    A join table has nowhere to put a tombstone, so a removed tag reappears on
    the next sync.
    """
    deck_id, card_id = uid(), uid()
    service.push(db, user, "decks", [deck_row(deck_id, "b", NOW, PHONE)])

    with_tags = card_row(card_id, deck_id, "f", NOW, PHONE)
    with_tags["tags"] = ["historia", "revolucao"]
    service.push(db, user, "cards", [with_tags])

    without = card_row(card_id, deck_id, "f", NOW + timedelta(minutes=1), PHONE)
    without["tags"] = ["historia"]
    service.push(db, user, "cards", [without])

    rows, _ = service.pull(db, user, "cards", since_seq=0)
    assert rows[0]["tags"] == ["historia"]


# ---------------------------------------------------------------------------
# Ownership (§5.5)
# ---------------------------------------------------------------------------


def test_a_client_cannot_write_into_another_account(db, user):
    """Ids are client-generated, so parentage is verified, never trusted."""
    intruder = uid()
    db.execute(text("INSERT INTO users (id) VALUES (:id)"), {"id": intruder})
    victim_deck = uid()
    service.push(db, user, "decks", [deck_row(victim_deck, "meu", NOW, PHONE)])

    with pytest.raises(OwnershipError):
        service.push(db, intruder, "cards", [card_row(uid(), victim_deck, "f", NOW, TABLET)])


def test_a_review_for_someone_elses_card_is_rejected(db, user):
    intruder = uid()
    db.execute(text("INSERT INTO users (id) VALUES (:id)"), {"id": intruder})
    deck_id, card_id = uid(), uid()
    service.push(db, user, "decks", [deck_row(deck_id, "b", NOW, PHONE)])
    service.push(db, user, "cards", [card_row(card_id, deck_id, "f", NOW, PHONE)])

    with pytest.raises(OwnershipError):
        service.push(db, intruder, "reviews", [review_row(uid(), card_id, NOW, TABLET)])


def test_pull_never_leaks_another_account(db, user):
    other = uid()
    db.execute(text("INSERT INTO users (id) VALUES (:id)"), {"id": other})
    service.push(db, user, "decks", [deck_row(uid(), "meu", NOW, PHONE)])
    service.push(db, other, "decks", [deck_row(uid(), "dele", NOW, TABLET)])

    rows, _ = service.pull(db, other, "decks", since_seq=0)
    assert [r["name"] for r in rows] == ["dele"]


# ---------------------------------------------------------------------------
# Forced resync (§6.3)
# ---------------------------------------------------------------------------


def test_a_cursor_past_the_tombstone_horizon_forces_a_resync(db, user):
    deck_id = uid()
    service.push(db, user, "decks", [deck_row(deck_id, "b", NOW, PHONE)])
    _, cursor = service.pull(db, user, "decks", since_seq=0)

    # The push must carry a *newer* updated_at or LWW rejects it and the row's
    # server_seq never advances past the cursor — which is what made the first
    # version of this test pass for the wrong reason.
    tombstone = deck_row(deck_id, "b", NOW + timedelta(minutes=1), PHONE)
    tombstone["deleted_at"] = NOW + timedelta(minutes=1)
    result = service.push(db, user, "decks", [tombstone])
    assert result.applied == 1, "the tombstone must actually land"

    # The deletion itself happened long ago in wall-clock terms: the device has
    # been offline past the retention window.
    ancient = datetime.now(UTC) - timedelta(days=120)
    db.execute(
        text("UPDATE decks SET deleted_at = :t WHERE id = :i"),
        {"t": ancient, "i": deck_id},
    )
    db.flush()

    with pytest.raises(ResyncRequired):
        service.pull(db, user, "decks", since_seq=cursor)


def test_bootstrap_from_zero_is_always_allowed(db, user):
    """A fresh device is exactly the state a resync produces (§6.5)."""
    deck_id = uid()
    ancient = datetime.now(UTC) - timedelta(days=120)
    service.push(db, user, "decks", [deck_row(deck_id, "b", NOW, PHONE)])
    db.execute(
        text("UPDATE decks SET deleted_at = :t WHERE id = :i"), {"t": ancient, "i": deck_id}
    )
    db.flush()

    rows, _ = service.pull(db, user, "decks", since_seq=0)
    assert len(rows) == 1


# ---------------------------------------------------------------------------
# What the client needs back in order to empty its outbox (§6.2)
# ---------------------------------------------------------------------------


def test_push_says_which_sequence_each_row_got(db: Session, user: str):
    """The gap that only appeared when the two halves were wired together.

    `server_seq IS NULL` is what "not yet synced" means on the client, so a
    push that reports only a high-water mark leaves every row pending and the
    outbox never drains — the client re-pushes the same rows forever.
    """
    ids = [uid() for _ in range(3)]
    result = service.push(
        db,
        user,
        "decks",
        [
            {
                "id": deck_id,
                "name": f"Baralho {i}",
                "updated_at": NOW,
                "device_id": PHONE,
                "origin": "own",
                "version": 1,
            }
            for i, deck_id in enumerate(ids)
        ],
    )

    assert set(result.assigned) == set(ids)
    assert sorted(result.assigned.values()) == [1, 2, 3]
    assert result.high_water == max(result.assigned.values())


def test_a_stale_row_still_gets_a_sequence_so_it_leaves_the_outbox(db: Session, user: str):
    """Otherwise the loser of a last-writer-wins is pushed on every sync,
    forever, because nothing ever marks it synced."""
    deck_id = uid()
    winner = {
        "id": deck_id,
        "name": "Vencedor",
        "updated_at": NOW + timedelta(minutes=5),
        "device_id": PHONE,
        "origin": "own",
        "version": 1,
    }
    service.push(db, user, "decks", [winner])

    loser = {**winner, "name": "Perdedor", "updated_at": NOW}
    result = service.push(db, user, "decks", [loser])

    assert result.applied == 0 and result.skipped_stale == 1
    # The row is not pending any more; the next pull replaces its contents
    # with the version that won.
    assert deck_id in result.assigned


def test_user_settings_are_keyed_the_way_the_client_knows_them(db: Session, user: str):
    """Server-side the key is (user_id, key); the client holds one user's rows
    and knows them by `key` alone."""
    result = service.push(
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
    assert list(result.assigned) == ["timezone"]
