from typing import Any

from app.repositories.audit import AuditRepository


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
