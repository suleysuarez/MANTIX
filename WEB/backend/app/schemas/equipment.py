from datetime import date, datetime
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


class LocationBrief(BaseModel):
    id: int
    code: str
    name: str


class CustodianBrief(BaseModel):
    id: int
    full_name: str
    email: str


class LastMaintenance(BaseModel):
    performed_at: datetime
    work_type: str
    result: str
    technician_name: str


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
    #: When the item was registered: the first event of its history.
    created_at: datetime
    #: Where the item is now (open row of the location history), if recorded.
    current_location: LocationBrief | None = None
    #: Who holds it now (open row of the custody history), if assigned.
    current_custodian: CustodianBrief | None = None
    #: Most recent maintenance record logged against the item.
    last_maintenance: LastMaintenance | None = None


class EquipmentSummaryResponse(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "total": 28,
                "by_status": {
                    "assigned": 18,
                    "in_storage": 4,
                    "in_repair": 4,
                    "retired": 2,
                },
            }
        }
    )

    total: int
    by_status: dict[str, int]


class CustodianCandidate(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    full_name: str
    email: str


class EquipmentCreate(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "asset_tag": "LT-0042",
                "serial_number": "5CG1234XYZ",
                "equipment_type_id": 1,
                "brand": "Dell",
                "model": "Latitude 5440",
                "status": "in_storage",
                "purchase_date": "2026-01-15",
                "purchase_cost": "1250.00",
                "warranty_end_date": "2029-01-15",
            }
        }
    )

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
