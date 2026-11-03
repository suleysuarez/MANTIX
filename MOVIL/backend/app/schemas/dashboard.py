from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Scope = Literal["all", "own"]


class CountItem(BaseModel):
    key: str = Field(examples=["in_progress"])
    count: int


class TicketMetrics(BaseModel):
    total: int
    open: int
    overdue: int = Field(description="Open tickets past the SLA of their priority")
    by_status: list[CountItem]
    open_by_priority: list[CountItem] = Field(description="Most urgent first")


class ResolutionTime(BaseModel):
    priority: str | None = Field(description="Null for the overall figure")
    resolved_count: int
    avg_hours: float | None
    median_hours: float | None


class DashboardSummary(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "generated_at": "2026-10-11T15:00:00Z",
                "scope": "all",
                "window_days": 30,
                "tickets": {
                    "total": 128,
                    "open": 17,
                    "overdue": 3,
                    "by_status": [{"key": "in_progress", "count": 9}],
                    "open_by_priority": [{"key": "critical", "count": 2}],
                },
                "equipment_by_status": [{"key": "assigned", "count": 240}],
                "resolution": {
                    "priority": None,
                    "resolved_count": 41,
                    "avg_hours": 18.4,
                    "median_hours": 9.2,
                },
            }
        }
    )

    generated_at: datetime
    scope: Scope = Field(description="`own` when limited to the caller's tickets")
    window_days: int
    tickets: TicketMetrics
    equipment_by_status: list[CountItem]
    resolution: ResolutionTime


class TechnicianWorkload(BaseModel):
    technician_id: int
    full_name: str
    is_available: bool
    open_tickets: int
    resolved_in_window: int


class WorkloadResponse(BaseModel):
    window_days: int
    scope: Scope
    technicians: list[TechnicianWorkload]


class ResolutionTimesResponse(BaseModel):
    window_days: int
    scope: Scope
    overall: ResolutionTime
    by_priority: list[ResolutionTime]


class FailingEquipment(BaseModel):
    equipment_id: int
    asset_tag: str
    brand: str
    model: str
    tickets: int
    last_ticket_at: datetime | None


class FailingEquipmentResponse(BaseModel):
    window_days: int
    equipment: list[FailingEquipment]


# -- KPIs, trends and alerts ----------------------------------------------------

Period = Literal["7d", "30d", "12m"]


class KpiValue(BaseModel):
    """One headline figure with its comparison against the previous period.

    `value` is null when no ticket backs it (an empty state, never a misleading 0).
    """

    value: float | None
    previous: float | None
    change_pct: float | None = Field(
        description="Relative change vs the previous period; null when not comparable"
    )
    sample_size: int = Field(description="Tickets behind the current value (n)")
    low_sample: bool = Field(
        description="True when 0 < n < 5: show the value with a 'few data' note"
    )


class ResolutionTimeKpi(KpiValue):
    """Resolution time: `value` is the median, with the rest of the distribution.

    All figures are hours over the tickets resolved in the period; `previous` and
    `change_pct` compare the median against the previous period.
    """

    average_hours: float | None
    p90_hours: float | None
    min_hours: float | None
    max_hours: float | None
    stddev_hours: float | None = Field(
        description="Sample standard deviation; null with fewer than 2 tickets"
    )


class SlaKpi(KpiValue):
    met: int = Field(description="Resolved inside the SLA of their priority")
    missed: int = Field(description="Resolved after the SLA of their priority")
    excluded_no_sla: int = Field(
        description="Resolved tickets whose priority has no SLA: neither met nor missed"
    )


class BacklogKpi(BaseModel):
    open: int
    previous_open: int | None = Field(description="Open tickets at the period start")
    change_pct: float | None = Field(
        description="Open tickets now vs at the period start; null when not comparable"
    )
    age_0_2_days: int
    age_3_7_days: int
    age_over_7_days: int


class AvailabilityKpi(BaseModel):
    """Operational (assigned or in storage) over all equipment, now.

    `previous` is the same share at the start of the period, rebuilt from the
    equipment status history, so `change_pct` is the change over the period.
    """

    value: float | None
    previous: float | None
    change_pct: float | None
    operational: int
    total: int


class KpisResponse(BaseModel):
    generated_at: datetime
    scope: Scope
    period: Period
    window_start: datetime
    window_end: datetime
    mttr_hours: ResolutionTimeKpi = Field(
        description="Creation-to-resolution time: median, mean, P90, min, max and stddev"
    )
    first_assignment_hours: KpiValue = Field(
        description="Mean creation-to-first-assignment time"
    )
    sla_compliance_pct: SlaKpi
    resolution_rate_pct: KpiValue = Field(
        description="Tickets created in the period that are already resolved"
    )
    backlog: BacklogKpi
    availability: AvailabilityKpi


class TrendPoint(BaseModel):
    bucket: datetime = Field(
        description="Start of the day (7d, 30d) or month (12m), UTC"
    )
    created: int
    resolved: int
    mttr_hours: float | None
    sla_compliance_pct: float | None


class TrendsResponse(BaseModel):
    generated_at: datetime
    scope: Scope
    period: Period
    granularity: Literal["day", "month"]
    points: list[TrendPoint]


AlertReason = Literal["unassigned_critical", "sla_breached", "sla_at_risk"]


class TicketAlert(BaseModel):
    id: int
    ticket_number: str
    title: str
    equipment_id: int
    asset_tag: str
    priority: str
    status: str
    assigned: bool
    sla_deadline: datetime | None
    reason: AlertReason


class DownEquipmentAlert(BaseModel):
    equipment_id: int
    asset_tag: str
    brand: str
    model: str
    status: str
    down_since: datetime | None
    down_hours: float | None


class ScheduleAlert(BaseModel):
    id: int
    equipment_id: int
    asset_tag: str
    title: str
    next_due_at: datetime
    overdue: bool


class AlertsResponse(BaseModel):
    generated_at: datetime
    scope: Scope
    tickets: list[TicketAlert]
    down_equipment: list[DownEquipmentAlert]
    schedules: list[ScheduleAlert]


class TechnicianPerformance(BaseModel):
    technician_id: int
    full_name: str
    specialization: str | None
    is_available: bool
    open_tickets: int = Field(description="Assigned and still open, right now")
    resolved: int = Field(description="Tickets they resolved inside the period")
    mttr_median_hours: float | None = Field(
        description="Median creation-to-resolution time of those tickets"
    )
    sample_size: int = Field(description="n behind the MTTR: tickets resolved")
    low_sample: bool = Field(description="True when 0 < n < 5")
    sla_compliance_pct: float | None
    sla_sample_size: int = Field(
        description="Resolved tickets whose priority has an SLA"
    )
    sla_low_sample: bool
    sla_excluded_no_sla: int = Field(
        description="Resolved tickets left out of the SLA: their priority has no sla_hours"
    )
    reopened: int = Field(description="Tickets moved from resolved back to in progress")


class TechniciansPerformanceResponse(BaseModel):
    generated_at: datetime
    scope: Scope
    period: Period
    window_start: datetime
    window_end: datetime
    technicians: list[TechnicianPerformance] = Field(
        description="Busiest first (open tickets), never ranked by performance"
    )
