from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from app.models.auth import Permission, Role, User, UserRole
from app.repositories.base import BaseRepository


class AdminRepository(BaseRepository[User]):
    model = User

    async def list_pending_users(self) -> list[User]:
        result = await self.session.execute(
            select(User)
            .where(User.is_active.is_(True))
            .where(~User.user_roles.any())
            .order_by(User.created_at, User.id)
        )
        return list(result.scalars().all())

    async def list_active_roles(self) -> list[Role]:
        result = await self.session.execute(
            select(Role).where(Role.is_active.is_(True)).order_by(Role.code)
        )
        return list(result.scalars().all())

    async def get_active_user(self, user_id: int) -> User | None:
        result = await self.session.execute(
            select(User)
            .options(selectinload(User.user_roles))
            .where(User.id == user_id, User.is_active.is_(True))
        )
        return result.scalar_one_or_none()

    async def get_active_roles_by_ids(self, role_ids: list[int]) -> list[Role]:
        result = await self.session.execute(
            select(Role)
            .where(Role.id.in_(role_ids), Role.is_active.is_(True))
            .order_by(Role.id)
        )
        return list(result.scalars().all())

    async def add_missing_roles(
        self, user: User, roles: list[Role], assigned_by_user_id: int
    ) -> None:
        existing_role_ids = {user_role.role_id for user_role in user.user_roles}
        for role in roles:
            if role.id not in existing_role_ids:
                self.session.add(
                    UserRole(
                        user_id=user.id,
                        role_id=role.id,
                        assigned_by_user_id=assigned_by_user_id,
                    )
                )

    async def reload_user(self, user_id: int) -> User | None:
        return await self.get_active_user(user_id)

    async def list_roles_with_permissions(self) -> list[Role]:
        result = await self.session.execute(
            select(Role)
            .options(selectinload(Role.permissions))
            .where(Role.is_active.is_(True))
            .order_by(Role.code)
        )
        return list(result.scalars().all())

    async def list_active_permissions(self) -> list[Permission]:
        result = await self.session.execute(
            select(Permission)
            .where(Permission.is_active.is_(True))
            .order_by(Permission.module, Permission.code)
        )
        return list(result.scalars().all())

    async def get_user_role(self, user_id: int, role_id: int) -> UserRole | None:
        result = await self.session.execute(
            select(UserRole)
            .options(selectinload(UserRole.role))
            .where(UserRole.user_id == user_id, UserRole.role_id == role_id)
        )
        return result.scalar_one_or_none()

    async def count_active_users_with_role(self, role_code: str) -> int:
        result = await self.session.execute(
            select(func.count(func.distinct(User.id)))
            .join(UserRole, UserRole.user_id == User.id)
            .join(Role, Role.id == UserRole.role_id)
            .where(Role.code == role_code, User.is_active.is_(True))
        )
        return int(result.scalar_one())

    async def remove_user_role(self, user_role: UserRole) -> None:
        await self.session.delete(user_role)
        await self.session.flush()
