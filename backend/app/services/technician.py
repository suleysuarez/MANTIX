from decimal import Decimal
from typing import Any

from sqlalchemy.exc import IntegrityError

from app.core.authz import AuthContext
from app.core.exceptions import ConflictError, NotFoundError
from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.technician import Technician
from app.repositories.base import Page
from app.repositories.technician import TechnicianRepository
from app.schemas.technician import (
    TechnicianCreate,
    TechnicianResponse,
    TechnicianUpdate,
)
from app.services.audit import AuditService


def _jsonable(values: dict[str, Any]) -> dict[str, Any]:
    """Audit values are stored as JSON: render Decimals as strings."""
    return {
        key: str(value) if isinstance(value, Decimal) else value
        for key, value in values.items()
    }


class TechnicianService:
    def __init__(self, repository: TechnicianRepository, audit: AuditService):
        self.repository = repository
        self.audit = audit

    async def list(
        self,
        *,
        is_available: bool | None = None,
        search: str | None = None,
        params: PageParams = DEFAULT_PAGE,
    ) -> Page[TechnicianResponse]:
        page = await self.repository.list(
            is_available=is_available, search=search, params=params
        )
        return page.map(TechnicianResponse.model_validate)

    async def create(
        self, payload: TechnicianCreate, actor: AuthContext
    ) -> TechnicianResponse:
        if await self.repository.get_active_user(payload.user_id) is None:
            raise NotFoundError("active user not found")
        if await self.repository.get_by_user_id(payload.user_id) is not None:
            raise ConflictError("this user already has a technician profile")
        try:
            technician = await self.repository.create(payload)
            self.audit.record(
                user_id=actor.id,
                action="technician.created",
                entity_type="technician",
                entity_id=technician.id,
                new_values={"user_id": payload.user_id},
            )
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.rollback()
            raise ConflictError("this user already has a technician profile") from exc
        return self._response(technician)

    async def update(
        self, technician_id: int, payload: TechnicianUpdate, actor: AuthContext
    ) -> TechnicianResponse:
        technician = await self.repository.get(technician_id)
        if technician is None:
            raise NotFoundError("technician not found")
        changes = payload.model_dump(exclude_unset=True)
        old_values = {field: getattr(technician, field) for field in changes}
        await self.repository.update(technician, payload)
        self.audit.record(
            user_id=actor.id,
            action="technician.updated",
            entity_type="technician",
            entity_id=technician.id,
            old_values=_jsonable(old_values),
            new_values=_jsonable(changes),
        )
        await self.repository.commit()
        return self._response(technician)

    @staticmethod
    def _response(technician: Technician | None) -> TechnicianResponse:
        if technician is None:
            raise NotFoundError("technician not found")
        return TechnicianResponse.model_validate(technician)
