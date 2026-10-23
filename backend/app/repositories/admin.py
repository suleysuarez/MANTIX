from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from app.models.auth import Permission, Role, RolePermission, User, UserRole
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

    # -- roles administration ------------------------------------------------------------

    async def list_all_roles(self) -> list[Role]:
        """Every role, active or not, with fresh permissions (the matrix must not be stale)."""
        result = await self.session.execute(
            select(Role)
            .options(selectinload(Role.permissions))
            .order_by(Role.id)
            .execution_options(populate_existing=True)
        )
        return list(result.scalars().all())

    async def user_counts(self) -> dict[int, int]:
        result = await self.session.execute(
            select(UserRole.role_id, func.count(func.distinct(UserRole.user_id)))
            .join(User, User.id == UserRole.user_id)
            .where(User.is_active.is_(True))
            .group_by(UserRole.role_id)
        )
        return {role_id: int(total) for role_id, total in result.all()}

    async def role_has_users(self, role_id: int) -> bool:
        result = await self.session.execute(
            select(func.count())
            .select_from(UserRole)
            .where(UserRole.role_id == role_id)
        )
        return int(result.scalar_one()) > 0

    async def get_role(self, role_id: int) -> Role | None:
        result = await self.session.execute(
            select(Role)
            .options(selectinload(Role.permissions))
            .where(Role.id == role_id)
            .execution_options(populate_existing=True)
        )
        return result.scalar_one_or_none()

    async def role_name_taken(
        self, name: str, *, exclude_id: int | None = None
    ) -> bool:
        query = (
            select(func.count())
            .select_from(Role)
            .where(func.lower(Role.name) == name.lower())
        )
        if exclude_id is not None:
            query = query.where(Role.id != exclude_id)
        return int((await self.session.execute(query)).scalar_one()) > 0

    async def role_code_taken(self, code: str) -> bool:
        result = await self.session.execute(
            select(func.count()).select_from(Role).where(Role.code == code)
        )
        return int(result.scalar_one()) > 0

    async def catalogue_permissions(self, codes: list[str]) -> list[Permission]:
        """Active `recurso:accion` permissions among `codes` (legacy dotted ones excluded)."""
        result = await self.session.execute(
            select(Permission).where(
                Permission.code.in_(codes),
                Permission.is_active.is_(True),
                Permission.action.is_not(None),
            )
        )
        return list(result.scalars().all())

    async def add_role(self, role: Role) -> Role:
        self.session.add(role)
        await self.session.flush()
        return role

    async def set_catalogue_permissions(
        self, role: Role, permissions: list[Permission]
    ) -> None:
        """Make the role's `recurso:accion` grants exactly `permissions`, leaving legacy ones."""
        rows = await self.session.execute(
            select(RolePermission, Permission.id)
            .join(Permission, Permission.id == RolePermission.permission_id)
            .where(RolePermission.role_id == role.id, Permission.action.is_not(None))
        )
        wanted = {permission.id for permission in permissions}
        present: set[int] = set()
        for row, permission_id in rows.all():
            if permission_id in wanted:
                present.add(permission_id)
            else:
                await self.session.delete(row)
        for permission_id in wanted - present:
            self.session.add(
                RolePermission(role_id=role.id, permission_id=permission_id)
            )
        await self.session.flush()

    async def delete_role(self, role: Role) -> None:
        await self.session.delete(role)
        await self.session.flush()
