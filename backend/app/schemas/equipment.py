from datetime import date
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

EquipmentStatus = Literal[
    "in_storage",
    "assigned",
    "in_repair",
    "lost",
    "retired",
    "disposed",
]


class EquipmentTypeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    code: str
    name: str


class EquipmentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    asset_tag: str
    serial_number: str | None
    equipment_type_id: int
    equipment_type: EquipmentTypeResponse
    brand: str
    model: str
    description: str | None
    status: str
    purchase_date: date | None
    purchase_cost: Decimal | None
    warranty_start_date: date | None
    warranty_end_date: date | None


class EquipmentCreate(BaseModel):
    asset_tag: str = Field(min_length=1, max_length=50)
    serial_number: str | None = Field(default=None, max_length=100)
    equipment_type_id: int
    brand: str = Field(min_length=1, max_length=100)
    model: str = Field(min_length=1, max_length=100)
    description: str | None = None
    status: EquipmentStatus = "in_storage"
    purchase_date: date | None = None
    purchase_cost: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    warranty_start_date: date | None = None
    warranty_end_date: date | None = None

    @model_validator(mode="after")
    def validate_warranty_dates(self) -> "EquipmentCreate":
        if (
            self.warranty_start_date
            and self.warranty_end_date
            and self.warranty_end_date < self.warranty_start_date
        ):
            raise ValueError("warranty_end_date cannot precede warranty_start_date")
        return self


class LocationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    code: str
    name: str
    kind: str
    parent_id: int | None


class LocationCreate(BaseModel):
    code: str = Field(min_length=1, max_length=50)
    name: str = Field(min_length=1, max_length=150)
    kind: str = Field(min_length=1, max_length=50)
    parent_id: int | None = None
    description: str | None = None


class EquipmentLocationAssignRequest(BaseModel):
    location_id: int
    notes: str | None = None


class EquipmentCustodyAssignRequest(BaseModel):
    assigned_to_user_id: int
    notes: str | None = None


class EquipmentUpdate(BaseModel):
    serial_number: str | None = Field(default=None, max_length=100)
    equipment_type_id: int | None = None
    brand: str | None = Field(default=None, min_length=1, max_length=100)
    model: str | None = Field(default=None, min_length=1, max_length=100)
    description: str | None = None
    status: EquipmentStatus | None = None
    purchase_date: date | None = None
    purchase_cost: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    warranty_start_date: date | None = None
    warranty_end_date: date | None = None

    @model_validator(mode="after")
    def validate_warranty_dates(self) -> "EquipmentUpdate":
        if (
            self.warranty_start_date
            and self.warranty_end_date
            and self.warranty_end_date < self.warranty_start_date
        ):
            raise ValueError("warranty_end_date cannot precede warranty_start_date")
        return self
