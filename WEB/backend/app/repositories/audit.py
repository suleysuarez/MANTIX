from datetime import datetime
from typing import Any

from fastapi.encoders import jsonable_encoder
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.pagination import DEFAULT_PAGE, PageParams
from app.core.request_context import get_request_info
from app.models.audit import AuditLog
from app.repositories.base import BaseRepository, Page

SORTABLE = {
    "created_at": AuditLog.created_at,
    "action": AuditLog.action,
    "entity_type": AuditLog.entity_type,
    "id": AuditLog.id,
}


def _as_json(values: dict[str, Any] | None) -> dict[str, Any] | None:
    """Audit columns are JSONB: money (`Decimal`), dates and enums must become plain JSON.

    Every service passes whatever `model_dump()` gave it, so the conversion lives here once
    instead of in each caller (an edit with a cost or a date used to fail with a 500).
    """
    return None if values is None else jsonable_encoder(values)


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
        info = get_request_info()
        self.add(
            AuditLog(
                user_id=user_id,
                action=action,
                entity_type=entity_type,
                entity_id=entity_id,
                old_values=_as_json(old_values),
                new_values=_as_json(new_values),
                ip_address=info.ip_address[:45] if info and info.ip_address else None,
                user_agent=info.user_agent[:500] if info and info.user_agent else None,
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
        params: PageParams = DEFAULT_PAGE,
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
            params.sort,
            SORTABLE,
            default=(AuditLog.created_at.desc(), AuditLog.id.desc()),
        )
        return await self.paginate(
            query, page=params.page, size=params.size, offset=params.offset
        )
