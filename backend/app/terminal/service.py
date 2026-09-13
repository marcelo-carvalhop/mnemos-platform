from __future__ import annotations

import hashlib
import secrets
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.contract import ReviewSource
from app.models import Card, CardFlags, Deck, TerminalCredential
from app.sync import service as sync_service


class TerminalAuthError(Exception):
    pass


class TerminalScopeError(Exception):
    pass


class TerminalCapacityError(Exception):
    pass


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _owned_active_decks(session: Session, user_id: str, deck_ids: list[str]) -> list[str]:
    requested = list(dict.fromkeys(deck_ids))
    if not requested:
        return []

    owned = set(
        session.execute(
            select(Deck.id).where(
                Deck.user_id == user_id,
                Deck.id.in_(requested),
                Deck.deleted_at.is_(None),
                Deck.archived_at.is_(None),
            )
        ).scalars()
    )
    missing = [deck_id for deck_id in requested if deck_id not in owned]
    if missing:
        raise TerminalScopeError(f"decks are not available to this user: {missing}")
    return requested


def _owned_decks_any_state(session: Session, user_id: str, deck_ids: list[str]) -> list[str]:
    requested = list(dict.fromkeys(deck_ids))
    if not requested:
        return []
    owned = set(
        session.execute(
            select(Deck.id).where(Deck.user_id == user_id, Deck.id.in_(requested))
        ).scalars()
    )
    missing = [deck_id for deck_id in requested if deck_id not in owned]
    if missing:
        raise TerminalScopeError(f"decks do not belong to this user: {missing}")
    return requested


def register_terminal(
    session: Session,
    user_id: str,
    device_id: str,
    model: str,
    firmware: str,
    deck_ids: list[str],
) -> str:
    """Creates or rotates a credential scoped to one physical terminal."""
    selected_decks = _owned_active_decks(session, user_id, deck_ids)
    token = secrets.token_urlsafe(32)
    row = session.get(TerminalCredential, device_id)
    if row is None:
        row = TerminalCredential(
            device_id=device_id,
            user_id=user_id,
            token_hash=_hash(token),
            model=model,
            firmware=firmware,
            deck_ids=selected_decks,
            revoked=False,
        )
        session.add(row)
    else:
        if row.user_id != user_id:
            raise TerminalAuthError("terminal belongs to another user")
        row.token_hash = _hash(token)
        row.model = model
        row.firmware = firmware
        row.deck_ids = selected_decks
        row.revoked = False
    session.commit()
    return token


def authenticate_terminal(session: Session, token: str) -> TerminalCredential:
    digest = _hash(token)
    row = session.execute(
        select(TerminalCredential).where(
            TerminalCredential.token_hash == digest,
            TerminalCredential.revoked.is_(False),
        )
    ).scalar_one_or_none()
    if row is None:
        raise TerminalAuthError("invalid terminal credential")
    row.last_seen_at = datetime.now(UTC)
    session.commit()
    return row


