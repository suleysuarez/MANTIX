from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import require_permission
from app.db.session import get_db
from app.models.auth import User
from app.schemas.admin import (
    AdminRoleResponse,
    AssignRolesRequest,
    ManagedUserResponse,
    PendingUserResponse,
)
from app.services.admin import AdminUserService

router = APIRouter(prefix="/admin", tags=["administration"])


@router.get(
    "/users/pending",
    response_model=list[PendingUserResponse],
)
async def list_pending_users(
    _: User = Depends(require_permission("users.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> list[PendingUserResponse]:
    """List active users with no local application role assignment."""
    return await AdminUserService(session).list_pending_users()


@router.get("/roles", response_model=list[AdminRoleResponse])
async def list_roles(
    _: User = Depends(require_permission("users.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> list[AdminRoleResponse]:
    return await AdminUserService(session).list_roles()


@router.post(
    "/users/{user_id}/roles",
    response_model=ManagedUserResponse,
    status_code=status.HTTP_200_OK,
)
async def assign_roles(
    user_id: int,
    payload: AssignRolesRequest,
    admin: User = Depends(require_permission("users.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> ManagedUserResponse:
    return await AdminUserService(session).assign_roles(
        user_id, payload.role_ids, admin
    )
