import re
from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from app.schemas.dashboard import Period

Category = Literal["spare_part", "consumable", "accessory", "tool", "other"]
MovementKind = Literal["in", "out", "adjust"]
StockStatus = Literal["ok", "low", "out"]

#: Largest quantity or stock the system accepts (a sanity limit, not a business rule).
MAX_QUANTITY = 1_000_000
#: Largest unit cost: 2 decimals, never negative.
Money = Annotated[Decimal, Field(ge=0, le=1_000_000, max_digits=12, decimal_places=2)]
Quantity = Annotated[int, Field(ge=0, le=MAX_QUANTITY)]

_SKU_PATTERN = r"^[A-Z0-9][A-Z0-9._-]{2,39}$"
_UNIT_PATTERN = r"^[A-Za-zÁÉÍÓÚáéíóúÑñ0-9 ./]{1,20}$"


def _strip(value: str | None) -> str | None:
    return value.strip() if value is not None else None


class ItemFields(BaseModel):
    """Fields shared by creation and (partial) update."""

    name: str = Field(min_length=3, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    category: Category = "spare_part"
    unit: str = Field(default="unidad", pattern=_UNIT_PATTERN)
    unit_cost: Money = Decimal("0.00")
    min_stock: Quantity = 0
    max_stock: Quantity | None = None
    location: str | None = Field(default=None, max_length=100)
    supplier: str | None = Field(default=None, max_length=150)

    @field_validator("name", mode="before")
    @classmethod
    def _name(cls, value: str) -> str:
        return value.strip() if isinstance(value, str) else value

    @field_validator("description", "location", "supplier", mode="before")
    @classmethod
    def _optional_text(cls, value: str | None) -> str | None:
        """Trim; a blank string means 'not set'."""
        return (_strip(value) or None) if isinstance(value, str) else value

    @field_validator("unit", mode="before")
    @classmethod
    def _unit(cls, value: str) -> str:
        return value.strip() if isinstance(value, str) else value


class ItemCreate(ItemFields):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "sku": "SSD-512",
                "name": "SSD 512 GB",
                "category": "spare_part",
                "unit": "unidad",
                "unit_cost": "64.90",
                "min_stock": 5,
                "max_stock": 40,
                "initial_stock": 12,
            }
        }
    )

    sku: str = Field(description="Unique code; stored in upper case")
    initial_stock: Quantity = 0

    @field_validator("sku", mode="before")
    @classmethod
    def _sku(cls, value: str) -> str:
        return value.strip().upper() if isinstance(value, str) else value

    @field_validator("sku")
    @classmethod
    def _sku_format(cls, value: str) -> str:
        if not re.fullmatch(_SKU_PATTERN, value):
            raise ValueError(
                "must be 3-40 characters: letters, digits, '.', '_' or '-'"
            )
        return value

    @model_validator(mode="after")
    def _max_not_below_min(self) -> "ItemCreate":
        if self.max_stock is not None and self.max_stock < self.min_stock:
            raise ValueError("max_stock cannot be below min_stock")
        return self


