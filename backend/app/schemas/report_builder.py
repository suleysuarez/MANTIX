from datetime import datetime, timedelta
from typing import Annotated, Any, Literal

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from app.schemas.dashboard import Period

ReportKey = Literal[
    "equipment",
    "tickets",
    "summary",
    "maintenance_plans",
    "inventory_items",
    "inventory_movements",
]
ExportFormat = Literal["csv", "xlsx", "pdf"]

#: Longest date range a report may cover, and how many values a multi-select takes.
MAX_RANGE_DAYS = 366
MAX_VALUES = 20

_Code = Annotated[str, Field(pattern=r"^[a-z][a-z_]{1,29}$")]


class ReportFilters(BaseModel):
    """Every filter a report may take. Each report accepts only some of them (the
    catalog says which); sending an unsupported one is a 422, not silently ignored."""

    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "example": {
                "statuses": ["in_progress", "waiting"],
                "priorities": ["high", "critical"],
                "date_from": "2026-09-01T00:00:00Z",
                "date_to": "2026-09-30T23:59:59Z",
            }
        },
    )

    statuses: list[_Code] | None = Field(default=None, max_length=MAX_VALUES)
    priorities: list[_Code] | None = Field(default=None, max_length=MAX_VALUES)
    categories: list[_Code] | None = Field(default=None, max_length=MAX_VALUES)
    kinds: list[_Code] | None = Field(default=None, max_length=MAX_VALUES)
    equipment_type_ids: list[Annotated[int, Field(ge=1)]] | None = Field(
        default=None, max_length=50
    )
    date_from: AwareDatetime | None = None
    date_to: AwareDatetime | None = None
    days: int | None = Field(default=None, ge=1, le=365, description="Summary window")

    @field_validator(
        "statuses", "priorities", "categories", "kinds", "equipment_type_ids"
    )
    @classmethod
    def _no_repeats(cls, values: list[Any] | None) -> list[Any] | None:
        """An empty list means 'no filter'; repeats are dropped, order kept."""
        if not values:
            return None
        return list(dict.fromkeys(values))

    @model_validator(mode="after")
    def _coherent_range(self) -> "ReportFilters":
        if self.date_from and self.date_to:
            if self.date_to < self.date_from:
                raise ValueError("date_to cannot be before date_from")
            if self.date_to - self.date_from > timedelta(days=MAX_RANGE_DAYS):
                raise ValueError(f"the date range cannot exceed {MAX_RANGE_DAYS} days")
        return self


class ReportPreviewRequest(BaseModel):
    report: ReportKey
    filters: ReportFilters = Field(default_factory=ReportFilters)
    compare: bool = Field(
        default=False,
        description="Also count the same report over the previous period of equal length",
    )


class ReportGenerateRequest(BaseModel):
    report: ReportKey
    export_format: ExportFormat = Field(default="xlsx", alias="format")
    filters: ReportFilters = Field(default_factory=ReportFilters)

    model_config = ConfigDict(populate_by_name=True)


# -- catalog --------------------------------------------------------------------------


class FilterOption(BaseModel):
    value: str
    label: str


class FilterDefinition(BaseModel):
    key: Literal[
        "statuses",
        "priorities",
        "categories",
        "kinds",
        "equipment_type_ids",
        "dates",
        "days",
    ]
    label: str
    kind: Literal["multiselect", "dates", "days"]
    options: list[FilterOption] = []


class ReportDefinitionResponse(BaseModel):
    key: ReportKey
    title: str
    description: str
    icon: str
    filters: list[FilterDefinition]
    supports_compare: bool


class CatalogResponse(BaseModel):
    reports: list[ReportDefinitionResponse]
    max_rows: int
    max_range_days: int
    formats: list[ExportFormat]


# -- preview --------------------------------------------------------------------------


class PreviewColumn(BaseModel):
    key: str
    header: str


class Comparison(BaseModel):
    """Rows of the same report in the previous period of equal length."""

    current_total: int
    previous_total: int
    change_pct: float | None
    previous_from: datetime
    previous_to: datetime


class ReportPreview(BaseModel):
    report: ReportKey
    title: str
    columns: list[PreviewColumn]
    rows: list[dict[str, str]] = Field(description="The first rows, already formatted")
    total_rows: int
    truncated: bool = Field(
        description="True when more rows exist than the export limit"
    )
    comparison: Comparison | None


# -- activity -------------------------------------------------------------------------


class UsedReport(BaseModel):
    report: ReportKey
    title: str
    count: int


class LastExport(BaseModel):
    report: ReportKey
    title: str
    export_format: ExportFormat
    row_count: int
    by: str | None
    at: datetime


class ReportsOverview(BaseModel):
    generated_at: datetime
    period: Period
    window_start: datetime
    window_end: datetime
    generated: int = Field(description="Reports generated in the period (n)")
    previous: int
    change_pct: float | None
    low_sample: bool
    most_used: list[UsedReport]
    by_format: dict[str, int]
    last_export: LastExport | None
    people: int = Field(description="Distinct people who generated one in the period")


class ReportRunResponse(BaseModel):
    id: int
    report: ReportKey
    title: str
    export_format: ExportFormat
    row_count: int
    filters: dict[str, Any]
    by: str | None
    at: datetime
