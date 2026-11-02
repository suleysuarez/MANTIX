from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Literal

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from app.schemas.report_builder import MAX_RANGE_DAYS, MAX_VALUES

DocumentFormat = Literal["pdf", "xlsx"]
#: Reports with a document export: the ones the report builder lists plus the technician roster.
ExportReportKey = Literal[
    "equipment",
    "tickets",
    "summary",
    "maintenance_plans",
    "inventory_items",
    "inventory_movements",
    "technicians",
    "users",
]
TechnicianLoad = Literal["none", "low", "high"]
_Code = Annotated[str, Field(pattern=r"^[a-z][a-z_]{1,29}$")]


class ExportFilters(BaseModel):
    """Filters of a ticket export; the same ones the Tickets screen offers."""

    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "example": {
                "statuses": ["resolved", "closed"],
                "priorities": ["high"],
                "technician_ids": [4],
                "date_from": "2026-09-01T00:00:00Z",
                "date_to": "2026-09-30T23:59:59Z",
            }
        },
    )

    statuses: list[_Code] | None = Field(default=None, max_length=MAX_VALUES)
    priorities: list[_Code] | None = Field(default=None, max_length=MAX_VALUES)
    categories: list[_Code] | None = Field(default=None, max_length=MAX_VALUES)
    technician_ids: list[Annotated[int, Field(ge=1)]] | None = Field(
        default=None, max_length=50
    )
    date_from: AwareDatetime | None = None
    date_to: AwareDatetime | None = None
    # Technician roster filters (the Technicians screen offers the same ones).
    search: str | None = Field(default=None, max_length=100)
    specialty: str | None = Field(default=None, max_length=100)
    is_active: bool | None = Field(default=None, description="Account active or not")
    is_available: bool | None = Field(default=None, description="Open to new work")
    role: str | None = Field(
        default=None, max_length=50, description="Role code (users)"
    )
    load: TechnicianLoad | None = Field(
        default=None,
        description="Open tickets: none (0), low (1-2) or high (3 or more)",
    )

    @field_validator("search", "specialty", "role")
    @classmethod
    def _trimmed(cls, value: str | None) -> str | None:
        value = (value or "").strip()
        return value or None

    @field_validator("statuses", "priorities", "categories", "technician_ids")
    @classmethod
    def _no_repeats(cls, values: list[Any] | None) -> list[Any] | None:
        """An empty list means "no filter"; repeats are dropped, order kept."""
        if not values:
            return None
        return list(dict.fromkeys(values))

    @model_validator(mode="after")
    def _coherent_range(self) -> "ExportFilters":
        if self.date_from and self.date_to:
            if self.date_to < self.date_from:
                raise ValueError("date_to cannot be before date_from")
            if self.date_to - self.date_from > timedelta(days=MAX_RANGE_DAYS):
                raise ValueError(f"the date range cannot exceed {MAX_RANGE_DAYS} days")
        if self.date_from and self.date_from > datetime.now(UTC) + timedelta(days=1):
            raise ValueError("date_from cannot be in the future")
        return self


class ExportRequest(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "example": {
                "filters": {"statuses": ["resolved"]},
                "columns": ["ticket_number", "status", "total_cost"],
                "include_charts": True,
                "include_summary": True,
            }
        },
    )

    filters: ExportFilters = Field(default_factory=ExportFilters)
    columns: list[Annotated[str, Field(pattern=r"^[a-z][a-z_]{1,39}$")]] | None = Field(
        default=None,
        max_length=40,
        description="Columns to include, in the report's own order. Omit for the "
        "format's default set; an empty list is a 422.",
    )
    include_charts: bool = True
    include_summary: bool = True

    @field_validator("columns")
    @classmethod
    def _columns(cls, values: list[str] | None) -> list[str] | None:
        if values is None:
            return None
        if not values:
            raise ValueError("choose at least one column")
        return list(dict.fromkeys(values))


class ExportColumnInfo(BaseModel):
    key: str
    label: str
    kind: str
    default_pdf: bool
    default_xlsx: bool


class ExportOptions(BaseModel):
    report: ExportReportKey
    title: str
    columns: list[ExportColumnInfo]
    formats: list[DocumentFormat]
    max_rows: int
    warn_rows: int = Field(description="Above this many rows the file is slow to build")
    max_range_days: int


class ExportCount(BaseModel):
    total: int
    max_rows: int
    warn_rows: int
    over_limit: bool = Field(description="Too many rows to export; narrow the filters")
    large: bool = Field(description="Allowed, but it will take a while")
