"""§8.4 — export and deletion.

The product is Brazilian, so both are LGPD rights rather than features. What is
worth testing is not that the endpoints answer: it is that the export is
complete enough to be worth the name, that deletion actually deletes past an
append-only table designed to refuse it, and that deletion does not become a
way to mint a second free generation.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from app.auth import service as auth
from app.db import SessionLocal
from app.generation import service as generation
from app.main import app
from app.models import Device, Review, User
from app.quota import service as quota
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
    def __init__(self, user_id: str, token: str, deck_id: str, device_id: str):
        self.user_id = user_id
        self.token = token
        self.deck_id = deck_id
        self.device_id = device_id

    @property
    def headers(self) -> dict:
        return {"Authorization": f"Bearer {self.token}"}


def make_account(*, device_id: str | None = None) -> Account:
    device_id = device_id or uid()
    with SessionLocal() as session:
        pair = auth.register_device(
            session, device_id=device_id, platform="android", attested=True
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
        card_id = uid()
        sync.push(
            session,
            user_id,
            "cards",
            [
                {
                    "id": card_id,
                    "deck_id": deck_id,
                    "front": "Pergunta",
                    "back": "Resposta",
                    "updated_at": NOW,
                    "device_id": DEVICE,
                    "tags": [],
                }
            ],
        )
        sync.push(
            session,
            user_id,
            "reviews",
            [
                {
                    "id": uid(),
                    "card_id": card_id,
                    "reviewed_at": NOW,
                    "grade": 3,
                    "source": "standard",
                    "device_id": DEVICE,
                }
            ],
        )
        session.commit()
    return Account(user_id, pair.access_token, deck_id, device_id)


@pytest.fixture
def account() -> Account:
    return make_account()


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------


def test_export_is_the_whole_thing_not_a_summary(client, account: Account):
    body = client.get("/v1/account/export", headers=account.headers).json()

    # §3 makes the review log the source of truth and everything else derived
    # from it, so an export without it is a souvenir.
    assert body["reviews"], "the log is the point"
    assert body["decks"] and body["cards"]
    assert body["format_version"] == 1


def test_export_carries_no_other_account(client, account: Account):
    stranger = make_account()
    body = client.get("/v1/account/export", headers=account.headers).json()

    assert [d["id"] for d in body["decks"]] == [account.deck_id]
    assert stranger.deck_id not in [d["id"] for d in body["decks"]]


def test_export_needs_a_token(client):
    assert client.get("/v1/account/export").status_code == 401


def test_exported_timestamps_use_the_wire_format(client, account: Account):
    # §6.4 — milliseconds, so an export can be read back by the same code that
    # reads a sync payload rather than by a second parser nobody maintains.
    review = client.get("/v1/account/export", headers=account.headers).json()["reviews"][0]
    assert isinstance(review["reviewed_at"], int)
    assert review["reviewed_at"] > 1_000_000_000_000


# ---------------------------------------------------------------------------
# Deletion
# ---------------------------------------------------------------------------


def test_deletion_gets_past_the_append_only_reviews_table(client, account: Account):
    # §5.2 makes reviews immutable on purpose; §8.4 is the one sanctioned way
    # around it, and it has to actually work rather than fail on a trigger.
    response = client.post(
        "/v1/account/delete", headers=account.headers, json={"confirm": "APAGAR"}
    )
    assert response.status_code == 200
    assert response.json()["deleted"]["reviews"] >= 1

    with SessionLocal() as session:
        assert session.get(User, account.user_id) is None
        assert (
            session.execute(
                text("SELECT count(*) FROM reviews WHERE user_id = :u"),
                {"u": account.user_id},
            ).scalar_one()
            == 0
        )


def test_a_mis_tap_cannot_delete_an_account(client, account: Account):
    for confirm in ["", "apagar", "sim", "DELETE"]:
        response = client.post(
            "/v1/account/delete", headers=account.headers, json={"confirm": confirm}
        )
        assert response.status_code == 400, confirm

    with SessionLocal() as session:
        assert session.get(User, account.user_id) is not None


def test_deleting_one_account_leaves_the_others_alone(client, account: Account):
    stranger = make_account()

    client.post("/v1/account/delete", headers=account.headers, json={"confirm": "APAGAR"})

    with SessionLocal() as session:
        assert session.get(User, stranger.user_id) is not None
        assert (
            session.execute(
                text("SELECT count(*) FROM reviews WHERE user_id = :u"),
                {"u": stranger.user_id},
            ).scalar_one()
            >= 1
        )


def test_deleting_and_registering_again_does_not_mint_a_free_generation(client):
    """The hole §8.1 exists to close, reached by a different route.

    A reinstall must not grant a second free generation; deleting the account
    and registering the same device again is the same attack with an extra
    step.
    """
    account = make_account()

    with SessionLocal() as session:
        generation.enqueue(
            session,
            account.user_id,
            source_type="topic",
            target_deck_id=account.deck_id,
            topic="Revolução Gloriosa",
            now=NOW,
        )
        # Spend it for real: the reservation has to be committed, not just
        # taken, or the sweeper would give it back.
        reservation = session.execute(
            text(
                "SELECT id FROM quota_reservations WHERE user_id = :u ORDER BY id DESC LIMIT 1"
            ),
            {"u": account.user_id},
        ).scalar_one()
        quota.commit(session, reservation)
        session.commit()
        assert quota.remaining(session, account.user_id) == 0

    client.post("/v1/account/delete", headers=account.headers, json={"confirm": "APAGAR"})

    with SessionLocal() as session:
        pair = auth.register_device(
            session, device_id=account.device_id, platform="android", attested=True
        )
        session.commit()
        new_user, _ = auth.verify_access_token(pair.access_token)

        assert new_user != account.user_id, "a genuinely new account"
        assert quota.remaining(session, new_user) == 0, (
            "the device remembers that its free generation was spent"
        )


def test_a_device_that_never_generated_still_gets_its_allowance(client):
    """The other half: deletion must not punish someone who never used it."""
    account = make_account()
    client.post("/v1/account/delete", headers=account.headers, json={"confirm": "APAGAR"})

    with SessionLocal() as session:
        pair = auth.register_device(
            session, device_id=account.device_id, platform="android", attested=True
        )
        session.commit()
        new_user, _ = auth.verify_access_token(pair.access_token)
        assert quota.remaining(session, new_user) == 1


def test_the_detached_device_keeps_nothing_personal(client, account: Account):
    """Retaining an identifier for anti-abuse is defensible; retaining a person
    is not. So what survives is checked, not assumed."""
    client.post("/v1/account/delete", headers=account.headers, json={"confirm": "APAGAR"})

    with SessionLocal() as session:
        device = session.get(Device, account.device_id)
        assert device is not None
        assert device.user_id is None
        # A random client-generated id, a platform string and two booleans.
        assert not session.query(Review).filter_by(user_id=account.user_id).count()
