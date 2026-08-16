"""Sync (§6). No FastAPI here — this is called by a router and, later, by
tooling that has no request (§4.2).

Two merge rules, chosen to match the value of the data:

  history  — union. `INSERT ... ON CONFLICT DO NOTHING`. Conflict is
             impossible by construction, which is what the high-volume,
             irreplaceable data deserves.
  entities — row-level last-writer-wins on `updated_at`, tie-broken by
             `device_id`, tombstoned by `deleted_at`.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Any

from sqlalchemy import Date, DateTime, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.models import (
    Card,
    CardFlags,
    Deck,
    GoalHistory,
    ProgressReset,
    Review,
    UserSetting,
    UserSyncState,
)

# §6.3 — tombstones are kept this long, then collected. A device offline
# longer than the window would resurrect deleted rows, so it is told to resync
# instead.
TOMBSTONE_RETENTION = timedelta(days=90)

# Append-only: merged by union, never overwritten.
HISTORY_TABLES: dict[str, Any] = {
    "reviews": Review,
    "progress_resets": ProgressReset,
    "goal_history": GoalHistory,
}

# Mutable: merged by last-writer-wins.
ENTITY_TABLES: dict[str, Any] = {
    "decks": Deck,
    "cards": Card,
    "card_flags": CardFlags,
    "user_settings": UserSetting,
}

TABLES: dict[str, Any] = {**HISTORY_TABLES, **ENTITY_TABLES}

# Composite keys, where the primary key is not simply `id`.
PRIMARY_KEYS: dict[str, tuple[str, ...]] = {
    "card_flags": ("card_id",),
    "user_settings": ("user_id", "key"),
}


class ResyncRequired(Exception):
    """The device's cursor predates the tombstone horizon (§6.3)."""


class OwnershipError(Exception):
    """A pushed row referenced something the pusher does not own (§5.5)."""


@dataclass(frozen=True)
class PushResult:
    applied: int
    skipped_stale: int
    high_water: int

    # Row key → the server_seq that row now carries. The client cannot clear
    # its outbox without this: `server_seq IS NULL` is what "not yet synced"
    # means locally (§6.2), so a push that does not say which row got which
    # sequence leaves every row pending and the outbox never drains.
    assigned: dict[str, int] = field(default_factory=dict)


def _pk(table: str) -> tuple[str, ...]:
    return PRIMARY_KEYS.get(table, ("id",))


# ---------------------------------------------------------------------------
# The wire format (§6.4)
# ---------------------------------------------------------------------------
#
# SQLite has no date and no timestamp; the client stores instants as integer
# milliseconds since the epoch and local dates as "YYYY-MM-DD" text. Postgres
# has both types and should keep them — a timestamptz column is what makes the
# retention queries and the tombstone horizon expressible at all.
#
# So something has to convert, and it converts here, once, at the edge. Two
# earlier attempts at this protocol each assumed the other side's
# representation and neither test suite could notice: the Python tests passed
# `datetime` objects a real client never sends, and the Dart tests answered
# with a fake server that echoed whatever it was given. The first live round
# trip failed with "cannot cast type bigint to timestamp with time zone".
#
# Milliseconds rather than ISO-8601 on purpose. `updated_at` decides
# last-writer-wins, so the two sides must compare exactly the same value;
# integers compare exactly, while ISO strings invite a parser to round
# microseconds or to drop an offset.


def _epoch_ms(value: datetime) -> int:
    return int(value.timestamp() * 1000)


def _from_epoch_ms(value: int) -> datetime:
    return datetime.fromtimestamp(value / 1000, tz=timezone.utc)


def _to_database(table: str, row: dict) -> dict:
    """Wire → Postgres."""
    columns = TABLES[table].__table__.columns
    converted = {}
    for key, value in row.items():
        column = columns.get(key)
        if value is None or column is None:
            converted[key] = value
        elif isinstance(column.type, DateTime) and isinstance(value, int):
            converted[key] = _from_epoch_ms(value)
        elif isinstance(column.type, Date) and isinstance(value, str):
            converted[key] = date.fromisoformat(value)
        else:
            converted[key] = value
    return converted


def _to_wire(table: str, row: dict) -> dict:
    """Postgres → wire. The inverse, and it has to stay the inverse."""
    columns = TABLES[table].__table__.columns
    converted = {}
    for key, value in row.items():
        column = columns.get(key)
        if value is None or column is None:
            converted[key] = value
        elif isinstance(value, datetime):
            converted[key] = _epoch_ms(value)
        elif isinstance(value, date):
            converted[key] = value.isoformat()
        else:
            converted[key] = value
    return converted


def _client_key(table: str) -> str:
    """The column the client identifies a row by.

    The last component of the primary key, not the first: `user_settings` is
    keyed `(user_id, key)` server-side, and the client — which holds one
    user's rows — knows it only as `key`.
    """
    return _pk(table)[-1]


def _allocate(session: Session, user_id: str, count: int) -> int:
    """Reserves `count` sequence values and returns the first.

    Taken under `FOR UPDATE` so concurrent pushes from the same account
    serialise. See UserSyncState for why a global sequence is not enough.
    """
    state = session.execute(
        select(UserSyncState).where(UserSyncState.user_id == user_id).with_for_update()
    ).scalar_one_or_none()

    if state is None:
        state = UserSyncState(user_id=user_id, last_seq=0)
        session.add(state)
        session.flush()

    first = state.last_seq + 1
    state.last_seq += count
    session.flush()
    return first


