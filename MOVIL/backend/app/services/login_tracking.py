"""Last-access tracking for the native mobile sign-in.

`users.last_login_at` is what the admin screens show as "last access" (and what turns an account
from "pending first sign-in" into "active"). It is stamped here, when the mobile app signs someone
in, and not by anything that reads Clerk.
"""

from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from typing import Protocol

from app.models.auth import User

#: A new session is recorded when the previous one started longer ago than this.
SESSION_GAP = timedelta(minutes=30)


class AuditRecorder(Protocol):
    def record(
        self,
        *,
        user_id: int | None,
        action: str,
        entity_type: str,
        entity_id: int | None,
    ) -> None: ...


async def record_login(
    user: User,
    *,
    commit: Callable[[], Awaitable[None]],
    audit: AuditRecorder | None = None,
    now: datetime | None = None,
) -> bool:
    """Note the start of a session, at most once per `SESSION_GAP`.

    Stamps `last_login_at`, stages an `auth.login` audit entry (when `audit` is given) and calls
    `commit`, so both are saved together. Returns whether a new session was recorded.
    """
    now = now or datetime.now(UTC)
    if user.last_login_at is not None and now - user.last_login_at < SESSION_GAP:
        return False
    user.last_login_at = now
    if audit is not None:
        audit.record(
            user_id=user.id,
            action="auth.login",
            entity_type="user",
            entity_id=user.id,
        )
    await commit()
    return True
