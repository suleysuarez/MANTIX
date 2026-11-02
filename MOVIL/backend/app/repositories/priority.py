from sqlalchemy import select

from app.models.priority import Priority
from app.repositories.base import BaseRepository


class PriorityRepository(BaseRepository[Priority]):
    model = Priority

    async def list(self, *, include_inactive: bool = False) -> list[Priority]:
        query = select(Priority)
        if not include_inactive:
            query = query.where(Priority.is_active.is_(True))
        result = await self.session.execute(query.order_by(Priority.level.desc()))
        return list(result.scalars().all())

    async def get_by_code(self, code: str) -> Priority | None:
        result = await self.session.execute(
            select(Priority).where(Priority.code == code)
        )
        return result.scalar_one_or_none()
