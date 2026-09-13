"""Export and deletion (§8.4).

The product is Brazilian, so the LGPD applies and both of these are rights
rather than features. Two consequences the code has to honour:

* **Export is the whole thing**, not a summary. It is also the honest answer to
  "what happens to my years of study if I stop paying" — the review log is the
  user's, and §3 makes it the only source of truth, so exporting it means the
  export is enough to reconstruct everything.
* **Deletion deletes.** §5.2 makes reviews append-only and revokes DELETE from
  the application role; this is the one sanctioned path around that, and it
  removes rather than anonymises. A single-user product has no analytical
  reason to keep orphaned history, and "anonymised" data that can be rejoined
  by device id is not anonymous.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import delete, select, text, update
from sqlalchemy.orm import Session

from app.models import (
    Card,
    CardFlags,
    Deck,
    Device,
    GenerationJob,
    GoalHistory,
    PendingCard,
    ProgressReset,
    QuotaReservation,
    QuotaUsage,
    RefreshToken,
    Review,
    User,
    UserSetting,
    UserSyncState,
)

logger = logging.getLogger(__name__)

# Deleted in this order: children before parents, so no foreign key has to be
# deferred and no cascade has to be trusted.
_OWNED = (
    PendingCard,
    GenerationJob,
    QuotaReservation,
    QuotaUsage,
    Review,
    ProgressReset,
    CardFlags,
    Card,
    Deck,
    GoalHistory,
    UserSetting,
    UserSyncState,
    RefreshToken,
)


def export(session: Session, user_id: str, *, now: datetime | None = None) -> dict[str, Any]:
    """Everything the account holds, as JSON.

    Deliberately the raw rows rather than a rendered report: §3 says the review
    log is the source of truth and everything else is derived from it, so the
    rows are what makes this an export instead of a souvenir.
    """
    now = now or datetime.now(UTC)

    def rows(model) -> list[dict[str, Any]]:
        return [
            {
                column.name: _plain(getattr(row, column.name))
                for column in model.__table__.columns
                if column.name != "user_id"
            }
            for row in session.execute(
                select(model).where(model.user_id == user_id)
            ).scalars()
        ]

    return {
        "exported_at": now.isoformat(),
        "format_version": 1,
        "decks": rows(Deck),
        "cards": rows(Card),
        "card_flags": rows(CardFlags),
        "reviews": rows(Review),
        "progress_resets": rows(ProgressReset),
        "goal_history": rows(GoalHistory),
        "user_settings": rows(UserSetting),
    }


def delete_account(session: Session, user_id: str) -> dict[str, int]:
    """Removes the account and everything it owns.

    Runs as the privileged path §5.2 reserves: the immutability trigger on
    `reviews` refuses DELETE, so it is disabled for this transaction only. That
    is narrower than granting the application role permission it would then
    hold for every other statement it ever runs.
    """
    removed: dict[str, int] = {}

    # Read before anything is deleted. `quota_usage` is one of the tables this
    # function removes, so asking it afterwards always answers "never spent" —
    # which is exactly the answer that reopens the hole below.
    spent = (
        session.execute(
            select(QuotaUsage.used).where(
                QuotaUsage.user_id == user_id, QuotaUsage.period_key == "lifetime"
            )
        ).scalar_one_or_none()
        or 0
    ) > 0

    # `session_replication_role = replica` switches triggers off for this
    # transaction and this connection. Scoped, reverted on commit, and it does
    # not touch what the application role is allowed to do the rest of the
    # time.
    session.execute(text("SET LOCAL session_replication_role = replica"))

    for model in _OWNED:
        result = session.execute(delete(model).where(model.user_id == user_id))
        if result.rowcount:
            removed[model.__tablename__] = result.rowcount

    # Devices are detached, not deleted, and remember one thing.
    #
    # §8.1 exists because a reinstall must not mint a second free generation;
    # deleting the account and registering again is the same attack with an
    # extra step. So the row survives with its user removed, carrying whether
    # the free allowance was already spent — a random client-generated id and
    # a boolean, with no name, no email and no study data attached to it.
    detached = session.execute(
        update(Device)
        .where(Device.user_id == user_id)
        .values(user_id=None, free_grant_spent=Device.free_grant_spent | spent)
    )
    if detached.rowcount:
        removed["devices_detached"] = detached.rowcount

    result = session.execute(delete(User).where(User.id == user_id))
    removed["users"] = result.rowcount or 0

    session.flush()
    logger.info("account %s deleted: %s", user_id, removed)
    return removed


def _plain(value: Any) -> Any:
    if isinstance(value, datetime):
        # Milliseconds, matching §6.4's wire format, so an export can be read
        # back by the same code that reads a sync payload.
        return int(value.timestamp() * 1000)
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value
