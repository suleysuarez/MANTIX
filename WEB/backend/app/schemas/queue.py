from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.dashboard import CountItem, KpiValue, Period


class RequestCategoryResponse(BaseModel):
    code: str
    name: str


class TriageTimeKpi(KpiValue):
    """Hours from creation to the first decision on a request (the first time it
    leaves `submitted`). `value` is the mean; `previous`/`change_pct` compare it."""

    median_hours: float | None


class DecisionKpi(BaseModel):
    """Requests decided in the period: the first exit from `submitted` is either an
    approval (triaged or assigned) or a rejection (cancelled)."""

    approved: int
    rejected: int
    sample_size: int = Field(description="Decisions in the period (n)")
    low_sample: bool = Field(description="True when 0 < n < 5")
    approval_rate_pct: float | None
    rejection_rate_pct: float | None
    previous_approval_rate_pct: float | None
    change_pct: float | None = Field(
        description="Relative change of the approval rate vs the previous period"
    )


class QueueSummary(BaseModel):
    generated_at: datetime
    period: Period
    window_start: datetime
    window_end: datetime
    pending_total: int = Field(
        description="Submitted, triaged or assigned (not started)"
    )
    unassigned: int = Field(description="Pending requests with no technician yet")
    oldest_wait_hours: float | None = Field(
        description="Longest time in queue right now"
    )
    median_wait_hours: float | None
    by_priority: list[CountItem] = Field(
        description="Pending requests, most urgent first"
    )
    by_category: list[CountItem] = Field(
        description="Pending requests per category; `uncategorized` when unset"
    )
    triage_time: TriageTimeKpi
    decisions: DecisionKpi
