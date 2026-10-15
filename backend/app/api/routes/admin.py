from fastapi import APIRouter, Depends, status

from app.api.dependencies import require_permission
from app.api.providers import get_admin_user_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.schemas.admin import (
    AdminRoleResponse,
    AssignRolesRequest,
    ManagedUserResponse,
    PendingUserResponse,
    PermissionDetail,
    RoleDetailResponse,
)
from app.services.admin import AdminUserService

router = APIRouter(prefix="/admin", tags=["administration"])


@router.get(
    "/users/pending",
    response_model=list[PendingUserResponse],
)
async def list_pending_users(
    _: AuthContext = Depends(require_permission("usuarios:ver")),  # noqa: B008
    service: AdminUserService = Depends(get_admin_user_service),  # noqa: B008
) -> list[PendingUserResponse]:
    """List active users with no local application role assignment."""
    return await service.list_pending_users()


@router.get("/roles", response_model=list[AdminRoleResponse])
async def list_roles(
    _: AuthContext = Depends(require_permission("usuarios:ver")),  # noqa: B008
    service: AdminUserService = Depends(get_admin_user_service),  # noqa: B008
) -> list[AdminRoleResponse]:
    return await service.list_roles()


@router.post(
    "/users/{user_id}/roles",
    response_model=ManagedUserResponse,
    status_code=status.HTTP_200_OK,
)
async def assign_roles(
    user_id: int,
    payload: AssignRolesRequest,
    admin: AuthContext = Depends(require_permission("usuarios:asignar")),  # noqa: B008
    service: AdminUserService = Depends(get_admin_user_service),  # noqa: B008
) -> ManagedUserResponse:
    return await service.assign_roles(user_id, payload.role_ids, admin)


@router.get(
    "/roles/matrix",
    response_model=list[RoleDetailResponse],
    summary="Role-permission matrix",
    description="Every active role with the permissions it currently grants.",
)
async def role_matrix(
    _: AuthContext = Depends(require_permission("configuracion:ver")),  # noqa: B008
    service: AdminUserService = Depends(get_admin_user_service),  # noqa: B008
) -> list[RoleDetailResponse]:
    return await service.role_matrix()


@router.get(
    "/permissions",
    response_model=list[PermissionDetail],
    summary="List permissions",
)
async def list_permissions(
    _: AuthContext = Depends(require_permission("configuracion:ver")),  # noqa: B008
    service: AdminUserService = Depends(get_admin_user_service),  # noqa: B008
) -> list[PermissionDetail]:
    return await service.list_permissions()


@router.delete(
    "/users/{user_id}/roles/{role_id}",
    response_model=ManagedUserResponse,
    summary="Revoke a role from a user",
    description="Refuses to remove your own ADMIN role or the last active ADMIN.",
    responses=error_responses(404, 409),
)
async def revoke_role(
    user_id: int,
    role_id: int,
    admin: AuthContext = Depends(require_permission("usuarios:asignar")),  # noqa: B008
    service: AdminUserService = Depends(get_admin_user_service),  # noqa: B008
) -> ManagedUserResponse:
    return await service.revoke_role(user_id, role_id, admin)
