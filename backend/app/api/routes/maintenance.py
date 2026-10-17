from datetime import datetime

from fastapi import APIRouter, Depends, Query, Response, status

from app.api.dependencies import require_permission
from app.api.pagination import page_params, set_page_headers
from app.api.providers import get_maintenance_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.core.pagination import PageParams
from app.domain.ticket_state import TicketState
from app.schemas.maintenance import (
    MaintenanceClassifyRequest,
    MaintenanceRecordCreate,
    MaintenanceRecordResponse,
    MaintenanceRejectRequest,
    MaintenanceRequestCreate,
    MaintenanceRequestListItem,
    MaintenanceRequestResponse,
    MaintenanceStatusTransitionRequest,
    TicketAssignmentCreateRequest,
    WorkflowState,
)
from app.services.maintenance import MaintenanceService

router = APIRouter(prefix="/maintenance/requests", tags=["maintenance"])


@router.get(
    "/workflow",
    response_model=list[WorkflowState],
    summary="Ticket statuses and the moves between them",
    description=(
        "Every status in workflow order with the statuses it may move to and the data "
        "a person must supply to enter it. Boards read this to draw their columns, "
        "highlight valid drops and ask for what is missing; nothing is hard-coded there."
    ),
)
async def ticket_workflow(
    _: AuthContext = Depends(require_permission("tickets:ver")),  # noqa: B008
) -> list[WorkflowState]:
    return [
        WorkflowState(
            status=state.status,
            order=state.order,
            allowed_targets=sorted(state.allowed_targets),
            requires=list(state.requires),
            terminal=state.is_terminal,
            in_queue=state.in_queue,
        )
        for state in TicketState.workflow()
    ]


@router.post(
    "", response_model=MaintenanceRequestResponse, status_code=status.HTTP_201_CREATED
)
async def create_maintenance_request(
    payload: MaintenanceRequestCreate,
    actor: AuthContext = Depends(require_permission("solicitudes:crear")),  # noqa: B008
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
    status_filter: str | None = Query(
        default=None,
        alias="status",
        description="One status or a comma-separated list, e.g. `submitted,triaged`",
    ),
    priority: str | None = Query(default=None),
    category: str | None = Query(default=None),
    unassigned: bool | None = Query(
        default=None, description="True: no technician yet; false: has one"
    ),
    equipment_id: int | None = Query(default=None),
    search: str | None = Query(
        default=None,
        max_length=100,
        description="Matches ticket number, title or description",
    ),
    date_from: datetime | None = Query(default=None, description="Created at or after"),  # noqa: B008
    date_to: datetime | None = Query(default=None, description="Created at or before"),  # noqa: B008
    params: PageParams = Depends(page_params(default_size=200)),  # noqa: B008
    actor: AuthContext = Depends(require_permission("tickets:ver")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> list[MaintenanceRequestListItem]:
    page = await service.list_requests(
        status=status_filter,
        priority=priority,
        category=category,
        unassigned=unassigned,
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
    actor: AuthContext = Depends(require_permission("tickets:ver")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await service.get_request(request_id, actor)


@router.post("/{request_id}/status", response_model=MaintenanceRequestResponse)
async def transition_maintenance_request_status(
    request_id: int,
    payload: MaintenanceStatusTransitionRequest,
    actor: AuthContext = Depends(require_permission("tickets:cambiar_estado")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await service.transition_status(request_id, payload, actor)


@router.post(
    "/{request_id}/classify",
    response_model=MaintenanceRequestResponse,
    summary="Classify (triage) a request",
    description=(
        "Sets the category and priority, both of which must be active catalog "
        "entries (422 otherwise), and moves a `submitted` request to `triaged`. "
        "A `triaged` request can be reclassified. Audited with the previous and "
        "new values. ADMIN and SUPERVISOR only."
    ),
    responses=error_responses(404, 409, 422),
)
async def classify_maintenance_request(
    request_id: int,
    payload: MaintenanceClassifyRequest,
    actor: AuthContext = Depends(require_permission("solicitudes:editar")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await service.classify_request(request_id, payload, actor)


@router.post(
    "/{request_id}/reject",
    response_model=MaintenanceRequestResponse,
    summary="Reject a request that has not started",
    description=(
        "Cancels a submitted, triaged or assigned request. A reason of at least 5 "
        "characters is required and is kept in the status history. ADMIN and "
        "SUPERVISOR only."
    ),
)
async def reject_maintenance_request(
    request_id: int,
    payload: MaintenanceRejectRequest,
    actor: AuthContext = Depends(require_permission("solicitudes:aprobar")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await service.reject_request(request_id, payload.reason, actor)


@router.post("/{request_id}/assignment", response_model=MaintenanceRequestResponse)
async def assign_technician(
    request_id: int,
    payload: TicketAssignmentCreateRequest,
    actor: AuthContext = Depends(require_permission("tickets:asignar")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await service.assign_technician(request_id, payload, actor)


@router.delete("/{request_id}/assignment", response_model=MaintenanceRequestResponse)
async def unassign_technician(
    request_id: int,
    actor: AuthContext = Depends(require_permission("tickets:asignar")),  # noqa: B008
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
    actor: AuthContext = Depends(require_permission("tickets:editar")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> MaintenanceRecordResponse:
    return await service.add_maintenance_record(request_id, payload, actor)


@router.get("/{request_id}/records", response_model=list[MaintenanceRecordResponse])
async def list_maintenance_records(
    request_id: int,
    actor: AuthContext = Depends(require_permission("tickets:ver")),  # noqa: B008
    service: MaintenanceService = Depends(get_maintenance_service),  # noqa: B008
) -> list[MaintenanceRecordResponse]:
    return await service.list_records(request_id, actor)
