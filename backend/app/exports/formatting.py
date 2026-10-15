"""Cell text shared by the PDF (Excel keeps real numbers and dates instead)."""

from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Any

from app.exports.model import ExportColumn, Kind
from app.exports.theme import DATE_FORMAT, DATETIME_FORMAT, DISPLAY_TZ

EMPTY = "—"


def local(value: datetime) -> datetime:
    """A timestamp in display time; naive values are taken as UTC."""
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(DISPLAY_TZ)


def _grouped(value: float | Decimal, decimals: int) -> str:
    """`1,234.50` rendered the Spanish way: `1.234,50`."""
    text = f"{value:,.{decimals}f}"
    return text.replace(",", "\0").replace(".", ",").replace("\0", ".")


def format_value(value: Any, kind: Kind) -> str:
    if value is None or value == "":
        return "N/A" if kind == "bool" else EMPTY
    if kind == "bool":
        return "Sí" if value else "No"
    if kind in ("date", "datetime"):
        if isinstance(value, datetime):
            return local(value).strftime(
                DATE_FORMAT if kind == "date" else DATETIME_FORMAT
            )
        if isinstance(value, date):
            return value.strftime(DATE_FORMAT)
        return str(value)
    if kind == "money":
        return "$ " + _grouped(value, 2)
    if kind == "number":
        return _grouped(value, 1)
    if kind == "int":
        return _grouped(value, 0)
    return str(value)


def total_of(column: ExportColumn, rows: list[dict[str, Any]]) -> Any:
    """Value of a column's totals-row cell (computed here for the PDF)."""
    values = [row.get(column.key) for row in rows]
    present = [v for v in values if v is not None and v != ""]
    if column.total == "count":
        return len(present)
    if column.total == "sum":
        return sum(present, Decimal(0)) if column.kind == "money" else sum(present)
    return None
