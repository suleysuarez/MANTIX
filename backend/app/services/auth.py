from datetime import timedelta

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.security import (
    create_access_token,
    decode_access_token,
    generate_opaque_token,
    hash_password,
    hash_token,
    utcnow,
    verify_password,
)
from app.models.auth import User
from app.repositories.auth import AuthRepository
from app.schemas.auth import (
    LoginRequest,
    MessageResponse,
    PasswordResetConfirm,
    PasswordResetRequest,
    RefreshRequest,
    TokenResponse,
    UserResponse,
)

INVALID_CREDENTIALS = "invalid email or password"
RESET_MESSAGE = "if the account exists, password reset instructions have been created"


def user_response(user: User) -> UserResponse:
    roles = [
        {"code": role.code, "name": role.name}
        for role in sorted(user.roles, key=lambda item: item.code)
        if role.is_active
    ]
    permissions = {
        permission.code: {"code": permission.code, "name": permission.name}
        for role in user.roles
        if role.is_active
        for permission in role.permissions
    }
    return UserResponse(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        employee_code=user.employee_code,
        is_active=user.is_active,
        roles=roles,
        permissions=sorted(permissions.values(), key=lambda item: item["code"]),
    )


class AuthService:
    def __init__(self, session: AsyncSession, settings: Settings):
        self.repository = AuthRepository(session)
        self.settings = settings

    async def login(self, data: LoginRequest) -> TokenResponse:
        user = await self.repository.get_user_by_email(str(data.email).lower())
        if (
            user is None
            or not user.is_active
            or user.credentials is None
            or not verify_password(data.password, user.credentials.password_hash)
        ):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail=INVALID_CREDENTIALS
            )
        return await self._issue_tokens(user)

    async def refresh(self, data: RefreshRequest) -> TokenResponse:
        now = utcnow()
        token = await self.repository.get_refresh_token(hash_token(data.refresh_token))
        if (
            token is None
            or token.revoked_at is not None
            or token.expires_at <= now
            or token.user is None
            or not token.user.is_active
        ):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="invalid or expired refresh token",
            )
        await self.repository.revoke_refresh_token(token, now)
        return await self._issue_tokens(token.user)

    async def logout(self, data: RefreshRequest) -> MessageResponse:
        token = await self.repository.get_refresh_token(hash_token(data.refresh_token))
        if token is not None and token.revoked_at is None:
            await self.repository.revoke_refresh_token(token, utcnow())
            await self.repository.commit()
        return MessageResponse(message="logged out")

    async def request_password_reset(
        self, data: PasswordResetRequest
    ) -> MessageResponse:
        user = await self.repository.get_user_by_email(str(data.email).lower())
        if user is not None and user.is_active:
            token = generate_opaque_token()
            await self.repository.add_password_reset_token(
                user.id,
                hash_token(token),
                utcnow()
                + timedelta(minutes=self.settings.password_reset_expire_minutes),
            )
            await self.repository.commit()
        return MessageResponse(message=RESET_MESSAGE)

    async def confirm_password_reset(
        self, data: PasswordResetConfirm
    ) -> MessageResponse:
        token = await self.repository.get_password_reset_token(hash_token(data.token))
        now = utcnow()
        if (
            token is None
            or token.used_at is not None
            or token.expires_at <= now
            or token.user is None
            or not token.user.is_active
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="invalid or expired password reset token",
            )
        token.user.credentials.password_hash = hash_password(data.new_password)
        token.used_at = now
        await self.repository.commit()
        return MessageResponse(message="password reset successfully")

    async def _issue_tokens(self, user: User) -> TokenResponse:
        refresh_token = generate_opaque_token()
        await self.repository.add_refresh_token(
            user.id,
            hash_token(refresh_token),
            utcnow() + timedelta(days=self.settings.refresh_token_expire_days),
        )
        await self.repository.commit()
        return TokenResponse(
            access_token=create_access_token(str(user.id), self.settings),
            refresh_token=refresh_token,
            expires_in=self.settings.access_token_expire_minutes * 60,
            user=user_response(user),
        )


async def get_current_user(
    session: AsyncSession, token: str, settings: Settings
) -> User:
    payload = decode_access_token(token, settings)
    repository = AuthRepository(session)
    user = await repository.get_user_by_id(int(payload["sub"]))
    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="user is inactive or no longer exists",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


def has_permission(user: User, permission_code: str) -> bool:
    return any(
        role.is_active
        and any(
            permission.is_active and permission.code == permission_code
            for permission in role.permissions
        )
        for role in user.roles
    )
