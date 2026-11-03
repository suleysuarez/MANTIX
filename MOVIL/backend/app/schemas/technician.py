from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class TechnicianResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    #: Identity of the person behind the profile (read from the linked user).
    full_name: str
    email: str
    employee_code: str | None
    specialization: str | None
    is_available: bool
    #: Whether the linked user account is active; boards only offer active technicians.
    is_active: bool
    hourly_rate: Decimal | None
    #: When the profile was registered: the first event of its history.
    created_at: datetime


class TechnicianCreate(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "user_id": 7,
                "specialization": "Networking",
                "hourly_rate": "25.00",
            }
        }
    )

    user_id: int
    specialization: str | None = Field(default=None, max_length=100)
    hourly_rate: Decimal | None = Field(default=None, ge=0, decimal_places=2)


class TechnicianUpdate(BaseModel):
    specialization: str | None = Field(default=None, max_length=100)
    is_available: bool | None = None
    hourly_rate: Decimal | None = Field(default=None, ge=0, decimal_places=2)
