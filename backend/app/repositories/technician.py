from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.auth import User
from app.models.technician import Technician
from app.repositories.base import BaseRepository, Page
from app.schemas.technician import TechnicianCreate, TechnicianUpdate


class TechnicianRepository(BaseRepository[Technician]):
    model = Technician

    async def list(
        self,
        *,
        is_available: bool | None = None,
        search: str | None = None,
        params: PageParams = DEFAULT_PAGE,
    ) -> Page[Technician]:
        query = (
            select(Technician)
            .join(User, User.id == Technician.user_id)
            .options(selectinload(Technician.user))
        )
        if is_available is not None:
            query = query.where(Technician.is_available.is_(is_available))
        query = self.apply_search(
            query, search, [User.full_name, User.email, Technician.specialization]
        )
        query = self.apply_ordering(
            query,
            params.sort,
            {
                "name": User.full_name,
                "specialization": Technician.specialization,
                "hourly_rate": Technician.hourly_rate,
                "id": Technician.id,
            },
            default=(Technician.id,),
        )
        return await self.paginate(
            query, page=params.page, size=params.size, offset=params.offset
        )

    async def get(self, entity_id: int) -> Technician | None:
        result = await self.session.execute(
            select(Technician)
            .options(selectinload(Technician.user))
            .where(Technician.id == entity_id)
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
        technician = await self.add_and_flush(Technician(**payload.model_dump()))
        # `created_at` is a server default and the response shows the user's
        # identity: load both now, since async sessions cannot lazy-load later.
        await self.session.refresh(technician, ["created_at", "user"])
        return technician

    async def update(
        self, technician: Technician, payload: TechnicianUpdate
    ) -> Technician:
        return await self.update_fields(
            technician, payload.model_dump(exclude_unset=True)
        )
