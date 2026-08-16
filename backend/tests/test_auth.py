"""Auth verification (§8.1, §8.2) — end to end through the API."""

from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient

from app.auth import service
from app.main import app

client = TestClient(app)


def device_id() -> str:
    return str(uuid.uuid4())


def register() -> dict:
    response = client.post(
        "/v1/auth/device",
        json={"device_id": device_id(), "platform": "ios", "attestation": "stub"},
    )
    assert response.status_code == 200, response.text
    return response.json()


def auth_header(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# The anonymous period (§8.1)
# ---------------------------------------------------------------------------


def test_first_launch_yields_a_usable_account_without_credentials():
    body = register()
    assert body["user_id"]
    assert body["access_token"]
    assert body["token_type"] == "Bearer"

    # The token works immediately — the app is usable before signup.
    quota = client.get("/v1/quota/", headers=auth_header(body["access_token"]))
    assert quota.status_code == 200
    assert quota.json()["remaining"] == 1


def test_the_same_device_does_not_get_a_second_free_allowance():
    """§7.7.1 — with one generation per lifetime, this is the business model."""
    did = device_id()
    payload = {"device_id": did, "platform": "ios", "attestation": "stub"}

    first = client.post("/v1/auth/device", json=payload).json()
    second = client.post("/v1/auth/device", json=payload).json()

    assert first["user_id"] == second["user_id"], "re-registering must not mint a new account"


def test_signup_keeps_the_same_user_so_nothing_migrates():
    """§8.1 — the anonymous row *is* the account; it only gains credentials."""
    anon = register()
    email = f"{uuid.uuid4().hex}@exemplo.com"

    response = client.post(
        "/v1/auth/signup",
        json={"email": email, "password": "senha-bem-longa", "device_id": device_id()},
        headers=auth_header(anon["access_token"]),
    )
    assert response.status_code == 200, response.text
    assert response.json()["user_id"] == anon["user_id"], "signup must not move data"


def test_an_email_cannot_be_registered_twice():
    email = f"{uuid.uuid4().hex}@exemplo.com"
    first = register()
    client.post(
        "/v1/auth/signup",
        json={"email": email, "password": "senha-bem-longa", "device_id": device_id()},
        headers=auth_header(first["access_token"]),
    )

    second = register()
    response = client.post(
        "/v1/auth/signup",
        json={"email": email, "password": "outra-senha-longa", "device_id": device_id()},
        headers=auth_header(second["access_token"]),
    )
    assert response.status_code == 409


def test_login_from_another_device_reaches_the_same_account():
    anon = register()
    email = f"{uuid.uuid4().hex}@exemplo.com"
    client.post(
        "/v1/auth/signup",
        json={"email": email, "password": "senha-bem-longa", "device_id": device_id()},
        headers=auth_header(anon["access_token"]),
    )

    other = client.post(
        "/v1/auth/login",
        json={"email": email, "password": "senha-bem-longa", "device_id": device_id()},
    )
    assert other.status_code == 200
    assert other.json()["user_id"] == anon["user_id"]


def test_a_wrong_password_is_rejected():
    anon = register()
    email = f"{uuid.uuid4().hex}@exemplo.com"
    client.post(
        "/v1/auth/signup",
        json={"email": email, "password": "senha-bem-longa", "device_id": device_id()},
        headers=auth_header(anon["access_token"]),
    )

    response = client.post(
        "/v1/auth/login",
        json={"email": email, "password": "errada", "device_id": device_id()},
    )
    assert response.status_code == 401


def test_an_unknown_email_answers_like_a_wrong_password():
    """The endpoint must not double as a registered-address oracle."""
    response = client.post(
        "/v1/auth/login",
        json={"email": "ninguem@exemplo.com", "password": "qualquer", "device_id": device_id()},
    )
    assert response.status_code == 401


# ---------------------------------------------------------------------------
# Tokens (§8.2)
# ---------------------------------------------------------------------------


def test_refresh_rotates_the_token():
    body = register()
    rotated = client.post("/v1/auth/refresh", json={"refresh_token": body["refresh_token"]})
    assert rotated.status_code == 200
    assert rotated.json()["refresh_token"] != body["refresh_token"]


def test_reusing_a_rotated_token_revokes_the_whole_family():
    """§8.2 — a replayed token is either a leak or a blind retry, and we cannot
    tell which, so everything descended from that login goes."""
    body = register()
    rotated = client.post(
        "/v1/auth/refresh", json={"refresh_token": body["refresh_token"]}
    ).json()

    replay = client.post("/v1/auth/refresh", json={"refresh_token": body["refresh_token"]})
    assert replay.status_code == 401

    # The token issued by the legitimate rotation is revoked too.
    after = client.post("/v1/auth/refresh", json={"refresh_token": rotated["refresh_token"]})
    assert after.status_code == 401


def test_an_unknown_refresh_token_is_rejected():
    response = client.post("/v1/auth/refresh", json={"refresh_token": "inventado"})
    assert response.status_code == 401


def test_the_access_token_outlives_a_week_offline():
    """§8.2 — the app works offline; a short expiry would log the user out for
    being on the subway, which is the worst bug an offline-first product has."""
    assert service.ACCESS_TOKEN_TTL.days >= 7


def test_a_protected_route_rejects_a_missing_or_bad_token():
    assert client.get("/v1/quota/").status_code == 401
    assert client.get("/v1/quota/", headers={"Authorization": "Bearer lixo"}).status_code == 401
    assert client.get("/v1/quota/", headers={"Authorization": "Basic x"}).status_code == 401


# ---------------------------------------------------------------------------
# Sync through the API — the identity comes from the token, never the payload
# ---------------------------------------------------------------------------


def test_sync_push_and_pull_round_trip():
    body = register()
    headers = auth_header(body["access_token"])
    deck_id = str(uuid.uuid4())

    push = client.post(
        "/v1/sync/push",
        json={
            "table": "decks",
            "rows": [
                {
                    "id": deck_id,
                    "name": "História",
                    "updated_at": "2026-08-09T12:00:00Z",
                    "device_id": str(uuid.uuid4()),
                    "origin": "own",
                    "version": 1,
                }
            ],
        },
        headers=headers,
    )
    assert push.status_code == 200, push.text
    assert push.json()["applied"] == 1

    pull = client.get("/v1/sync/pull", params={"table": "decks", "since": 0}, headers=headers)
    assert pull.status_code == 200
    assert [r["id"] for r in pull.json()["rows"]] == [deck_id]


def test_one_account_cannot_pull_anothers_data():
    first = register()
    client.post(
        "/v1/sync/push",
        json={
            "table": "decks",
            "rows": [
                {
                    "id": str(uuid.uuid4()),
                    "name": "meu",
                    "updated_at": "2026-08-09T12:00:00Z",
                    "device_id": str(uuid.uuid4()),
                    "origin": "own",
                    "version": 1,
                }
            ],
        },
        headers=auth_header(first["access_token"]),
    )

    second = register()
    pull = client.get(
        "/v1/sync/pull",
        params={"table": "decks", "since": 0},
        headers=auth_header(second["access_token"]),
    )
    assert pull.json()["rows"] == []


def test_pushing_into_another_account_is_forbidden():
    """The deck id is real and valid — it just belongs to someone else."""
    victim = register()
    deck_id = str(uuid.uuid4())
    client.post(
        "/v1/sync/push",
        json={
            "table": "decks",
            "rows": [
                {
                    "id": deck_id,
                    "name": "meu",
                    "updated_at": "2026-08-09T12:00:00Z",
                    "device_id": str(uuid.uuid4()),
                    "origin": "own",
                    "version": 1,
                }
            ],
        },
        headers=auth_header(victim["access_token"]),
    )

    intruder = register()
    response = client.post(
        "/v1/sync/push",
        json={
            "table": "cards",
            "rows": [
                {
                    "id": str(uuid.uuid4()),
                    "deck_id": deck_id,
                    "front": "f",
                    "back": "v",
                    "tags": [],
                    "updated_at": "2026-08-09T12:00:00Z",
                    "device_id": str(uuid.uuid4()),
                }
            ],
        },
        headers=auth_header(intruder["access_token"]),
    )
    assert response.status_code == 403


def test_an_unknown_table_is_a_client_error_not_a_crash():
    body = register()
    response = client.get(
        "/v1/sync/pull",
        params={"table": "inventada", "since": 0},
        headers=auth_header(body["access_token"]),
    )
    assert response.status_code == 400


@pytest.mark.parametrize("route", ["/v1/sync/tables", "/v1/quota/"])
def test_every_new_route_requires_authentication(route: str):
    assert client.get(route).status_code == 401
