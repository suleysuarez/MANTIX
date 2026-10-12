from sqlalchemy import select

from app.models.auth import User
from app.models.technician import Technician
from app.repositories.base import BaseRepository
from app.schemas.technician import TechnicianCreate, TechnicianUpdate


class TechnicianRepository(BaseRepository[Technician]):
    model = Technician

    async def list(self, *, is_available: bool | None = None) -> list[Technician]:
        query = select(Technician)
        if is_available is not None:
            query = query.where(Technician.is_available.is_(is_available))
        result = await self.session.execute(query.order_by(Technician.id))
        return list(result.scalars().all())

    async def get(self, technician_id: int) -> Technician | None:
        result = await self.session.execute(
            select(Technician).where(Technician.id == technician_id)
        )
        return result.scalar_one_or_none()

    async def get_active_user(self, user_id: int) -> User | None:
        result = await self.session.execute(
            select(User).where(User.id == user_id, User.is_active.is_(True))
        )
        return result.scalar_one_or_none()

    async def get_by_user_id(self, user_id: int) -> Technician | None:
        result = await self.session.execute(
            select(Technician).where(Technician.user_id == user_id)
        )
        return result.scalar_one_or_none()

    async def create(self, payload: TechnicianCreate) -> Technician:
        return await self.add_and_flush(Technician(**payload.model_dump()))

    async def update(
        self, technician: Technician, payload: TechnicianUpdate
    ) -> Technician:
        return await self.update_fields(
            technician, payload.model_dump(exclude_unset=True)
        )
