from fastapi import APIRouter, Depends, Query
from pydantic import AwareDatetime

from app.api.dependencies import require_permission
from app.api.providers import get_maintenance_overview_service
from app.core.authz import AuthContext
from app.schemas.dashboard import Period
from app.schemas.maintenance_overview import CalendarResponse, MaintenanceOverview
from app.services.maintenance_overview import (
    MAX_CALENDAR_DAYS,
    MaintenanceOverviewService,
)

router = APIRouter(prefix="/maintenance", tags=["maintenance"])

PERIOD = Query(default="30d", description="Global dashboard period")
RANGE_START = Query(description="Start of the range (timezone-aware, inclusive)")
RANGE_END = Query(description="End of the range (timezone-aware, exclusive)")


@router.get(
    "/overview",
    response_model=MaintenanceOverview,
    summary="Maintenance metrics for the period",
    description=(
        "Preventive vs corrective mix, services overdue or due in 7 and 30 days, plan "
        "compliance per week, real vs estimated duration, cost and reschedules. Each "
        "figure compares with the previous period and reports its sample size; a "
        "figure with no data is null."
    ),
)
async def maintenance_overview(
    period: Period = PERIOD,
    _: AuthContext = Depends(require_permission("maintenance.read")),  # noqa: B008
    service: MaintenanceOverviewService = Depends(get_maintenance_overview_service),  # noqa: B008
) -> MaintenanceOverview:
    return await service.overview(period=period)


@router.get(
    "/calendar",
    response_model=CalendarResponse,
    summary="Preventive services in a date range",
    description=(
        f"Planned, overdue and done occurrences of the preventive plans. The range "
        f"is at most {MAX_CALENDAR_DAYS} days. Occurrences after a plan's next date "
        "are projected one interval apart."
    ),
)
async def maintenance_calendar(
    start: AwareDatetime = RANGE_START,
    end: AwareDatetime = RANGE_END,
    _: AuthContext = Depends(require_permission("maintenance.read")),  # noqa: B008
    service: MaintenanceOverviewService = Depends(get_maintenance_overview_service),  # noqa: B008
) -> CalendarResponse:
    return await service.calendar(start=start, end=end)
