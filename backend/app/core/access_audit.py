"""Audit of denied access (403): who tried what, when and from where.

A denial ends the request with an error, so the request's own transaction is rolled back; the
row is therefore written in a short transaction of its own. It is best effort: recording must
never turn a 403 into a 500, so failures are only logged.
"""

import logging
from typing import Any

from fastapi import Request

from app.core.config import get_settings

logger = logging.getLogger("mantix.access")

ACTION = "access.denied"


def denial_values(request: Request, detail: str) -> dict[str, Any]:
    """What is stored: the endpoint, the permission it needed (if known) and the message."""
    return {
        "method": request.method,
        "path": request.url.path,
        "permission": getattr(request.state, "denied_permission", None),
        "detail": detail,
    }


async def record_denial(request: Request, detail: str) -> None:
    """Write one `access.denied` audit row for the signed-in person, if there is one."""
    user_id = getattr(request.state, "auth_user_id", None)
    if user_id is None or not get_settings().audit_denials:
        return
    try:
        from app.db import session as db
        from app.repositories.audit import AuditRepository

        if db.AsyncSessionLocal is None:
            return
        async with db.AsyncSessionLocal() as session:
            AuditRepository(session).record(
                user_id=user_id,
                action=ACTION,
                entity_type="endpoint",
                entity_id=None,
                new_values=denial_values(request, detail),
            )
            await session.commit()
    except Exception:
        logger.warning("could not record access.denied", exc_info=True)
