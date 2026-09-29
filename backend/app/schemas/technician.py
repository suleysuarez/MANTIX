from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class TechnicianResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    specialization: str | None
    is_available: bool
    hourly_rate: Decimal | None


class TechnicianCreate(BaseModel):
    user_id: int
    specialization: str | None = Field(default=None, max_length=100)
    hourly_rate: Decimal | None = Field(default=None, ge=0, decimal_places=2)


class TechnicianUpdate(BaseModel):
    specialization: str | None = Field(default=None, max_length=100)
    is_available: bool | None = None
    hourly_rate: Decimal | None = Field(default=None, ge=0, decimal_places=2)
