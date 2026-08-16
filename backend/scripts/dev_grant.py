#!/usr/bin/env python3
"""Raise an account's generation allowance, for development.

    docker compose run --rm --entrypoint python server scripts/dev_grant.py --latest
    docker compose run --rm --entrypoint python server scripts/dev_grant.py --device <id>
    docker compose run --rm --entrypoint python server scripts/dev_grant.py --latest --reset

**This is not the subscription.** §5.13's billing is a human gate: it needs
products configured in both stores, a sandbox account and a signed build, and
until that exists the paywall's buttons stay disabled. What this does is
narrower and honest about it — it raises `quota_usage.limit_count` for one
account so generation can be exercised repeatedly, which is what testing the
model actually needs.

Nothing about the plan changes: `plan` is still `free` everywhere, the paywall
still exists, and the 402 path is still reachable by setting the limit back to
one. That matters, because a fake premium state would make the one flow most
worth testing untestable.

Refuses to run against a production database, because a script that grants
free generations is exactly the sort of thing that gets run in the wrong shell.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

# Python puts the *script's* directory on the path, not the working directory,
# so `app` is not importable from here without help. Doing it in the file
# rather than in a PYTHONPATH the caller has to remember.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from sqlalchemy import select, text, update  # noqa: E402

from app.config import get_settings  # noqa: E402
from app.contract import FREE_GENERATIONS_LIFETIME  # noqa: E402
from app.db import SessionLocal  # noqa: E402
from app.models import Device, QuotaUsage  # noqa: E402
from app.quota.service import _ensure_row  # noqa: E402

PERIOD = "lifetime"


def main() -> int:
    parser = argparse.ArgumentParser()
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--device", help="the device_id the app generated")
    target.add_argument(
        "--latest",
        action="store_true",
        help="the most recently registered device — usually the emulator",
    )
    parser.add_argument("--limit", type=int, default=1000, help="generations to allow")
    parser.add_argument(
        "--reset",
        action="store_true",
        help=f"back to the real free tier ({FREE_GENERATIONS_LIFETIME}), unused",
    )
    args = parser.parse_args()

    settings = get_settings()
    if settings.is_production:
        print("refusing: ENVIRONMENT is production", file=sys.stderr)
        return 1

    with SessionLocal() as session:
        if args.latest:
            device = session.execute(
                select(Device)
                .where(Device.user_id.is_not(None))
                .order_by(text("ctid DESC"))
                .limit(1)
            ).scalar_one_or_none()
        else:
            device = session.get(Device, args.device)

        if device is None or device.user_id is None:
            print("no registered device found", file=sys.stderr)
            return 1

        user_id = device.user_id
        limit = FREE_GENERATIONS_LIFETIME if args.reset else args.limit

        _ensure_row(session, user_id, PERIOD, limit)
        session.execute(
            update(QuotaUsage)
            .where(QuotaUsage.user_id == user_id, QuotaUsage.period_key == PERIOD)
            # `used` goes back to zero as well: raising the ceiling under an
            # account that already spent its one generation would otherwise
            # leave it one short of where the number suggests.
            .values(limit_count=limit, used=0, reserved=0)
        )

        # §8.4 keeps this on the device across account deletion. Clearing it
        # here as well, or a delete-and-reregister in testing would hand the
        # new account an exhausted quota and look like the grant had failed.
        device.free_grant_spent = args.reset
        session.commit()

        row = session.execute(
            select(QuotaUsage).where(
                QuotaUsage.user_id == user_id, QuotaUsage.period_key == PERIOD
            )
        ).scalar_one()

    print(f"device {device.id}")
    print(f"user   {user_id}")
    print(f"quota  {row.limit_count - row.used - row.reserved} de {row.limit_count}")
    print()
    print("O app lê isto de /v1/quota/ — reabra a tela para atualizar.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
