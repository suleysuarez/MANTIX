from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.auth import User
from app.models.technician import Technician
from app.schemas.technician import TechnicianCreate, TechnicianUpdate


class TechnicianRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

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
        technician = Technician(**payload.model_dump())
        self.session.add(technician)
        await self.session.flush()
        return technician

    async def update(
        self, technician: Technician, payload: TechnicianUpdate
    ) -> Technician:
        for field, value in payload.model_dump(exclude_unset=True).items():
            setattr(technician, field, value)
        await self.session.flush()
        return technician

    async def commit(self) -> None:
        await self.session.commit()

    async def rollback(self) -> None:
        await self.session.rollback()
