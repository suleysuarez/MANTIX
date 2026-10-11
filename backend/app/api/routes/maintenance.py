from datetime import datetime

from fastapi import APIRouter, Depends, Query, Response, status

from app.api.dependencies import require_permission
from app.api.pagination import page_params, set_page_headers
from app.api.providers import get_maintenance_service
from app.core.authz import AuthContext
from app.core.pagination import PageParams
from app.schemas.maintenance import (
    MaintenanceRecordCreate,
    MaintenanceRecordResponse,
    MaintenanceRequestCreate,
    MaintenanceRequestListItem,
    MaintenanceRequestResponse,
    MaintenanceStatusTransitionRequest,
    TicketAssignmentCreateRequest,
)
from app.services.maintenance import MaintenanceService

router = APIRouter(prefix="/maintenance/requests", tags=["maintenance"])


@router.post(
    "", response_model=MaintenanceRequestResponse, status_code=status.HTTP_201_CREATED
)
async def create_maintenance_request(
    payload: MaintenanceRequestCreate,
    actor: AuthContext = Depends(require_permission("maintenance.create")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await service.create_request(payload, actor)


@router.get(
    "",
    response_model=list[MaintenanceRequestListItem],
    summary="List maintenance tickets",
    description=(
        "Admins and supervisors see every ticket; technicians see the tickets "
        "assigned to them; everyone else sees only their own. "
        "Sort fields: `created_at`, `updated_at`, `status`, `priority` "
        "(by urgency level), `ticket_number`."
    ),
)
async def list_maintenance_requests(
    response: Response,
    status_filter: str | None = Query(default=None, alias="status"),
    priority: str | None = Query(default=None),
    equipment_id: int | None = Query(default=None),
    search: str | None = Query(
        default=None,
        max_length=100,
        description="Matches ticket number, title or description",
    ),
    date_from: datetime | None = Query(default=None, description="Created at or after"),  # noqa: B008
    date_to: datetime | None = Query(default=None, description="Created at or before"),  # noqa: B008
    params: PageParams = Depends(page_params(default_size=200)),  # noqa: B008
    actor: AuthContext = Depends(require_permission("maintenance.read")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> list[MaintenanceRequestListItem]:
    page = await service.list_requests(
        status=status_filter,
        priority=priority,
        equipment_id=equipment_id,
        search=search,
        date_from=date_from,
        date_to=date_to,
        params=params,
        actor=actor,
    )
    set_page_headers(response, page)
    return page.items


@router.get("/{request_id}", response_model=MaintenanceRequestResponse)
async def get_maintenance_request(
    request_id: int,
    actor: AuthContext = Depends(require_permission("maintenance.read")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await service.get_request(request_id, actor)


@router.post("/{request_id}/status", response_model=MaintenanceRequestResponse)
async def transition_maintenance_request_status(
    request_id: int,
    payload: MaintenanceStatusTransitionRequest,
    actor: AuthContext = Depends(require_permission("maintenance.manage")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await service.transition_status(request_id, payload, actor)


@router.post("/{request_id}/assignment", response_model=MaintenanceRequestResponse)
async def assign_technician(
    request_id: int,
    payload: TicketAssignmentCreateRequest,
    actor: AuthContext = Depends(require_permission("maintenance.manage")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await service.assign_technician(request_id, payload, actor)


@router.delete("/{request_id}/assignment", response_model=MaintenanceRequestResponse)
async def unassign_technician(
    request_id: int,
    actor: AuthContext = Depends(require_permission("maintenance.manage")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await service.unassign_technician(request_id, actor)


@router.post(
    "/{request_id}/records",
    response_model=MaintenanceRecordResponse,
    status_code=status.HTTP_201_CREATED,
)
async def add_maintenance_record(
    request_id: int,
    payload: MaintenanceRecordCreate,
    actor: AuthContext = Depends(require_permission("maintenance.manage")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRecordResponse:
    return await service.add_maintenance_record(request_id, payload, actor)


@router.get("/{request_id}/records", response_model=list[MaintenanceRecordResponse])
async def list_maintenance_records(
    request_id: int,
    actor: AuthContext = Depends(require_permission("maintenance.read")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> list[MaintenanceRecordResponse]:
    return await service.list_records(request_id, actor)
