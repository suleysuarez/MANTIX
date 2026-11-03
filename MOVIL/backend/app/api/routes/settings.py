from fastapi import APIRouter, Depends, Request, Response, status

from app.api.dependencies import require_permission
from app.api.providers import get_system_settings_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.jobs import job_snapshots
from app.schemas.settings import (
    CategoryAdmin,
    CategoryCreate,
    CategoryUpdate,
    OrganizationResponse,
    OrganizationUpdate,
    SystemHealth,
)
from app.services.settings import SystemSettingsService

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get(
    "/health",
    response_model=SystemHealth,
    summary="System health",
    description=(
        "Users and roles, the latest audit entries, scheduled jobs (next and last "
        "run) and the state of the integrations (database, authentication provider, "
        "attachment storage), plus the read-only runtime parameters. Never returns "
        "secrets. ADMIN only."
    ),
)
async def system_health(
    request: Request,
    _: AuthContext = Depends(require_permission("configuracion:ver")),  # noqa: B008
    service: SystemSettingsService = Depends(get_system_settings_service),  # noqa: B008
) -> SystemHealth:
    scheduler = getattr(request.app.state, "scheduler", None)
    return await service.health(job_snapshots(scheduler))


@router.get(
    "/categories",
    response_model=list[CategoryAdmin],
    summary="Request categories, with how many requests use each",
)
async def list_categories(
    _: AuthContext = Depends(require_permission("configuracion:ver")),  # noqa: B008
    service: SystemSettingsService = Depends(get_system_settings_service),  # noqa: B008
) -> list[CategoryAdmin]:
    return await service.categories()


@router.post(
    "/categories",
    response_model=CategoryAdmin,
    status_code=status.HTTP_201_CREATED,
    summary="Create a request category",
    responses=error_responses(409, 422),
)
async def create_category(
    payload: CategoryCreate,
    actor: AuthContext = Depends(require_permission("configuracion:editar")),  # noqa: B008
    service: SystemSettingsService = Depends(get_system_settings_service),  # noqa: B008
) -> CategoryAdmin:
    return await service.create_category(payload, actor)


@router.patch(
    "/categories/{category_id}",
    response_model=CategoryAdmin,
    summary="Rename or (de)activate a category",
    description="The `code` cannot change because requests reference it.",
    responses=error_responses(404, 422),
)
async def update_category(
    category_id: int,
    payload: CategoryUpdate,
    actor: AuthContext = Depends(require_permission("configuracion:editar")),  # noqa: B008
    service: SystemSettingsService = Depends(get_system_settings_service),  # noqa: B008
) -> CategoryAdmin:
    return await service.update_category(category_id, payload, actor)


@router.delete(
    "/categories/{category_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete an unused category",
    description="A category that requests use cannot be deleted: deactivate it.",
    responses=error_responses(404, 409),
)
async def delete_category(
    category_id: int,
    actor: AuthContext = Depends(require_permission("configuracion:editar")),  # noqa: B008
    service: SystemSettingsService = Depends(get_system_settings_service),  # noqa: B008
) -> Response:
    await service.delete_category(category_id, actor)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get(
    "/organization",
    response_model=OrganizationResponse,
    summary="Company shown in report headers",
    description="Company name, legal name and tax id (NIT). ADMIN only.",
)
async def get_organization(
    _: AuthContext = Depends(require_permission("configuracion:ver")),  # noqa: B008
    service: SystemSettingsService = Depends(get_system_settings_service),  # noqa: B008
) -> OrganizationResponse:
    return await service.organization()


@router.put(
    "/organization",
    response_model=OrganizationResponse,
    summary="Set the company shown in report headers",
    description="Replaces the three fields; blank optional ones are cleared. Audited.",
    responses=error_responses(422),
)
async def update_organization(
    payload: OrganizationUpdate,
    actor: AuthContext = Depends(require_permission("configuracion:editar")),  # noqa: B008
    service: SystemSettingsService = Depends(get_system_settings_service),  # noqa: B008
) -> OrganizationResponse:
    return await service.update_organization(payload, actor)
