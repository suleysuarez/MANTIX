from fastapi import APIRouter, Depends, Query, status

from app.api.dependencies import require_permission
from app.api.providers import get_priority_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.schemas.priority import PriorityCreate, PriorityResponse, PriorityUpdate
from app.services.priority import PriorityService

router = APIRouter(prefix="/priorities", tags=["priorities"])


@router.get(
    "",
    response_model=list[PriorityResponse],
    summary="List ticket priorities",
    description="Priorities ordered from most to least urgent. Inactive ones are "
    "hidden unless `include_inactive=true`.",
    responses=error_responses(401, 403),
)
async def list_priorities(
    include_inactive: bool = Query(default=False),
    _: AuthContext = Depends(require_permission("tickets:ver")),  # noqa: B008
    service: PriorityService = Depends(get_priority_service),  # noqa: B008
) -> list[PriorityResponse]:
    return await service.list(include_inactive=include_inactive)


@router.post(
    "",
    response_model=PriorityResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a priority",
    responses=error_responses(401, 403, 409, 422),
)
async def create_priority(
    payload: PriorityCreate,
    actor: AuthContext = Depends(require_permission("configuracion:editar")),  # noqa: B008
    service: PriorityService = Depends(get_priority_service),  # noqa: B008
) -> PriorityResponse:
    return await service.create(payload, actor)


@router.patch(
    "/{priority_id}",
    response_model=PriorityResponse,
    summary="Update a priority",
    description="Partial update. The `code` cannot change; deactivate a priority "
    "with `is_active=false` instead of deleting it.",
    responses=error_responses(401, 403, 404, 422),
)
async def update_priority(
    priority_id: int,
    payload: PriorityUpdate,
    actor: AuthContext = Depends(require_permission("configuracion:editar")),  # noqa: B008
    service: PriorityService = Depends(get_priority_service),  # noqa: B008
) -> PriorityResponse:
    return await service.update(priority_id, payload, actor)
