from sqlalchemy.exc import IntegrityError

from app.core.authz import AuthContext
from app.core.exceptions import ConflictError, NotFoundError
from app.models.priority import Priority
from app.repositories.priority import PriorityRepository
from app.schemas.priority import PriorityCreate, PriorityResponse, PriorityUpdate
from app.services.audit import AuditService


class PriorityService:
    def __init__(self, repository: PriorityRepository, audit: AuditService):
        self.repository = repository
        self.audit = audit

    async def list(self, *, include_inactive: bool = False) -> list[PriorityResponse]:
        items = await self.repository.list(include_inactive=include_inactive)
        return [PriorityResponse.model_validate(item) for item in items]

    async def create(
        self, payload: PriorityCreate, actor: AuthContext
    ) -> PriorityResponse:
        if await self.repository.get_by_code(payload.code) is not None:
            raise ConflictError(f"priority '{payload.code}' already exists")
        try:
            priority = await self.repository.add_and_flush(
                Priority(**payload.model_dump(), is_active=True)
            )
            self.audit.record(
                user_id=actor.id,
                action="priority.created",
                entity_type="priority",
                entity_id=priority.id,
                new_values=payload.model_dump(),
            )
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.rollback()
            raise ConflictError(f"priority '{payload.code}' already exists") from exc
        return PriorityResponse.model_validate(priority)

    async def update(
        self, priority_id: int, payload: PriorityUpdate, actor: AuthContext
    ) -> PriorityResponse:
        priority = await self.repository.get(priority_id)
        if priority is None:
            raise NotFoundError("priority not found")
        changes = payload.model_dump(exclude_unset=True)
        old_values = {field: getattr(priority, field) for field in changes}
        await self.repository.update_fields(priority, changes)
        self.audit.record(
            user_id=actor.id,
            action="priority.updated",
            entity_type="priority",
            entity_id=priority.id,
            old_values=old_values,
            new_values=changes,
        )
        await self.repository.commit()
        return PriorityResponse.model_validate(priority)
