from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class PriorityResponse(BaseModel):
    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "example": {
                "id": 3,
                "code": "high",
                "name": "High",
                "description": "Significant impact on daily work",
                "level": 3,
                "sla_hours": 24,
                "is_active": True,
                "created_at": "2026-10-11T12:00:00Z",
            }
        },
    )

    id: int
    code: str
    name: str
    description: str | None
    level: int = Field(description="Urgency weight; higher is more urgent")
    sla_hours: int | None = Field(description="Target resolution time in hours")
    is_active: bool
    created_at: datetime


class PriorityCreate(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "code": "urgent",
                "name": "Urgent",
                "description": "Needs attention within the hour",
                "level": 5,
                "sla_hours": 1,
            }
        }
    )

    code: str = Field(pattern=r"^[a-z][a-z_]{1,19}$", description="Stable identifier")
    name: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    level: int = Field(ge=1, le=100)
    sla_hours: int | None = Field(default=None, gt=0, le=24 * 365)


class PriorityUpdate(BaseModel):
    """Partial update; `code` is immutable because tickets reference it."""

    name: str | None = Field(default=None, min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    level: int | None = Field(default=None, ge=1, le=100)
    sla_hours: int | None = Field(default=None, gt=0, le=24 * 365)
    is_active: bool | None = None