class ItemUpdate(BaseModel):
    """Partial update. Stock changes only through movements."""

    name: str | None = Field(default=None, min_length=3, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    category: Category | None = None
    unit: str | None = Field(default=None, pattern=_UNIT_PATTERN)
    unit_cost: Money | None = None
    min_stock: Quantity | None = None
    max_stock: Quantity | None = None
    location: str | None = Field(default=None, max_length=100)
    supplier: str | None = Field(default=None, max_length=150)
    is_active: bool | None = None

    @field_validator("name", "unit", mode="before")
    @classmethod
    def _trim(cls, value: str | None) -> str | None:
        return value.strip() if isinstance(value, str) else value

    @field_validator("description", "location", "supplier", mode="before")
    @classmethod
    def _optional_text(cls, value: str | None) -> str | None:
        return (_strip(value) or None) if isinstance(value, str) else value


class ItemResponse(BaseModel):
    id: int
    sku: str
    name: str
    description: str | None
    category: Category
    unit: str
    unit_cost: Decimal
    stock: int
    min_stock: int
    max_stock: int | None
    location: str | None
    supplier: str | None
    is_active: bool
    status: StockStatus = Field(
        description="`out` at zero, `low` at or below the minimum, otherwise `ok`"
    )
    stock_value: Decimal = Field(description="stock x unit_cost")
    level_pct: float = Field(
        description="Stock against the maximum (or twice the minimum when none is set)"
    )
    last_movement_at: datetime | None
    created_at: datetime
    updated_at: datetime


class MovementCreate(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "kind": "out",
                "quantity": 2,
                "record_id": 31,
                "notes": "Cambio de SSD",
            }
        }
    )

    kind: MovementKind
    quantity: int = Field(
        ge=-MAX_QUANTITY,
        le=MAX_QUANTITY,
        description="`in` and `out`: units, always positive. `adjust`: signed, not zero",
    )
    unit_cost: Money | None = Field(
        default=None, description="Cost of an entry; updates the item's average cost"
    )
    notes: str | None = Field(default=None, max_length=300)
    record_id: int | None = Field(
        default=None, description="Maintenance record that used it"
    )
    request_id: int | None = Field(default=None, description="Ticket that used it")

    @field_validator("notes", mode="before")
    @classmethod
    def _notes(cls, value: str | None) -> str | None:
        return (_strip(value) or None) if isinstance(value, str) else value

    @model_validator(mode="after")
    def _coherent(self) -> "MovementCreate":
        if self.quantity == 0:
            raise ValueError("quantity cannot be zero")
        if self.kind in ("in", "out") and self.quantity < 0:
            raise ValueError("quantity must be positive for entries and consumption")
        if self.unit_cost is not None and self.kind != "in":
            raise ValueError("unit_cost only applies to entries")
        if (self.record_id or self.request_id) and self.kind != "out":
            raise ValueError(
                "a maintenance record or ticket only applies to consumption"
            )
        return self


class MovementResponse(BaseModel):
    id: int
    item_id: int
    kind: MovementKind
    quantity: int = Field(description="Signed: entries > 0, consumption < 0")
    stock_after: int
    unit_cost: Decimal | None
    notes: str | None
    record_id: int | None
    request_id: int | None
    created_by: str | None
    created_at: datetime


# -- overview -----------------------------------------------------------------------


class StockValue(BaseModel):
    """Valued at each item's current unit cost; `previous` is the stock at the period start."""

    total: Decimal
    previous: Decimal | None
    change_pct: float | None
    items: int = Field(description="Active items counted")


class Consumption(BaseModel):
    units: int
    value: Decimal
    previous_units: int
    change_pct: float | None
    movements: int = Field(description="Consumption movements in the period (n)")
    low_sample: bool


class Rotation(BaseModel):
    """Consumed value over the stock value at the start of the period."""

    value: float | None
    previous: float | None
    change_pct: float | None


class MonthlyConsumption(BaseModel):
    month: datetime = Field(description="First day of the month, UTC")
    units: int


class ReorderAlert(BaseModel):
    item_id: int
    sku: str
    name: str
    stock: int
    min_stock: int
    suggested_order: int = Field(
        description="Units to reach the maximum (or twice the minimum)"
    )


class StaleItem(BaseModel):
    item_id: int
    sku: str
    name: str
    stock: int
    last_movement_at: datetime | None


class UsedItem(BaseModel):
    item_id: int
    sku: str
    name: str
    units: int


class InventoryOverview(BaseModel):
    generated_at: datetime
    period: Period
    window_start: datetime
    window_end: datetime
    stock_value: StockValue
    low_stock: int = Field(description="Active items at or below their minimum, now")
    out_of_stock: int
    consumption: Consumption
    rotation: Rotation
    monthly_consumption: list[MonthlyConsumption]
    stale_count: int = Field(description="Items in stock with no movement for 90 days")
    stale_items: list[StaleItem]
    most_used: list[UsedItem] = Field(description="Most consumed in maintenance work")
    reorder: list[ReorderAlert] = Field(
        description="Replenishment alerts, most urgent first"
    )
