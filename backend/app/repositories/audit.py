from datetime import datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.models.audit import AuditLog
from app.repositories.base import BaseRepository, Page

SORTABLE = {
    "created_at": AuditLog.created_at,
    "action": AuditLog.action,
    "entity_type": AuditLog.entity_type,
    "id": AuditLog.id,
}


class AuditRepository(BaseRepository[AuditLog]):
    model = AuditLog

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
        """Stage an audit row in the caller's transaction (no commit)."""
        self.add(
            AuditLog(
                user_id=user_id,
                action=action,
                entity_type=entity_type,
                entity_id=entity_id,
                old_values=old_values,
                new_values=new_values,
            )
        )

    async def search(
        self,
        *,
        user_id: int | None = None,
        action: str | None = None,
        entity_type: str | None = None,
        entity_id: int | None = None,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
        sort: str | None = None,
        page: int = 1,
        size: int = 20,
    ) -> Page[AuditLog]:
        query = select(AuditLog).options(selectinload(AuditLog.user))
        if user_id is not None:
            query = query.where(AuditLog.user_id == user_id)
        if action:
            query = query.where(AuditLog.action == action)
        if entity_type:
            query = query.where(AuditLog.entity_type == entity_type)
        if entity_id is not None:
            query = query.where(AuditLog.entity_id == entity_id)
        if date_from is not None:
            query = query.where(AuditLog.created_at >= date_from)
        if date_to is not None:
            query = query.where(AuditLog.created_at <= date_to)
        query = self.apply_ordering(
            query,
            sort,
            SORTABLE,
            default=(AuditLog.created_at.desc(), AuditLog.id.desc()),
        )
        return await self.paginate(query, page=page, size=size)
