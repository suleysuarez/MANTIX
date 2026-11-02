"""PDF/Excel export for every report of the gallery (equipment, plans, inventory…).

The ticket and technician reports have their own definitions; the rest are plain tables, so
this builds the same `ReportExport` from a dataset's columns and rows: status columns become
coloured pills, the summary shows the total and the most frequent statuses, and the Excel
summary gets a doughnut and a bar chart of the first two categorical columns.
"""

from collections import Counter
from collections.abc import Sequence
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from app.exports.formatting import status_tone
from app.exports.meta import meta_items, report_code
from app.exports.model import (
    ExportColumn,
    Kind,
    ReportExport,
    SummaryGroup,
    SummaryLine,
)

PREFIXES = {
    "equipment": "EQ",
    "tickets": "TICK",
    "summary": "RES",
    "maintenance_plans": "MANT",
    "inventory_items": "INV",
    "inventory_movements": "MOV",
}
#: Columns that hold a status, drawn as pills.
PILL_KEYS = frozenset({"status", "kind"})
#: Columns worth a chart, in order of preference; only those with a few distinct values.
CATEGORICAL = (
    "status",
    "kind",
    "equipment_type",
    "category",
    "priority",
    "location",
    "technician",
)
MAX_CATEGORIES = 12
SUBTITLES = {
    "equipment": "Listado y estado actual de los equipos tecnológicos",
    "tickets": "Solicitudes de mantenimiento, su prioridad y su resolución",
    "summary": "Métricas operativas del periodo",
    "maintenance_plans": "Planes de mantenimiento preventivo y su próxima fecha",
    "inventory_items": "Existencias, mínimos, valor y proveedor",
    "inventory_movements": "Entradas, consumos y ajustes de stock",
}


def _kind(key: str, rows: Sequence[dict[str, Any]]) -> Kind:
    sample = next((row[key] for row in rows if row.get(key) not in (None, "")), None)
    if isinstance(sample, bool):
        return "bool"
    if isinstance(sample, datetime):
        return "datetime"
    if isinstance(sample, date):
        return "date"
    if isinstance(sample, int):
        return "int"
    if isinstance(sample, Decimal | float):
        return "money" if "cost" in key or "value" in key else "number"
    return "text"


def _columns(
    dataset_columns: Sequence[Any], rows: Sequence[dict[str, Any]]
) -> list[ExportColumn]:
    out = []
    for column in dataset_columns:
        kind = _kind(column.key, rows)
        pill = column.key in PILL_KEYS and kind == "text"
        out.append(
            ExportColumn(
                column.key,
                column.header,
                kind,
                width=int(column.width),
                align="center" if pill else None,
                pill=pill,
            )
        )
    return out


def _counts(rows: Sequence[dict[str, Any]], key: str) -> Counter[str]:
    return Counter(str(row[key]) for row in rows if row.get(key) not in (None, ""))


def _summary(
    columns: Sequence[ExportColumn], rows: Sequence[dict[str, Any]], key: str
) -> list[SummaryGroup]:
    total = len(rows)
    cards = [SummaryLine("Total de registros", total, str(total), "Filas del reporte")]
    groups: list[SummaryGroup] = []
    charted = 0
    for column in columns:
        if column.key not in CATEGORICAL or column.kind != "text":
            continue
        counts = _counts(rows, column.key)
        if not 1 <= len(counts) <= MAX_CATEGORIES:
            continue
        lines = [SummaryLine(label, n, str(n)) for label, n in counts.most_common()]
        if column.pill and len(cards) == 1:

            def share(n: int) -> str:
                return f"{round(n / total * 100)} % del total" if total else ""

            cards += [
                SummaryLine(label, n, str(n), share(n), status_tone(label))
                for label, n in counts.most_common(3)
            ]
        if charted < 2:
            groups.append(
                SummaryGroup(
                    f"Por {column.header.lower()}",
                    lines,
                    chart="pie" if charted == 0 else "bar",
                )
            )
            charted += 1
    return [SummaryGroup("Resumen general", cards, kpi=True), *groups]


def build_generic_export(
    *,
    key: str,
    title: str,
    dataset_columns: Sequence[Any],
    rows: list[dict[str, Any]],
    generated_by: str,
    generated_at: datetime,
    filters: str,
    period: str,
) -> ReportExport:
    columns = _columns(dataset_columns, rows)
    meta = meta_items(
        code=report_code(PREFIXES.get(key, "REP"), generated_at),
        generated_by=generated_by,
        generated_at=generated_at,
        records=len(rows),
        period=period,
        filters=filters,
    )
    return ReportExport(
        key=key,
        title=f"REPORTE DE {title.upper()}",
        section=f"Detalle de {title.lower()}",
        columns=columns,
        rows=rows,
        subtitle=SUBTITLES.get(key, "Gestión de equipos tecnológicos"),
        meta_left=meta[0],
        meta_right=meta[1],
        summary=_summary(columns, rows, key),
    )
