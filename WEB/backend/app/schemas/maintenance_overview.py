from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.dashboard import Period


class WorkMix(BaseModel):
    """Maintenance records started in the period, by kind of work."""

    preventive: int
    corrective: int
    other: int
    sample_size: int = Field(description="Records in the period (n)")
    low_sample: bool = Field(description="True when 0 < n < 5")
    preventive_pct: float | None = Field(description="Preventive share of all records")
    previous_preventive_pct: float | None
    change_pct: float | None = Field(
        description="Relative change of the preventive share vs the previous period"
    )


class Upcoming(BaseModel):
    """Active plans by due date, measured now (not tied to the period)."""

    overdue: int
    next_7_days: int
    next_30_days: int


class WeekCompliance(BaseModel):
    week_start: datetime = Field(description="Monday 00:00 UTC")
    planned: int = Field(description="Services due that week: done plus still overdue")
    on_time: int
    compliance_pct: float | None


class PlanCompliance(BaseModel):
    """Services due in the period that were done on or before their due date."""

    weeks: list[WeekCompliance]
    planned: int
    on_time: int
    sample_size: int = Field(description="Services due in the period (n)")
    low_sample: bool
    compliance_pct: float | None
    previous_compliance_pct: float | None
    change_pct: float | None


class DurationComparison(BaseModel):
    """Real vs estimated hours for completed services that report both."""

    average_actual_hours: float | None
    average_estimated_hours: float | None
    variance_pct: float | None = Field(
        description="(actual - estimated) / estimated; positive means it took longer"
    )
    previous_variance_pct: float | None
    sample_size: int
    low_sample: bool


class CostSummary(BaseModel):
    total: Decimal = Field(description="Sum of `total_cost` of the period's records")
    previous_total: Decimal
    change_pct: float | None
    records_with_cost: int = Field(description="Records that report a cost (n)")
    average_per_record: Decimal | None
    low_sample: bool


class Reschedules(BaseModel):
    count: int
    previous: int
    change_pct: float | None


class MaintenanceOverview(BaseModel):
    generated_at: datetime
    period: Period
    window_start: datetime
    window_end: datetime
    mix: WorkMix
    upcoming: Upcoming
    compliance: PlanCompliance
    duration: DurationComparison
    cost: CostSummary
    reschedules: Reschedules


CalendarKind = Literal["planned", "overdue", "done"]


class CalendarEvent(BaseModel):
    kind: CalendarKind
    schedule_id: int
    title: str
    equipment_id: int
    asset_tag: str
    technician: str | None
    at: datetime = Field(description="The due date of this occurrence")
    completed_at: datetime | None = Field(description="Only for `done` events")
    on_time: bool | None = Field(description="Only for `done` events")


class CalendarResponse(BaseModel):
    generated_at: datetime
    start: datetime
    end: datetime
    truncated: bool = Field(description="True when the event cap was reached")
    events: list[CalendarEvent]
