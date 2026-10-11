from fastapi import APIRouter, Depends, Query

from app.api.dependencies import require_permission
from app.api.providers import get_dashboard_service
from app.core.authz import AuthContext
from app.schemas.dashboard import (
    DashboardSummary,
    FailingEquipmentResponse,
    ResolutionTimesResponse,
    WorkloadResponse,
)
from app.services.dashboard import DashboardService

router = APIRouter(prefix="/dashboard", tags=["dashboard"])

DAYS = Query(default=30, ge=1, le=365, description="Look-back window in days")


@router.get(
    "/summary",
    response_model=DashboardSummary,
    summary="Operational summary",
    description=(
        "Tickets by status, open tickets by priority, overdue tickets (past the "
        "SLA of their priority), equipment by status and resolution times. "
        "Technicians only see figures for tickets assigned to them (`scope=own`)."
    ),
)
async def summary(
    days: int = DAYS,
    actor: AuthContext = Depends(require_permission("dashboard.read")),  # noqa: B008
    service: DashboardService = Depends(get_dashboard_service),  # noqa: B008
) -> DashboardSummary:
    return await service.summary(actor, days=days)


@router.get(
    "/workload",
    response_model=WorkloadResponse,
    summary="Workload per technician",
    description="Open assigned tickets and tickets resolved inside the window.",
)
async def workload(
    days: int = DAYS,
    actor: AuthContext = Depends(require_permission("dashboard.read")),  # noqa: B008
    service: DashboardService = Depends(get_dashboard_service),  # noqa: B008
) -> WorkloadResponse:
    return await service.workload(actor, days=days)


@router.get(
    "/resolution-times",
    response_model=ResolutionTimesResponse,
    summary="Mean and median resolution time",
    description="Hours from ticket creation to resolution, overall and per priority.",
)
async def resolution_times(
    days: int = DAYS,
    actor: AuthContext = Depends(require_permission("dashboard.read")),  # noqa: B008
    service: DashboardService = Depends(get_dashboard_service),  # noqa: B008
) -> ResolutionTimesResponse:
    return await service.resolution_times(actor, days=days)


@router.get(
    "/top-failing-equipment",
    response_model=FailingEquipmentResponse,
    summary="Equipment with the most tickets",
)
async def top_failing_equipment(
    days: int = DAYS,
    limit: int = Query(default=10, ge=1, le=50),
    _: AuthContext = Depends(require_permission("dashboard.read")),  # noqa: B008
    service: DashboardService = Depends(get_dashboard_service),  # noqa: B008
) -> FailingEquipmentResponse:
    return await service.top_failing_equipment(days=days, limit=limit)
