from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import require_permission
from app.db.session import get_db
from app.models.auth import User
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
    actor: User = Depends(require_permission("maintenance.create")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await MaintenanceService(session).create_request(payload, actor)


@router.get("", response_model=list[MaintenanceRequestListItem])
async def list_maintenance_requests(
    status_filter: str | None = Query(default=None, alias="status"),
    priority: str | None = Query(default=None),
    equipment_id: int | None = Query(default=None),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    actor: User = Depends(require_permission("maintenance.read")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> list[MaintenanceRequestListItem]:
    return await MaintenanceService(session).list_requests(
        status=status_filter,
        priority=priority,
        equipment_id=equipment_id,
        limit=limit,
        offset=offset,
        actor=actor,
    )


@router.get("/{request_id}", response_model=MaintenanceRequestResponse)
async def get_maintenance_request(
    request_id: int,
    actor: User = Depends(require_permission("maintenance.read")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await MaintenanceService(session).get_request(request_id, actor)


@router.post("/{request_id}/status", response_model=MaintenanceRequestResponse)
async def transition_maintenance_request_status(
    request_id: int,
    payload: MaintenanceStatusTransitionRequest,
    actor: User = Depends(require_permission("maintenance.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await MaintenanceService(session).transition_status(
        request_id, payload, actor
    )


@router.post("/{request_id}/assignment", response_model=MaintenanceRequestResponse)
async def assign_technician(
    request_id: int,
    payload: TicketAssignmentCreateRequest,
    actor: User = Depends(require_permission("maintenance.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await MaintenanceService(session).assign_technician(
        request_id, payload, actor
    )


@router.delete("/{request_id}/assignment", response_model=MaintenanceRequestResponse)
async def unassign_technician(
    request_id: int,
    actor: User = Depends(require_permission("maintenance.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> MaintenanceRequestResponse:
    return await MaintenanceService(session).unassign_technician(request_id, actor)


@router.post(
    "/{request_id}/records",
    response_model=MaintenanceRecordResponse,
    status_code=status.HTTP_201_CREATED,
)
async def add_maintenance_record(
    request_id: int,
    payload: MaintenanceRecordCreate,
    actor: User = Depends(require_permission("maintenance.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> MaintenanceRecordResponse:
    return await MaintenanceService(session).add_maintenance_record(
        request_id, payload, actor
    )


@router.get("/{request_id}/records", response_model=list[MaintenanceRecordResponse])
async def list_maintenance_records(
    request_id: int,
    actor: User = Depends(require_permission("maintenance.read")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> list[MaintenanceRecordResponse]:
    return await MaintenanceService(session).list_records(request_id, actor)
