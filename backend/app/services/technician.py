from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ConflictError, NotFoundError
from app.models.technician import Technician
from app.repositories.technician import TechnicianRepository
from app.schemas.technician import (
    TechnicianCreate,
    TechnicianResponse,
    TechnicianUpdate,
)


class TechnicianService:
    def __init__(self, session: AsyncSession):
        self.repository = TechnicianRepository(session)

    async def list(
        self, *, is_available: bool | None = None
    ) -> list[TechnicianResponse]:
        return [
            TechnicianResponse.model_validate(item)
            for item in await self.repository.list(is_available=is_available)
        ]

    async def create(self, payload: TechnicianCreate) -> TechnicianResponse:
        if await self.repository.get_active_user(payload.user_id) is None:
            raise NotFoundError("active user not found")
        if await self.repository.get_by_user_id(payload.user_id) is not None:
            raise ConflictError("this user already has a technician profile")
        try:
            technician = await self.repository.create(payload)
            await self.repository.commit()
        except IntegrityError as exc:
            await self.repository.rollback()
            raise ConflictError("this user already has a technician profile") from exc
        return self._response(technician)

    async def update(
        self, technician_id: int, payload: TechnicianUpdate
    ) -> TechnicianResponse:
        technician = await self.repository.get(technician_id)
        if technician is None:
            raise NotFoundError("technician not found")
        await self.repository.update(technician, payload)
        await self.repository.commit()
        return self._response(technician)

    @staticmethod
    def _response(technician: Technician | None) -> TechnicianResponse:
        if technician is None:
            raise NotFoundError("technician not found")
        return TechnicianResponse.model_validate(technician)
