from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.auth import (
    PasswordResetToken,
    RefreshToken,
    Role,
    User,
)


class AuthRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def get_user_by_email(self, email: str) -> User | None:
        result = await self.session.execute(
            select(User)
            .where(User.email == email.lower())
            .options(
                selectinload(User.credentials),
                selectinload(User.roles).selectinload(Role.permissions),
            )
        )
        return result.scalar_one_or_none()

    async def get_user_by_id(self, user_id: int) -> User | None:
        result = await self.session.execute(
            select(User)
            .where(User.id == user_id)
            .options(
                selectinload(User.credentials),
                selectinload(User.roles).selectinload(Role.permissions),
            )
        )
        return result.scalar_one_or_none()

    async def get_refresh_token(self, token_hash: str) -> RefreshToken | None:
        result = await self.session.execute(
            select(RefreshToken)
            .where(RefreshToken.token_hash == token_hash)
            .options(
                selectinload(RefreshToken.user)
                .selectinload(User.roles)
                .selectinload(Role.permissions)
            )
        )
        return result.scalar_one_or_none()

    async def add_refresh_token(
        self, user_id: int, token_hash: str, expires_at: datetime
    ) -> RefreshToken:
        token = RefreshToken(
            user_id=user_id,
            token_hash=token_hash,
            expires_at=expires_at,
        )
        self.session.add(token)
        return token

    async def get_password_reset_token(
        self, token_hash: str
    ) -> PasswordResetToken | None:
        result = await self.session.execute(
            select(PasswordResetToken)
            .where(PasswordResetToken.token_hash == token_hash)
            .options(
                selectinload(PasswordResetToken.user).selectinload(User.credentials)
            )
        )
        return result.scalar_one_or_none()

    async def add_password_reset_token(
        self, user_id: int, token_hash: str, expires_at: datetime
    ) -> PasswordResetToken:
        token = PasswordResetToken(
            user_id=user_id,
            token_hash=token_hash,
            expires_at=expires_at,
        )
        self.session.add(token)
        return token

    async def revoke_refresh_token(self, token: RefreshToken, now: datetime) -> None:
        token.revoked_at = now

    async def commit(self) -> None:
        await self.session.commit()

    async def rollback(self) -> None:
        await self.session.rollback()
