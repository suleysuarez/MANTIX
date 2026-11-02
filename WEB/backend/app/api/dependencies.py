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
    user = await service.resolve_local_user(identity)
    # Lets the 403 handler say who was denied (see `app.core.access_audit`).
    request.state.auth_user_id = user.id
    return user


async def get_auth_context(
    user: Annotated[User, Depends(get_authenticated_user)],
) -> AuthContext:
    return AuthContext.from_user(user)


def _forbidden(
    detail: str = "No tienes permiso para realizar esta acción.",
) -> HTTPException:
    return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)


class RequirePermission:
    """Dependency: the caller must hold `code`. Exposes `code` for introspection."""

    def __init__(self, code: str):
        self.code = code

    async def __call__(
        self,
        request: Request,
        context: Annotated[AuthContext, Depends(get_auth_context)],
    ) -> AuthContext:
        if not context.has_permission(self.code):
            request.state.denied_permission = self.code
            raise _forbidden()
        return context


class AuthenticatedOnly:
    """Marker: the route needs a signed-in person and nothing more, on purpose.

    Used where there is no single permission to ask for (the person's own notifications and
    `/auth/me`) or where the rule depends on the record (attachments: the permission of the
    ticket or equipment they belong to, checked by the service). Declaring it explicitly lets a
    test tell "open to every signed-in person" from "forgot to protect".
    """


class RequireSession(AuthenticatedOnly):
    """Dependency returning the signed-in `User`."""

    async def __call__(
        self, user: Annotated[User, Depends(get_authenticated_user)]
    ) -> User:
        return user


class RequireAuthenticated(AuthenticatedOnly):
    """Dependency returning the signed-in person's `AuthContext`."""

    async def __call__(
        self, context: Annotated[AuthContext, Depends(get_auth_context)]
    ) -> AuthContext:
        return context


def require_permission(permission_code: str) -> RequirePermission:
    return RequirePermission(permission_code)


def require_session() -> RequireSession:
    return RequireSession()


def require_authenticated() -> RequireAuthenticated:
    return RequireAuthenticated()
