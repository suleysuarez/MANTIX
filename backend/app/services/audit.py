from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import AuditLog


class AuditService:
    """Records audit trail entries as part of the caller's transaction.

    Deliberately has no `commit()`/`rollback()` of its own: it only calls
    `session.add()`, so the audit row is flushed and committed together with
    whatever business operation it describes, in the same transaction.
    """

    def __init__(self, session: AsyncSession):
        self.session = session

    def record(
        self,
        *,
        user_id: int | None,
        action: str,
        entity_type: str,
        entity_id: int | None,
        old_values: dict[str, Any] | None = None,
        new_values: dict[str, Any] | None = None,
    ) -> None:
        self.session.add(
            AuditLog(
                user_id=user_id,
                action=action,
                entity_type=entity_type,
                entity_id=entity_id,
                old_values=old_values,
                new_values=new_values,
            )
        )
