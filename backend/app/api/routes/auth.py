from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_authenticated_user
from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.models.auth import User
from app.schemas.auth import (
    LoginRequest,
    MessageResponse,
    PasswordResetConfirm,
    PasswordResetRequest,
    RefreshRequest,
    TokenResponse,
    UserResponse,
)
from app.services.auth import AuthService, user_response

router = APIRouter(prefix="/auth", tags=["authentication"])


async def service(
    session: AsyncSession = Depends(get_db),  # noqa: B008
    settings: Settings = Depends(get_settings),  # noqa: B008
) -> AuthService:
    return AuthService(session, settings)


@router.post("/login", response_model=TokenResponse)
async def login(
    data: LoginRequest,
    auth: AuthService = Depends(service),  # noqa: B008
) -> TokenResponse:
    return await auth.login(data)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(
    data: RefreshRequest,
    auth: AuthService = Depends(service),  # noqa: B008
) -> TokenResponse:
    return await auth.refresh(data)


@router.post("/logout", response_model=MessageResponse)
async def logout(
    data: RefreshRequest,
    auth: AuthService = Depends(service),  # noqa: B008
) -> MessageResponse:
    return await auth.logout(data)


@router.get("/me", response_model=UserResponse)
async def me(user: User = Depends(get_authenticated_user)) -> UserResponse:  # noqa: B008
    return user_response(user)


@router.post("/password-reset/request", response_model=MessageResponse)
async def request_password_reset(
    data: PasswordResetRequest,
    auth: AuthService = Depends(service),  # noqa: B008
) -> MessageResponse:
    return await auth.request_password_reset(data)


@router.post("/password-reset/confirm", response_model=MessageResponse)
async def confirm_password_reset(
    data: PasswordResetConfirm,
    auth: AuthService = Depends(service),  # noqa: B008
) -> MessageResponse:
    return await auth.confirm_password_reset(data)
