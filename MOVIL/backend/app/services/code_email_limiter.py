"""One limiter for the emails that carry verification and recovery codes.

Three rules, checked together and recorded only when all pass:
  * at least `min_interval` seconds between two emails to the same account,
  * at most `per_account_per_hour` emails per account per hour,
  * at most `global_per_hour` emails per hour for the whole system.

Counters live in this process's memory: they reset on restart and are not shared
between workers or replicas. That is acceptable for a demo with personal SMTP;
production would need a shared store.
"""

import time
from collections import defaultdict, deque

HOUR_SECONDS = 3600.0


class CodeEmailLimiter:
    def __init__(
        self,
        *,
        per_account_per_hour: int = 5,
        min_interval_seconds: float = 60.0,
        global_per_hour: int = 60,
    ):
        self.per_account_per_hour = per_account_per_hour
        self.min_interval = min_interval_seconds
        self.global_per_hour = global_per_hour
        self._accounts: dict[str, deque[float]] = defaultdict(deque)
        self._all: deque[float] = deque()

    @staticmethod
    def _prune(hits: deque[float], now: float) -> None:
        while hits and now - hits[0] >= HOUR_SECONDS:
            hits.popleft()

    def allow(self, account: str, *, now: float | None = None) -> bool:
        """Return True and record the send, or False when any rule blocks it."""
        now = time.monotonic() if now is None else now
        key = account.strip().lower()
        self._prune(self._all, now)
        hits = self._accounts[key]
        self._prune(hits, now)
        if not hits:
            self._accounts.pop(key, None)
            hits = self._accounts[key]
        if len(self._all) >= self.global_per_hour:
            return False
        if len(hits) >= self.per_account_per_hour:
            return False
        if hits and now - hits[-1] < self.min_interval:
            return False
        hits.append(now)
        self._all.append(now)
        return True


# Shared by every request in this process.
code_email_limiter = CodeEmailLimiter()
