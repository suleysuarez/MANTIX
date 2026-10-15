from fastapi import APIRouter, Depends, Query

from app.api.dependencies import require_permission
from app.api.providers import get_dashboard_service
from app.core.authz import AuthContext
from app.schemas.dashboard import (
    AlertsResponse,
    DashboardSummary,
    FailingEquipmentResponse,
    KpisResponse,
    Period,
    ResolutionTimesResponse,
    TechniciansPerformanceResponse,
    TrendsResponse,
    WorkloadResponse,
)
from app.services.dashboard_kpis import DashboardKpiService

router = APIRouter(prefix="/dashboard", tags=["dashboard"])

PERIOD = Query(default="30d", description="Global dashboard period")
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
    service: DashboardKpiService = Depends(get_dashboard_service),  # noqa: B008
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
    service: DashboardKpiService = Depends(get_dashboard_service),  # noqa: B008
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
    service: DashboardKpiService = Depends(get_dashboard_service),  # noqa: B008
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
    service: DashboardKpiService = Depends(get_dashboard_service),  # noqa: B008
) -> FailingEquipmentResponse:
    return await service.top_failing_equipment(days=days, limit=limit)


@router.get(
    "/kpis",
    response_model=KpisResponse,
    summary="Headline KPIs with period-over-period comparison",
    description=(
        "MTTR, mean time to first assignment, SLA compliance, resolution rate, "
        "backlog by age and fleet availability. Each KPI compares the period "
        "against the previous one of the same length. A KPI with no tickets behind "
        "it has a null value. SLA compliance leaves out priorities without "
        "`sla_hours` and reports how many tickets that excluded (`excluded_no_sla`). "
        "Technicians only see figures for tickets assigned to them (`scope=own`)."
    ),
)
async def kpis(
    period: Period = PERIOD,
    actor: AuthContext = Depends(require_permission("dashboard.read")),  # noqa: B008
    service: DashboardKpiService = Depends(get_dashboard_service),  # noqa: B008
) -> KpisResponse:
    return await service.kpis(actor, period=period)


@router.get(
    "/trends",
    response_model=TrendsResponse,
    summary="Time series behind the KPI sparklines",
    description=(
        "One point per UTC day (7d, 30d) or month (12m), zero-filled: tickets "
        "created, tickets resolved, MTTR and SLA compliance of the tickets resolved "
        "in that bucket (null when none)."
    ),
)
async def trends(
    period: Period = PERIOD,
    actor: AuthContext = Depends(require_permission("dashboard.read")),  # noqa: B008
    service: DashboardKpiService = Depends(get_dashboard_service),  # noqa: B008
) -> TrendsResponse:
    return await service.trends(actor, period=period)


@router.get(
    "/alerts",
    response_model=AlertsResponse,
    summary="What needs attention now",
    description=(
        "Open tickets that are critical and unassigned or whose SLA is breached or "
        "about to be; equipment that is down (in repair or lost) with the time it "
        "has been down; preventive plans overdue or due within 7 days."
    ),
)
async def alerts(
    actor: AuthContext = Depends(require_permission("dashboard.read")),  # noqa: B008
    service: DashboardKpiService = Depends(get_dashboard_service),  # noqa: B008
) -> AlertsResponse:
    return await service.alerts(actor)


@router.get(
    "/technicians",
    response_model=TechniciansPerformanceResponse,
    summary="Technician performance for the period",
    description=(
        "Per technician: open tickets now, tickets resolved in the period, median "
        "resolution time, SLA compliance (priorities without `sla_hours` are left "
        "out and counted in `sla_excluded_no_sla`), sample sizes with a `low_sample` "
        "flag (n < 5) and reopened tickets. Ordered by open tickets (load), not by "
        "performance. Technicians only see their own row (`scope=own`)."
    ),
)
async def technicians_performance(
    period: Period = PERIOD,
    actor: AuthContext = Depends(require_permission("dashboard.read")),  # noqa: B008
    service: DashboardKpiService = Depends(get_dashboard_service),  # noqa: B008
) -> TechniciansPerformanceResponse:
    return await service.technicians(actor, period=period)