def _iso(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def snapshot(session: Session, credential: TerminalCredential, limit: int = 48) -> dict:
    """Returns the full canonical content snapshot assigned to a terminal.

    A snapshot is never silently truncated. If the assigned library no longer
    fits the declared device capacity, the server reports a capacity conflict
    and the terminal keeps its previous atomic snapshot.
    """
    limit = max(1, min(limit, 256))
    user_id = credential.user_id
    selected_decks = set(credential.deck_ids or [])

    deck_rows = session.execute(
        select(Deck).where(
            Deck.user_id == user_id,
            Deck.id.in_(selected_decks),
            Deck.deleted_at.is_(None),
            Deck.archived_at.is_(None),
        ).order_by(Deck.name)
    ).scalars().all()
    deck_by_id = {d.id: d for d in deck_rows}

    if not deck_by_id:
        return {
            "schema": "mnemos.sync/v2",
            "exportedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            "decks": [],
            "cards": [],
            "states": [],
        }

    active_flags = select(CardFlags.card_id).where(
        CardFlags.user_id == user_id,
        CardFlags.status != "active",
    )
    card_rows = session.execute(
        select(Card).where(
            Card.user_id == user_id,
            Card.deck_id.in_(deck_by_id.keys()),
            Card.deleted_at.is_(None),
            ~Card.id.in_(active_flags),
        ).order_by(Card.updated_at.desc(), Card.id).limit(limit + 1)
    ).scalars().all()

    if len(card_rows) > limit:
        raise TerminalCapacityError(
            f"assigned library exceeds terminal capacity ({limit} cards)"
        )

    used_deck_ids = {c.deck_id for c in card_rows}
    decks = []
    for deck_id in sorted(used_deck_ids, key=lambda x: deck_by_id[x].name.lower()):
        d = deck_by_id[deck_id]
        decks.append(
            {
                "schema": "mnemos.deck/v2",
                "id": d.id,
                "name": d.name,
                "description": d.description,
                "metadata": {
                    "language": "pt-BR",
                    "updatedAt": _iso(d.updated_at),
                    "revision": max(1, int(d.server_seq)),
                },
            }
        )

    cards = []
    for c in card_rows:
        cards.append(
            {
                "schema": "mnemos.card/v2",
                "id": c.id,
                "deckId": c.deck_id,
                "type": "open_recall",
                "content": {
                    "prompt": {"format": "plain", "text": c.front},
                    "answer": {"format": "plain", "text": c.back},
                },
                "tags": list(c.tags or []),
                "metadata": {
                    "language": "pt-BR",
                    # The current app database does not have an independent
                    # creation timestamp. v0.3 uses updatedAt as a compatibility
                    # value until createdAt becomes first-class persistence.
                    "createdAt": _iso(c.updated_at),
                    "updatedAt": _iso(c.updated_at),
                    "revision": max(1, int(c.server_seq)),
                },
            }
        )

    return {
        "schema": "mnemos.sync/v2",
        "exportedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "decks": decks,
        "cards": cards,
        "states": [],
    }


def _validate_terminal_review(review: dict) -> None:
    required = {
        "schema",
        "id",
        "cardId",
        "reviewedAtMs",
        "schedulerRating",
        "source",
    }

    missing = sorted(
        required - review.keys()
    )

    if missing:
        raise ValueError(
            f"missing review fields: {missing}"
        )

    if review.get("schema") != "mnemos.review/v2":
        raise ValueError(
            "unsupported review schema"
        )

    valid_sources = {
        source.value
        for source in ReviewSource
    }

    if review.get("source") not in valid_sources:
        raise ValueError(
            "invalid review source"
        )

    if (
        not isinstance(review.get("id"), str)
        or not (1 <= len(review["id"]) <= 36)
    ):
        raise ValueError("invalid review id")

    if (
        not isinstance(review.get("cardId"), str)
        or not (1 <= len(review["cardId"]) <= 36)
    ):
        raise ValueError("invalid card id")

    if (
        not isinstance(review.get("reviewedAtMs"), int)
        or review["reviewedAtMs"] < 0
    ):
        raise ValueError("invalid reviewedAtMs")

    rating = review.get("schedulerRating")

    if (
        not isinstance(rating, int)
        or not (1 <= rating <= 4)
    ):
        raise ValueError(
            "invalid schedulerRating"
        )

    elapsed = review.get(
        "responseTimeMs",
        0,
    )

    if (
        not isinstance(elapsed, int)
        or elapsed < 0
    ):
        raise ValueError(
            "invalid responseTimeMs"
        )


def ingest_reviews(
    session: Session,
    credential: TerminalCredential,
    reviews: list[dict],
) -> dict:

    for review in reviews:
        _validate_terminal_review(review)

    card_ids = {
        str(review["cardId"])
        for review in reviews
    }

    if card_ids:
        allowed = set(
            session.execute(
                select(Card.id).where(
                    Card.user_id
                    == credential.user_id,
                    Card.deck_id.in_(
                        set(
                            credential.deck_ids
                            or []
                        )
                        |
                        set(
                            credential.reported_deck_ids
                            or []
                        )
                    ),
                    Card.deleted_at.is_(None),
                    Card.id.in_(card_ids),
                )
            ).scalars()
        )

        outside_scope = sorted(
            card_ids - allowed
        )

        if outside_scope:
            raise TerminalScopeError(
                "reviews reference cards outside "
                f"terminal scope: {outside_scope}"
            )

    rows: list[dict] = []

    for review in reviews:
        reviewed_at_ms = int(
            review["reviewedAtMs"]
        )

        due_after_ms = int(
            review.get(
                "dueAfterMs",
                reviewed_at_ms,
            )
            or reviewed_at_ms
        )

        interval_days_after = max(
            0,
            (
                due_after_ms
                - reviewed_at_ms
            )
            // 86_400_000,
        )

        rows.append(
            {
                "id": str(review["id"]),
                "card_id": str(
                    review["cardId"]
                ),
                "reviewed_at":
                    reviewed_at_ms,
                "grade": int(
                    review[
                        "schedulerRating"
                    ]
                ),
                "source": str(
                    review["source"]
                ),
                "elapsed_ms": int(
                    review.get(
                        "responseTimeMs",
                        0,
                    )
                ),
                "device_id":
                    credential.device_id,
                "interval_days_after":
                    interval_days_after,
                "stability_after":
                    review.get(
                        "stabilityAfterDays"
                    ),
                "difficulty_after":
                    review.get(
                        "difficultyAfter"
                    ),
                # FSRS-6.
                "scheduler_version": 6,
                "app_version":
                    credential.firmware,
            }
        )

    result = sync_service.push(
        session,
        credential.user_id,
        "reviews",
        rows,
    )

    session.commit()

    return {
        "accepted": result.applied,
        "duplicates":
            result.skipped_stale,
        "highWater":
            result.high_water,
        "assigned":
            result.assigned,
    }


def pull_reviews(
    session: Session,
    credential: TerminalCredential,
    *,
    since_seq: int,
    limit: int = 500,
) -> dict:
    """
    Pulls account review history using the same server_seq
    cursor as Web/App, but exposes only cards inside this
    terminal's content scope.

    Rows emitted by this same terminal are omitted from the
    payload because they already exist in local history.
    The cursor still advances across them.
    """

    rows, cursor = sync_service.pull(
        session,
        credential.user_id,
        "reviews",
        since_seq=since_seq,
        limit=limit,
    )

    scope_decks = (
        set(credential.deck_ids or [])
        |
        set(
            credential.reported_deck_ids
            or []
        )
    )

    card_ids = {
        str(row["card_id"])
        for row in rows
    }

    if card_ids and scope_decks:
        allowed = set(
            session.execute(
                select(Card.id).where(
                    Card.user_id
                    == credential.user_id,
                    Card.deck_id.in_(
                        scope_decks
                    ),
                    Card.deleted_at.is_(
                        None
                    ),
                    Card.id.in_(card_ids),
                )
            ).scalars()
        )
    else:
        allowed = set()

    reviews: list[dict] = []

    for row in rows:
        card_id = str(
            row["card_id"]
        )

        if card_id not in allowed:
            continue

        # O evento local já existe no terminal.
        if (
            row.get("device_id")
            == credential.device_id
        ):
            continue

        reviews.append(
            {
                "schema":
                    "mnemos.review/v2",
                "id": str(row["id"]),
                "cardId": card_id,
                "reviewedAtMs": int(
                    row["reviewed_at"]
                ),
                "schedulerRating": int(
                    row["grade"]
                ),
                "source": str(
                    row["source"]
                ),
                "responseTimeMs": int(
                    row.get(
                        "elapsed_ms",
                        0,
                    )
                    or 0
                ),
                "stabilityAfterDays":
                    row.get(
                        "stability_after"
                    ),
                "difficultyAfter":
                    row.get(
                        "difficulty_after"
                    ),
                "serverSeq": int(
                    row["server_seq"]
                ),
                "deviceId": str(
                    row["device_id"]
                ),
                "affectsSchedule": True,
            }
        )

    return {
        "schema":
            "mnemos.review-delta/v2",
        "reviews": reviews,
        "cursor": cursor,
        # hasMore refere-se ao fluxo bruto server_seq,
        # não ao subconjunto visível ao terminal.
        "hasMore":
            len(rows) == limit,
    }



def pull_progress_resets(
    session: Session,
    credential: TerminalCredential,
    *,
    since_seq: int,
    limit: int = 500,
) -> dict:
    """
    Pulls schedule-reset events visible to this terminal.

    The server_seq cursor advances over the canonical account
    history even when a row is outside this terminal's deck scope.
    """

    rows, cursor = sync_service.pull(
        session,
        credential.user_id,
        "progress_resets",
        since_seq=since_seq,
        limit=limit,
    )

    scope_decks = (
        set(credential.deck_ids or [])
        |
        set(
            credential.reported_deck_ids
            or []
        )
    )

    card_ids = {
        str(row["card_id"])
        for row in rows
    }

    if card_ids and scope_decks:
        allowed = set(
            session.execute(
                select(Card.id).where(
                    Card.user_id
                    == credential.user_id,
                    Card.deck_id.in_(
                        scope_decks
                    ),
                    Card.deleted_at.is_(None),
                    Card.id.in_(card_ids),
                )
            ).scalars()
        )
    else:
        allowed = set()

    resets: list[dict] = []

    for row in rows:
        card_id = str(
            row["card_id"]
        )

        if card_id not in allowed:
            continue

        # Mantemos esta regra desde já para que uma futura
        # implementação de reset no próprio T5 seja idempotente.
        if (
            row.get("device_id")
            == credential.device_id
        ):
            continue

        resets.append(
            {
                "schema":
                    "mnemos.progress-reset/v2",
                "id": str(row["id"]),
                "cardId": card_id,
                "resetAtMs": int(
                    row["reset_at"]
                ),
                "serverSeq": int(
                    row["server_seq"]
                ),
                "deviceId": str(
                    row["device_id"]
                ),
            }
        )

    return {
        "schema":
            "mnemos.progress-reset-delta/v2",
        "resets": resets,
        "cursor": cursor,
        "hasMore":
            len(rows) == limit,
    }



_TERMINAL_PEDAGOGICAL_SETTINGS = {
    "desired_retention",
}


def pull_user_settings(
    session: Session,
    credential: TerminalCredential,
    *,
    since_seq: int,
    limit: int = 500,
) -> dict:
    """
    Pulls only settings that alter deterministic study
    behaviour on the terminal.

    Cosmetic/app-specific preferences deliberately do not
    cross this boundary.
    """

    rows, cursor = sync_service.pull(
        session,
        credential.user_id,
        "user_settings",
        since_seq=since_seq,
        limit=limit,
    )

    settings: list[dict] = []

    for row in rows:
        key = str(
            row["key"]
        )

        if (
            key not in
            _TERMINAL_PEDAGOGICAL_SETTINGS
        ):
            continue

        settings.append(
            {
                "schema":
                    "mnemos.user-setting/v2",
                "key": key,
                "value": str(
                    row["value"]
                ),
                "updatedAtMs": int(
                    row["updated_at"]
                ),
                "serverSeq": int(
                    row["server_seq"]
                ),
                "deviceId": str(
                    row["device_id"]
                ),
            }
        )

    return {
        "schema":
            "mnemos.user-setting-delta/v2",
        "settings": settings,
        "cursor": cursor,
        "hasMore":
            len(rows) == limit,
    }


def terminal_for_user(session: Session, user_id: str, device_id: str) -> TerminalCredential:
    row = session.get(TerminalCredential, device_id)
    if row is None or row.user_id != user_id:
        raise TerminalScopeError("terminal is not registered to this user")
    return row


def update_desired_decks(
    session: Session, user_id: str, device_id: str, deck_ids: list[str]
) -> TerminalCredential:
    row = terminal_for_user(session, user_id, device_id)
    row.deck_ids = _owned_active_decks(session, user_id, deck_ids)
    session.commit()
    session.refresh(row)
    return row


def report_status(
    session: Session,
    credential: TerminalCredential,
    *,
    reported_deck_ids: list[str],
    card_count: int,
    max_cards: int,
    connectivity: str | None,
    wifi_ssid: str | None,
    library_revision: int,
    synced: bool,
) -> TerminalCredential:
    # A terminal may only report content that belongs to its desired scope. A
    # transient old snapshot is allowed during reconciliation, but it cannot
    # grant itself access to reviews/cards outside that scope.
    credential.reported_deck_ids = _owned_decks_any_state(
        session, credential.user_id, reported_deck_ids
    )
    credential.card_count = max(0, card_count)
    credential.max_cards = max(0, max_cards)
    credential.connectivity = connectivity
    credential.wifi_ssid = wifi_ssid or None
    credential.library_revision = max(0, library_revision)
    if synced:
        credential.last_sync_at = datetime.now(UTC)
    session.commit()
    session.refresh(credential)
    return credential


def observe_direct_sync(
    session: Session,
    user_id: str,
    device_id: str,
    *,
    reported_deck_ids: list[str],
    card_count: int,
    max_cards: int,
) -> TerminalCredential:
    row = terminal_for_user(session, user_id, device_id)
    row.reported_deck_ids = _owned_decks_any_state(session, user_id, reported_deck_ids)
    row.card_count = max(0, card_count)
    row.max_cards = max(0, max_cards)
    row.connectivity = "ble"
    row.last_sync_at = datetime.now(UTC)
    session.commit()
    session.refresh(row)
    return row


def list_terminals(session: Session, user_id: str) -> list[TerminalCredential]:
    return list(
        session.execute(
            select(TerminalCredential).where(
                TerminalCredential.user_id == user_id
            ).order_by(TerminalCredential.created_at.desc(), TerminalCredential.device_id)
        ).scalars()
    )


def revoke_terminal(session: Session, user_id: str, device_id: str) -> None:
    row = session.get(TerminalCredential, device_id)
    if row is None or row.user_id != user_id:
        raise TerminalScopeError("terminal is not registered to this user")
    row.revoked = True
    session.commit()
