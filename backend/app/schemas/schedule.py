from datetime import datetime
from decimal import Decimal
from typing import Annotated

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from app.schemas.maintenance import EquipmentSummary, TechnicianSummary

#: Hours with two decimals, positive and below a day-and-a-bit of work per service.
Hours = Annotated[Decimal, Field(gt=0, le=999, max_digits=6, decimal_places=2)]


def _clean(value: str | None) -> str | None:
    return value.strip() if value is not None else None


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
    estimated_hours: Decimal | None = None
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
    estimated_hours: Hours | None = None
    remind_days_before: int = Field(default=3, ge=0, le=365)
    first_due_at: AwareDatetime

    @field_validator("title")
    @classmethod
    def _title_not_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("must not be blank")
        return value

    @field_validator("description")
    @classmethod
    def _description_trimmed(cls, value: str | None) -> str | None:
        return _clean(value) or None

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
    estimated_hours: Hours | None = None
    remind_days_before: int | None = Field(default=None, ge=0, le=365)
    next_due_at: AwareDatetime | None = None
    reschedule_reason: str | None = Field(
        default=None, max_length=500, description="Why the due date moved"
    )
    is_active: bool | None = None

    @field_validator("title")
    @classmethod
    def _title_not_blank(cls, value: str | None) -> str | None:
        if value is None:
            return value
        value = value.strip()
        if not value:
            raise ValueError("must not be blank")
        return value

    @field_validator("description", "reschedule_reason")
    @classmethod
    def _trimmed(cls, value: str | None) -> str | None:
        return _clean(value) or None


class ScheduleCompleteRequest(BaseModel):
    model_config = ConfigDict(json_schema_extra={"example": {"actual_hours": "1.50"}})

    actual_hours: Hours | None = Field(
        default=None, description="Hours the service really took"
    )


class ScheduleRunResponse(BaseModel):
    id: int
    due_at: datetime
    completed_at: datetime
    on_time: bool
    actual_hours: Decimal | None


class ScheduleRescheduleResponse(BaseModel):
    id: int
    old_due_at: datetime
    new_due_at: datetime
    reason: str | None
    changed_at: datetime


class ScheduleHistoryResponse(BaseModel):
    runs: list[ScheduleRunResponse]
    reschedules: list[ScheduleRescheduleResponse]


class ReminderRunResponse(BaseModel):
    locked_by_another_worker: bool = Field(
        description="True when another instance is already running the job"
    )
    reminders_sent: int
    skipped_without_recipient: int
