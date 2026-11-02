from datetime import datetime
from typing import Any

from app.core.pagination import DEFAULT_PAGE, PageParams
from app.repositories.audit import AuditRepository
from app.repositories.base import Page
from app.schemas.audit import AuditLogResponse


class AuditService:
    """Records audit trail entries as part of the caller's transaction.

    Deliberately has no `commit()`/`rollback()` of its own: the repository only
    stages the row, so it is committed together with the business operation it
    describes, in the same transaction.
    """

    def __init__(self, repository: AuditRepository):
        self.repository = repository

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
        self.repository.record(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            old_values=old_values,
            new_values=new_values,
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
    ) -> Page[AuditLogResponse]:
        page = await self.repository.search(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            date_from=date_from,
            date_to=date_to,
            params=params,
        )
        return page.map(AuditLogResponse.model_validate)