def _verify_ownership(session: Session, user_id: str, table: str, rows: list[dict]) -> None:
    """Ids come from the client, so parentage is checked, never trusted (§5.5)."""
    if table == "cards":
        deck_ids = {r["deck_id"] for r in rows}
        owned = set(
            session.execute(
                select(Deck.id).where(Deck.user_id == user_id, Deck.id.in_(deck_ids))
            ).scalars()
        )
        if deck_ids - owned:
            raise OwnershipError(f"decks not owned by user: {sorted(deck_ids - owned)}")

    if table in {"reviews", "progress_resets", "card_flags"}:
        card_ids = {r["card_id"] for r in rows}
        owned = set(
            session.execute(
                select(Card.id).where(Card.user_id == user_id, Card.id.in_(card_ids))
            ).scalars()
        )
        if card_ids - owned:
            raise OwnershipError(f"cards not owned by user: {sorted(card_ids - owned)}")


def push(session: Session, user_id: str, table: str, rows: list[dict]) -> PushResult:
    """Applies a chunk. Idempotent: replaying it changes nothing (§6.4)."""
    if table not in TABLES:
        raise ValueError(f"unknown table: {table}")
    if not rows:
        return PushResult(applied=0, skipped_stale=0, high_water=0)

    model = TABLES[table]
    _verify_ownership(session, user_id, table, rows)

    first_seq = _allocate(session, user_id, len(rows))
    applied = skipped = 0
    high_water = first_seq - 1
    assigned: dict[str, int] = {}
    stale_keys: list = []

    for offset, row in enumerate(rows):
        payload = _to_database(table, row)
        payload["user_id"] = user_id
        seq = first_seq + offset
        payload["server_seq"] = seq

        key_column = getattr(model, _client_key(table))

        if table in HISTORY_TABLES:
            # Union. A replayed push inserts nothing and is not an error —
            # append-only history makes retry harmless by construction.
            statement = (
                pg_insert(model)
                .values(**payload)
                .on_conflict_do_nothing(index_elements=_pk(table))
                .returning(key_column)
            )
        else:
            # Last-writer-wins, tie-broken by device_id so two devices writing
            # in the same millisecond still converge on the same answer.
            base = pg_insert(model).values(**payload)
            statement = base.on_conflict_do_update(
                index_elements=_pk(table),
                set_={k: base.excluded[k] for k in payload if k not in _pk(table)},
                where=(
                    (model.updated_at < base.excluded.updated_at)
                    | (
                        (model.updated_at == base.excluded.updated_at)
                        & (model.device_id < base.excluded.device_id)
                    )
                ),
            ).returning(key_column)

        # RETURNING, not rowcount. psycopg3 reports rowcount as -1 here, which
        # is truthy — reading it made every push look applied, including the
        # replays and the stale writes this function exists to reject.
        # RETURNING yields a row only when something actually happened.
        returned = session.execute(statement).first()
        if returned is not None:
            applied += 1
            high_water = seq
            assigned[str(returned[0])] = seq
        else:
            skipped += 1
            stale_keys.append(row.get(_client_key(table)))

    if stale_keys:
        # A row rejected as stale still has to leave the client's outbox, or
        # it is pushed again on every sync forever. Handing back the winning
        # row's sequence does that: the row stops being pending, and the next
        # pull overwrites its contents with the version that won.
        for key, seq in session.execute(
            select(getattr(model, _client_key(table)), model.server_seq).where(
                model.user_id == user_id,
                getattr(model, _client_key(table)).in_(stale_keys),
            )
        ).all():
            if seq is not None:
                assigned[str(key)] = seq

    return PushResult(
        applied=applied, skipped_stale=skipped, high_water=high_water, assigned=assigned
    )


def pull(
    session: Session,
    user_id: str,
    table: str,
    since_seq: int,
    limit: int = 500,
) -> tuple[list[dict], int]:
    """Keyset delta over `(server_seq, id)` (§6.2).

    Filtering on `updated_at` would lose rows two ways — a slow device clock
    writes below a watermark another device already passed, and a long
    transaction commits after a later one started. `server_seq` is the
    server's, so neither applies.
    """
    if table not in TABLES:
        raise ValueError(f"unknown table: {table}")

    _guard_resync(session, user_id, since_seq)

    model = TABLES[table]
    rows = session.execute(
        select(model)
        .where(model.user_id == user_id, model.server_seq > since_seq)
        .order_by(model.server_seq, *[getattr(model, c) for c in _pk(table)])
        .limit(limit)
    ).scalars().all()

    payload = [
        _to_wire(
            table,
            {
                column.name: getattr(row, column.name)
                for column in model.__table__.columns
                if column.name != "user_id"
            },
        )
        for row in rows
    ]
    cursor = payload[-1]["server_seq"] if payload else since_seq
    return payload, cursor


def _guard_resync(session: Session, user_id: str, since_seq: int) -> None:
    """§6.3 — a cursor older than the tombstone horizon cannot be trusted.

    Answering normally would silently resurrect rows deleted while the device
    was away. This is one branch decided now and a painful migration if
    discovered in production.
    """
    if since_seq == 0:
        return  # bootstrap: nothing to resurrect

    horizon = datetime.now(timezone.utc) - TOMBSTONE_RETENTION
    stale = session.execute(
        select(Deck.id)
        .where(
            Deck.user_id == user_id,
            Deck.deleted_at.is_not(None),
            Deck.deleted_at < horizon,
            Deck.server_seq > since_seq,
        )
        .limit(1)
    ).first()
    if stale is not None:
        raise ResyncRequired(
            "cursor predates the tombstone horizon; discard the local mirror and pull from zero"
        )
