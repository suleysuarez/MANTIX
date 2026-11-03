"""Users as the Users screen sees them: every account (active or not), with filters, server-side
sorting and pagination, and the counts behind its indicators."""

from datetime import datetime
from typing import Any

from sqlalchemy import Select, func, select
from sqlalchemy.orm import selectinload

from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.auth import Role, User, UserRole
from app.repositories.base import BaseRepository, Page

SORTABLE = {
    "name": func.lower(User.full_name),
    "email": User.email,
    "created_at": User.created_at,
    "last_login_at": User.last_login_at,
    "is_active": User.is_active,
    "id": User.id,
}


class UserManagementRepository(BaseRepository[User]):
    model = User

    # -- reads -------------------------------------------------------------------------

    async def get(self, user_id: int) -> User | None:
        result = await self.session.execute(
            select(User)
            .options(selectinload(User.user_roles).selectinload(UserRole.role))
            .where(User.id == user_id)
            .execution_options(populate_existing=True)
        )
        user: User | None = result.scalar_one_or_none()
        return user

    async def search(
        self,
        *,
        search: str | None = None,
        role_code: str | None = None,
        is_active: bool | None = None,
        created_from: datetime | None = None,
        created_to: datetime | None = None,
        params: PageParams = DEFAULT_PAGE,
    ) -> Page[User]:
        query: Select[Any] = select(User).options(
            selectinload(User.user_roles).selectinload(UserRole.role)
        )
        if role_code:
            query = query.where(
                User.user_roles.any(UserRole.role.has(Role.code == role_code))
            )
        if is_active is not None:
            query = query.where(User.is_active.is_(is_active))
        if created_from is not None:
            query = query.where(User.created_at >= created_from)
        if created_to is not None:
            query = query.where(User.created_at <= created_to)
        query = self.apply_search(
            query, search, [User.full_name, User.email, User.employee_code]
        )
        query = self.apply_ordering(
            query,
            params.sort,
            SORTABLE,
            default=(User.created_at.desc(), User.id.desc()),
        )
        return await self.paginate(
            query, page=params.page, size=params.size, offset=params.offset
        )

    async def email_taken(self, email: str, *, excluding: int | None = None) -> bool:
        query = select(User.id).where(func.lower(User.email) == email.lower())
        if excluding is not None:
            query = query.where(User.id != excluding)
        return (await self.session.execute(query.limit(1))).first() is not None

    async def code_taken(self, code: str, *, excluding: int | None = None) -> bool:
        query = select(User.id).where(func.upper(User.employee_code) == code.upper())
        if excluding is not None:
            query = query.where(User.id != excluding)
        return (await self.session.execute(query.limit(1))).first() is not None

    async def roles_by_ids(self, role_ids: list[int]) -> list[Role]:
        result = await self.session.execute(
            select(Role).where(Role.id.in_(role_ids), Role.is_active.is_(True))
        )
        return list(result.scalars().all())

    async def count_active_admins(self) -> int:
        result = await self.session.execute(
            select(func.count(func.distinct(User.id)))
            .join(UserRole, UserRole.user_id == User.id)
            .join(Role, Role.id == UserRole.role_id)
            .where(Role.code == "ADMIN", User.is_active.is_(True))
        )
        return int(result.scalar_one())

    # -- writes ------------------------------------------------------------------------

    async def create(
        self,
        *,
        email: str,
        full_name: str,
        phone: str | None,
        employee_code: str | None,
        roles: list[Role],
        assigned_by: int,
    ) -> User:
        user = User(
            email=email,
            full_name=full_name,
            phone=phone,
            employee_code=employee_code,
            is_active=True,
        )
        self.session.add(user)
        await self.session.flush()
        for role in roles:
            self.session.add(
                UserRole(
                    user_id=user.id, role_id=role.id, assigned_by_user_id=assigned_by
                )
            )
        await self.session.flush()
        return user

    async def replace_roles(
        self, user: User, roles: list[Role], assigned_by: int
    ) -> None:
        wanted = {role.id for role in roles}
        for link in list(user.user_roles):
            if link.role_id not in wanted:
                await self.session.delete(link)
        have = {link.role_id for link in user.user_roles}
        for role in roles:
            if role.id not in have:
                self.session.add(
                    UserRole(
                        user_id=user.id,
                        role_id=role.id,
                        assigned_by_user_id=assigned_by,
                    )
                )
        await self.session.flush()

    # -- indicators --------------------------------------------------------------------

    async def totals(self) -> tuple[int, int, int, int]:
        """`(total, active, never signed in, active without role)`."""
        row = (
            await self.session.execute(
                select(
                    func.count(User.id),
                    func.count(User.id).filter(User.is_active.is_(True)),
                    func.count(User.id).filter(User.last_login_at.is_(None)),
                    func.count(User.id).filter(
                        User.is_active.is_(True), ~User.user_roles.any()
                    ),
                )
            )
        ).one()
        return int(row[0]), int(row[1]), int(row[2]), int(row[3])

    async def count_by_role(self) -> list[tuple[str, str, int]]:
        result = await self.session.execute(
            select(Role.code, Role.name, func.count(func.distinct(User.id)))
            .select_from(Role)
            .outerjoin(UserRole, UserRole.role_id == Role.id)
            .outerjoin(User, (User.id == UserRole.user_id) & (User.is_active.is_(True)))
            .where(Role.is_active.is_(True))
            .group_by(Role.code, Role.name)
            .order_by(Role.code)
        )
        return [(row[0], row[1], int(row[2])) for row in result.all()]

    async def recent_access(self, limit: int = 5) -> list[User]:
        result = await self.session.execute(
            select(User)
            .where(User.last_login_at.is_not(None))
            .order_by(User.last_login_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())
