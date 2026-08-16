"""Queue consumer.

The queue is a Postgres table claimed with SELECT ... FOR UPDATE SKIP LOCKED
(§4.2), so the worker needs the same database access as the API and runs from
the same image with a different command (§11.7).

The work itself is [app.generation.runner.run_one]; this file is only the loop
around it. That split is what lets a test run a whole job with an ordinary
session and a fake client, without a process, a signal handler or a sleep.
"""

import logging
import os
import pathlib
import signal
import sys
import time
from types import FrameType

import anthropic

from app.config import get_settings
from app.db import SessionLocal, check_connection
from app.generation import runner

logger = logging.getLogger("worker")

# Liveness for a process with no HTTP server. The container healthcheck reads
# this file's age, so it proves the loop is turning — not merely that the
# process exists, which is all a `pgrep` would tell you.
HEARTBEAT_PATH = pathlib.Path(os.getenv("WORKER_HEARTBEAT", "/tmp/worker-heartbeat"))

_shutdown = False


def _beat() -> None:
    HEARTBEAT_PATH.write_text(str(time.time()), encoding="utf-8")


def _handle_signal(signum: int, _frame: FrameType | None) -> None:
    global _shutdown
    logger.info("received signal %s, shutting down", signum)
    _shutdown = True


def main() -> int:
    settings = get_settings()
    logging.basicConfig(
        level=settings.log_level,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    # Boot check: a worker that cannot reach the database is not "running".
    deadline = time.monotonic() + 30
    while not check_connection():
        if time.monotonic() > deadline:
            logger.error("database unreachable after 30s; exiting")
            return 1
        logger.info("waiting for the database…")
        time.sleep(1)

    if not settings.anthropic_api_key:
        # Better to refuse to start than to claim jobs and fail every one of
        # them — a failed job refunds, but the user still watched it fail.
        logger.error("ANTHROPIC_API_KEY is not set; the worker has nothing to call")
        return 1

    client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

    _beat()
    logger.info("worker ready")

    poll_seconds = float(os.getenv("WORKER_POLL_SECONDS", "5"))
    while not _shutdown:
        _beat()
        try:
            with SessionLocal() as session:
                handled = runner.run_one(session, client)
        except Exception:  # noqa: BLE001 — one bad job must not stop the loop
            logger.exception("job failed unexpectedly")
            handled = None

        # Only sleep when the queue was empty. A backlog is drained as fast as
        # the model answers, not one job per poll interval.
        if handled is None:
            time.sleep(poll_seconds)

    logger.info("worker stopped cleanly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
