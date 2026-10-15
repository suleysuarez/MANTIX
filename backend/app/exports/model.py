"""What a report export contains, independent of the output format.

A `ReportExport` describes the report once (metadata, table, summary, charts, extra
sheets); the PDF and Excel renderers turn the same object into a file.
"""

from collections.abc import Sequence
from dataclasses import dataclass, field, replace
from typing import Any, Literal

Kind = Literal["text", "date", "datetime", "int", "number", "money", "bool"]
Total = Literal["sum", "count", "avg", "share_true"]
Align = Literal["left", "right", "center"]


@dataclass(frozen=True, slots=True)
class ExportColumn:
    key: str
    header: str
    kind: Kind = "text"
    #: Approximate width in characters (Excel) and relative weight (PDF).
    width: int = 14
    #: Totals row: `sum` adds, `count` counts non-empty cells, `avg` averages, `share_true`
    #: is the percentage of Sí among the Sí/No cells.
    total: Total | None = None
    #: Text left, numbers right, dates and states centered unless a report says otherwise.
    align: Align | None = None

    @property
    def numeric(self) -> bool:
        return self.kind in ("int", "number", "money")

    @property
    def alignment(self) -> Align:
        if self.align is not None:
            return self.align
        if self.numeric:
            return "right"
        return "center" if self.kind in ("date", "datetime", "bool") else "left"


@dataclass(frozen=True, slots=True)
class MetaItem:
    label: str
    value: str


@dataclass(frozen=True, slots=True)
class SummaryLine:
    label: str
    #: Number kept apart from its text so Excel gets a real number and charts can plot it.
    value: float | int | None
    text: str


@dataclass(frozen=True, slots=True)
class SummaryGroup:
    title: str
    lines: Sequence[SummaryLine]
    #: Draw this group as a chart (when charts are included).
    chart: Literal["bar", "pie"] | None = None
    #: Headline figures: first in the PDF summary and at the top of the Excel summary.
    kpi: bool = False


@dataclass(frozen=True, slots=True)
class ExtraSheet:
    """A second table (for example "Por técnico") with its own columns and totals."""

    name: str
    title: str
    columns: Sequence[ExportColumn]
    rows: Sequence[dict[str, Any]]


@dataclass(frozen=True, slots=True)
class ReportExport:
    key: str
    #: Upper-case title in the header, e.g. `REPORTE DE TICKETS`.
    title: str
    #: Section above the table, e.g. `DESGLOSE DE TICKETS`.
    section: str
    columns: Sequence[ExportColumn]
    rows: Sequence[dict[str, Any]]
    meta_left: Sequence[MetaItem]
    meta_right: Sequence[MetaItem]
    summary: Sequence[SummaryGroup] = ()
    extra_sheets: Sequence[ExtraSheet] = ()
    sheet_name: str = "Detalle"
    extras: dict[str, Any] = field(default_factory=dict)

    def only(self, keys: Sequence[str] | None) -> "ReportExport":
        """Keep the chosen columns (in the report's own order); `None` keeps them all."""
        if not keys:
            return self
        chosen = [column for column in self.columns if column.key in set(keys)]
        return replace(self, columns=chosen)
