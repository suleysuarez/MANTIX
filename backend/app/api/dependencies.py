from collections.abc import Callable
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status

from app.api.providers import get_auth_service
from app.core.authz import AuthContext
from app.core.clerk import verify_clerk_request
from app.core.config import Settings, get_settings
from app.models.auth import User
from app.services.auth import ClerkAuthService


async def get_authenticated_user(
    request: Request,
    service: Annotated[ClerkAuthService, Depends(get_auth_service)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> User:
    identity = verify_clerk_request(request, settings)
    return await service.resolve_local_user(identity)


async def get_auth_context(
    user: Annotated[User, Depends(get_authenticated_user)],
) -> AuthContext:
    return AuthContext.from_user(user)


def _forbidden(detail: str = "insufficient permissions") -> HTTPException:
    return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


def require_permission(permission_code: str) -> Callable[..., AuthContext]:
    """Dependency factory: the caller must hold `permission_code`."""

    async def dependency(
        context: Annotated[AuthContext, Depends(get_auth_context)],
    ) -> AuthContext:
        if not context.has_permission(permission_code):
            raise _forbidden()
        return context

    return dependency


def require_role(*role_codes: str) -> Callable[..., AuthContext]:
    """Dependency factory: the caller must hold at least one of `role_codes`."""

    async def dependency(
        context: Annotated[AuthContext, Depends(get_auth_context)],
    ) -> AuthContext:
        if not context.has_role(*role_codes):
            raise _forbidden("insufficient role")
        return context

    return dependency
