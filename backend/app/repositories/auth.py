from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.clerk import ClerkProfile
from app.models.auth import Role, User, UserRole


class AuthRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    @staticmethod
    def _user_query():
        return select(User).options(
            selectinload(User.roles).selectinload(Role.permissions)
        )

    async def get_user_by_clerk_id(self, clerk_user_id: str) -> User | None:
        result = await self.session.execute(
            self._user_query().where(User.clerk_user_id == clerk_user_id)
        )
        return result.scalar_one_or_none()

    async def get_user_by_email(self, email: str) -> User | None:
        result = await self.session.execute(
            self._user_query().where(User.email == email)
        )
        return result.scalar_one_or_none()

    async def get_employee_role(self) -> Role | None:
        result = await self.session.execute(
            select(Role).where(Role.code == "EMPLOYEE", Role.is_active.is_(True))
        )
        return result.scalar_one_or_none()

    async def create_user(self, profile: ClerkProfile) -> User:
        user = User(
            clerk_user_id=profile.clerk_user_id,
            email=profile.email,
            full_name=profile.full_name,
            is_active=True,
        )
        self.session.add(user)
        await self.session.flush()
        return user

    async def assign_role(self, user: User, role: Role) -> None:
        self.session.add(UserRole(user_id=user.id, role_id=role.id))

    async def commit(self) -> None:
        await self.session.commit()

    async def rollback(self) -> None:
        await self.session.rollback()
