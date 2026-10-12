from datetime import datetime

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

from app.schemas.maintenance import EquipmentSummary, TechnicianSummary


class ScheduleResponse(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "id": 4,
                "equipment": {
                    "id": 12,
                    "asset_tag": "SRV-0003",
                    "brand": "Dell",
                    "model": "PowerEdge R450",
                },
                "technician": {"id": 2, "user_id": 8, "full_name": "Luis Mora"},
                "title": "Quarterly server cleaning",
                "description": "Dust filters and fan check",
                "interval_days": 90,
                "remind_days_before": 7,
                "next_due_at": "2026-12-01T09:00:00Z",
                "last_reminded_at": None,
                "is_active": True,
                "created_at": "2026-10-11T15:00:00Z",
            }
        }
    )

    id: int
    equipment: EquipmentSummary
    technician: TechnicianSummary | None
    title: str
    description: str | None
    interval_days: int
    remind_days_before: int
    next_due_at: datetime
    last_reminded_at: datetime | None
    is_active: bool
    created_at: datetime


class ScheduleCreate(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "equipment_id": 12,
                "technician_id": 2,
                "title": "Quarterly server cleaning",
                "description": "Dust filters and fan check",
                "interval_days": 90,
                "remind_days_before": 7,
                "first_due_at": "2026-12-01T09:00:00Z",
            }
        }
    )

    equipment_id: int
    technician_id: int | None = Field(
        default=None, description="Who is reminded; defaults to the plan's creator"
    )
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    interval_days: int = Field(ge=1, le=3650, description="Days between services")
    remind_days_before: int = Field(default=3, ge=0, le=365)
    first_due_at: AwareDatetime

    @model_validator(mode="after")
    def reminder_fits_in_interval(self) -> "ScheduleCreate":
        if self.remind_days_before > self.interval_days:
            raise ValueError("remind_days_before cannot exceed interval_days")
        return self


class ScheduleUpdate(BaseModel):
    """Partial update. Send `technician_id: null` to clear the assignee."""

    technician_id: int | None = None
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    interval_days: int | None = Field(default=None, ge=1, le=3650)
    remind_days_before: int | None = Field(default=None, ge=0, le=365)
    next_due_at: AwareDatetime | None = None
    is_active: bool | None = None


class ReminderRunResponse(BaseModel):
    locked_by_another_worker: bool = Field(
        description="True when another instance is already running the job"
    )
    reminders_sent: int
    skipped_without_recipient: int
