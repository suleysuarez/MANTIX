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
