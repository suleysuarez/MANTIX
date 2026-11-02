from datetime import datetime

from fastapi import APIRouter, Depends, Query, Response, status

from app.api.dependencies import require_permission
from app.api.pagination import page_params, set_page_headers
from app.api.providers import get_user_management_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.core.pagination import PageParams
from app.schemas.user_management import (
    PasswordReset,
    RolesReplace,
    UserCreate,
    UserListItem,
    UsersSummary,
    UserUpdate,
)
from app.services.user_management import UserManagementService

router = APIRouter(prefix="/admin/users", tags=["users"])

SEARCH = Query(
    default=None, max_length=100, description="Name, e-mail or employee code"
)
ROLE = Query(default=None, max_length=50, description="Role code, e.g. `TECHNICIAN`")
ACTIVE = Query(default=None, description="True: active accounts; false: inactive ones")
CREATED_FROM = Query(default=None, description="Created at or after")
CREATED_TO = Query(default=None, description="Created at or before")


@router.get(
    "",
    response_model=list[UserListItem],
    summary="List users",
    description=(
        "Search, filter by role, state and creation date, with server-side sorting and "
        "pagination. Sort fields: `name`, `email`, `created_at`, `last_login_at`, "
        "`is_active`. ADMIN only (`users.manage`)."
    ),
    responses=error_responses(403, 422),
)
async def list_users(
    response: Response,
    search: str | None = SEARCH,
    role: str | None = ROLE,
    is_active: bool | None = ACTIVE,
    created_from: datetime | None = CREATED_FROM,
    created_to: datetime | None = CREATED_TO,
    params: PageParams = Depends(page_params(default_size=20)),  # noqa: B008
    _: AuthContext = Depends(require_permission("usuarios:ver")),  # noqa: B008
    service: UserManagementService = Depends(get_user_management_service),  # noqa: B008
) -> list[UserListItem]:
    page = await service.list_users(
        search=search,
        role=role,
        is_active=is_active,
        created_from=created_from,
        created_to=created_to,
        params=params,
    )
    set_page_headers(response, page)
    return page.items


@router.get(
    "/summary",
    response_model=UsersSummary,
    summary="Indicators of the Users screen",
    description="Users per role, active vs inactive, never signed in and the latest sign-ins.",
    responses=error_responses(403),
)
async def users_summary(
    _: AuthContext = Depends(require_permission("usuarios:ver")),  # noqa: B008
    service: UserManagementService = Depends(get_user_management_service),  # noqa: B008
) -> UsersSummary:
    return await service.summary()


@router.post(
    "",
    response_model=UserListItem,
    status_code=status.HTTP_201_CREATED,
    summary="Pre-register a user",
    description=(
        "Creates the account with its roles. The person signs in with that e-mail and the "
        "account is linked at that moment; passwords are managed by the sign-in service. "
        "E-mail and employee code must be unique (case-insensitive). Audited."
    ),
    responses=error_responses(403, 404, 409, 422),
)
async def create_user(
    payload: UserCreate,
    actor: AuthContext = Depends(require_permission("usuarios:crear")),  # noqa: B008
    service: UserManagementService = Depends(get_user_management_service),  # noqa: B008
) -> UserListItem:
    return await service.create(payload, actor)


@router.get(
    "/{user_id}",
    response_model=UserListItem,
    summary="Get a user",
    responses=error_responses(403, 404),
)
async def get_user(
    user_id: int,
    _: AuthContext = Depends(require_permission("usuarios:ver")),  # noqa: B008
    service: UserManagementService = Depends(get_user_management_service),  # noqa: B008
) -> UserListItem:
    return await service.get(user_id)


@router.patch(
    "/{user_id}",
    response_model=UserListItem,
    summary="Edit a user",
    description=(
        "Name, phone, employee code and (only before the first sign-in) e-mail. Audited with "
        "the previous values."
    ),
    responses=error_responses(403, 404, 409, 422),
)
async def update_user(
    user_id: int,
    payload: UserUpdate,
    actor: AuthContext = Depends(require_permission("usuarios:editar")),  # noqa: B008
    service: UserManagementService = Depends(get_user_management_service),  # noqa: B008
) -> UserListItem:
    return await service.update(user_id, payload, actor)


@router.post(
    "/{user_id}/deactivate",
    response_model=UserListItem,
    summary="Deactivate a user",
    description=(
        "Accounts are never deleted. You cannot deactivate yourself or the last active ADMIN "
        "(409)."
    ),
    responses=error_responses(403, 404, 409),
)
async def deactivate_user(
    user_id: int,
    actor: AuthContext = Depends(require_permission("usuarios:cambiar_estado")),  # noqa: B008
    service: UserManagementService = Depends(get_user_management_service),  # noqa: B008
) -> UserListItem:
    return await service.set_active(user_id, False, actor)


@router.post(
    "/{user_id}/activate",
    response_model=UserListItem,
    summary="Reactivate a user",
    responses=error_responses(403, 404),
)
async def activate_user(
    user_id: int,
    actor: AuthContext = Depends(require_permission("usuarios:cambiar_estado")),  # noqa: B008
    service: UserManagementService = Depends(get_user_management_service),  # noqa: B008
) -> UserListItem:
    return await service.set_active(user_id, True, actor)


@router.put(
    "/{user_id}/roles",
    response_model=UserListItem,
    summary="Set the roles of a user",
    description=(
        "Replaces the user's roles with the given ones (at least one). You cannot remove your "
        "own ADMIN role or leave the system without an active ADMIN (409). Audited."
    ),
    responses=error_responses(403, 404, 409, 422),
)
async def set_roles(
    user_id: int,
    payload: RolesReplace,
    actor: AuthContext = Depends(require_permission("usuarios:asignar")),  # noqa: B008
    service: UserManagementService = Depends(get_user_management_service),  # noqa: B008
) -> UserListItem:
    return await service.replace_roles(user_id, payload.role_ids, actor)


@router.post(
    "/{user_id}/password",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Set a new password for a user",
    description=(
        "Sets the password through the sign-in service (10+ characters with upper case, lower "
        "case and digits, no spaces) and signs the person's other sessions out. The password is "
        "never stored or logged. Not for your own account, and only for people who already "
        "signed in once. Audited."
    ),
    responses=error_responses(403, 404, 409, 422),
)
async def reset_password(
    user_id: int,
    payload: PasswordReset,
    actor: AuthContext = Depends(require_permission("usuarios:editar")),  # noqa: B008
    service: UserManagementService = Depends(get_user_management_service),  # noqa: B008
) -> Response:
    await service.reset_password(user_id, payload.password, actor)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
