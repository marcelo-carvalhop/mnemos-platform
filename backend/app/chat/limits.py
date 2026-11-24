"""Per-user rate limit for the chat. No FastAPI here.

In memory, per process. The API runs as a single uvicorn process, so one
counter is the whole truth; a restart forgets the counts, which errs on the
side of the user. It exists to stop a runaway client or a script — the spend
ceiling itself lives in the Anthropic console.
"""

from __future__ import annotations

import threading
import time
from collections import deque

MINUTE = 60.0
DAY = 86_400.0


class RateLimited(Exception):
    """`scope` is "minute" or "day"; `retry_after` is in whole seconds."""

    def __init__(self, scope: str, retry_after: int) -> None:
        super().__init__(f"chat rate limit ({scope}), retry after {retry_after}s")
        self.scope = scope
        self.retry_after = retry_after


class SlidingWindowLimiter:
    """Timestamps of the last day's requests, per user.

    One deque serves both windows: the minute count is the tail of the day
    count. It never holds more than the daily cap, so memory per user is
    bounded no matter how hard a client hammers.
    """

    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def hit(
        self,
        user_id: str,
        *,
        per_minute: int,
        per_day: int,
        now: float | None = None,
    ) -> None:
        """Counts one request, or raises [RateLimited] without counting it."""
        now = time.monotonic() if now is None else now
        with self._lock:
            hits = self._hits.setdefault(user_id, deque())
            while hits and now - hits[0] >= DAY:
                hits.popleft()

            if per_day > 0 and len(hits) >= per_day:
                raise RateLimited("day", _seconds(hits[0] + DAY - now))

            recent = [t for t in hits if now - t < MINUTE]
            if per_minute > 0 and len(recent) >= per_minute:
                raise RateLimited("minute", _seconds(recent[0] + MINUTE - now))

            hits.append(now)

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


def _seconds(value: float) -> int:
    return max(1, int(value + 0.999))


limiter = SlidingWindowLimiter()
