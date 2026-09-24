from collections.abc import Callable

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.models.auth import User
from app.services.auth import get_current_user as resolve_current_user
from app.services.auth import has_permission

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


async def get_authenticated_user(
    token: str = Depends(oauth2_scheme),
    session: AsyncSession = Depends(get_db),  # noqa: B008
    settings: Settings = Depends(get_settings),  # noqa: B008
) -> User:
    return await resolve_current_user(session, token, settings)


def require_permission(permission_code: str) -> Callable:
    async def dependency(user: User = Depends(get_authenticated_user)) -> User:  # noqa: B008
        if not has_permission(user, permission_code):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="insufficient permissions",
            )
        return user

    return dependency
