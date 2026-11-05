from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.providers import get_auth_service
from app.core.authz import AuthContext
from app.core.clerk import verify_clerk_request
from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.models.auth import User
from app.services.auth import ClerkAuthService
from app.services.mobile_auth import MobileAuthService


async def get_authenticated_user(
    request: Request,
    service: Annotated[ClerkAuthService, Depends(get_auth_service)],
    settings: Annotated[Settings, Depends(get_settings)],
    session: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    authorization = request.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() == "bearer" and token.startswith("mjwt."):
        user = await MobileAuthService(session, settings).user_from_token(token)
    else:
        identity = verify_clerk_request(request, settings)
        user = await service.resolve_local_user(identity)
    request.state.auth_user_id = user.id
    return user


async def get_auth_context(
    user: Annotated[User, Depends(get_authenticated_user)],
) -> AuthContext:
    return AuthContext.from_user(user)


def _forbidden(detail: str = "No tienes permiso para realizar esta acción.") -> HTTPException:
    return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


class RequirePermission:
    def __init__(self, code: str):
        self.code = code

    async def __call__(
        self, request: Request,
        context: Annotated[AuthContext, Depends(get_auth_context)],
    ) -> AuthContext:
        if not context.has_permission(self.code):
            request.state.denied_permission = self.code
            raise _forbidden()
        return context


class AuthenticatedOnly:
    """Marker for routes requiring any authenticated user."""


class RequireSession(AuthenticatedOnly):
    async def __call__(self, user: Annotated[User, Depends(get_authenticated_user)]) -> User:
        return user


class RequireAuthenticated(AuthenticatedOnly):
    async def __call__(self, context: Annotated[AuthContext, Depends(get_auth_context)]) -> AuthContext:
        return context


def require_permission(permission_code: str) -> RequirePermission:
    return RequirePermission(permission_code)


def require_session() -> RequireSession:
    return RequireSession()


def require_authenticated() -> RequireAuthenticated:
    return RequireAuthenticated()
