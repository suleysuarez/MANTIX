from collections.abc import Callable

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.clerk import verify_clerk_request
from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.models.auth import User
from app.services.auth import ClerkAuthService


async def get_authenticated_user(
    request: Request,
    session: AsyncSession = Depends(get_db),  # noqa: B008
    settings: Settings = Depends(get_settings),  # noqa: B008
) -> User:
    identity = verify_clerk_request(request, settings)
    return await ClerkAuthService(session, settings).resolve_local_user(identity)


def require_permission(permission_code: str) -> Callable:
    async def dependency(
        user: User = Depends(get_authenticated_user),  # noqa: B008
    ) -> User:
        if not any(
            role.is_active
            and any(
                permission.is_active and permission.code == permission_code
                for permission in role.permissions
            )
            for role in user.roles
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="insufficient permissions",
            )
        return user

    return dependency
