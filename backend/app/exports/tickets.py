"""Ticket export: the fields come from the database (equipment, type, category,
priority and SLA, technician, dates and the costs on the ticket's records)."""

from collections import Counter, defaultdict
from decimal import Decimal
from typing import Any

from app.exports.base import ExportContext, ExportDefinition, Scope
from app.exports.formatting import format_value, local
from app.exports.meta import meta_items, report_code
from app.exports.model import (
    ExportColumn,
    ExtraSheet,
    ReportExport,
    SummaryGroup,
    SummaryLine,
)
from app.exports.theme import DATE_FORMAT
from app.repositories.export import ExportRepository
from app.schemas.export import ExportFilters

STATUS_LABELS = {
    "submitted": "Enviado",
    "triaged": "Clasificado",
    "assigned": "Asignado",
    "in_progress": "En curso",
    "waiting": "En espera",
    "resolved": "Resuelto",
    "closed": "Cerrado",
    "cancelled": "Cancelado",
}
PRIORITY_LABELS = {
    "critical": "Crítica",
    "high": "Alta",
    "medium": "Media",
    "low": "Baja",
}
OPEN_STATUSES = {"submitted", "triaged", "assigned", "in_progress", "waiting"}
DONE_STATUSES = {"resolved", "closed"}
NO_TECHNICIAN = "Sin asignar"
NO_CATEGORY = "Sin categoría"

COLUMNS = (
    ExportColumn("ticket_number", "Ticket", width=19, total="count"),
    ExportColumn("title", "Título", width=34),
    ExportColumn("equipment", "Código de equipo", width=16),
    ExportColumn("serial", "Serial", width=16),
    ExportColumn("equipment_type", "Tipo de equipo", width=15),
    ExportColumn("category", "Categoría", width=15),
    ExportColumn("status", "Estado", width=14, align="center", pill=True),
    ExportColumn("priority", "Prioridad", width=11, align="center"),
    ExportColumn("requested_by", "Solicitante", width=20),
    ExportColumn("technician", "Técnico", width=20),
    ExportColumn("created_at", "Creado", "date", width=12),
    ExportColumn("resolved_at", "Resuelto", "date", width=12),
    ExportColumn(
        "resolution_hours", "Tiempo de resolución (h)", "number", width=13, total="avg"
    ),
    ExportColumn("sla_met", "SLA cumplido", "bool", width=10, total="share_true"),
    ExportColumn("labor_cost", "Mano de obra", "money", width=14, total="sum"),
    ExportColumn("parts_cost", "Repuestos", "money", width=14, total="sum"),
    ExportColumn("total_cost", "Costo total", "money", width=14, total="sum"),
)
#: What the printed report needs and nothing else: no ids, no free text (title), no
#: columns that repeat what the equipment code already says (type, serial) and no costs,
#: which are empty for most tickets. Excel keeps every column.
PDF_DEFAULT = (
    "ticket_number",
    "equipment",
    "priority",
    "status",
    "technician",
    "created_at",
    "resolved_at",
    "resolution_hours",
    "sla_met",
)


def _label(mapping: dict[str, str], code: str) -> str:
    return mapping.get(code, code)


def _hours(row: dict[str, Any]) -> float | None:
    created, resolved = row["created_at"], row["resolved_at"]
    if resolved is None:
        return None
    seconds: float = (resolved - created).total_seconds()
    return round(max(seconds, 0) / 3600, 1)


def prepare(raw: dict[str, Any]) -> dict[str, Any]:
    """A database row with the derived columns and Spanish labels."""
    row = dict(raw)
    hours = _hours(row)
    sla = row.get("sla_hours")
    row["resolution_hours"] = hours
    row["sla_met"] = None if hours is None or sla is None else hours <= sla
    labor = Decimal(row.get("labor_cost") or 0)
    parts = Decimal(row.get("parts_cost") or 0)
    row["labor_cost"], row["parts_cost"], row["total_cost"] = (
        labor,
        parts,
        labor + parts,
    )
    row["status_code"] = row["status"]
    row["status"] = _label(STATUS_LABELS, row["status"])
    row["priority"] = row.get("priority") or _label(
        PRIORITY_LABELS, row["priority_code"]
    )
    row["category"] = row.get("category") or row.get("category_code") or NO_CATEGORY
    return row


def _money(value: Decimal | float) -> str:
    return format_value(Decimal(str(value)), "money")


def _count_lines(
    counter: Counter[str], order: list[str] | None = None
) -> list[SummaryLine]:
    keys = [k for k in (order or []) if k in counter] + [
        k for k in sorted(counter) if k not in (order or [])
    ]
    return [SummaryLine(key, counter[key], str(counter[key])) for key in keys]


def describe_period(filters: ExportFilters) -> str:
    start, end = filters.date_from, filters.date_to
    if start and end:
        return (
            f"{local(start).strftime(DATE_FORMAT)} – {local(end).strftime(DATE_FORMAT)}"
        )
    if start:
        return f"Desde {local(start).strftime(DATE_FORMAT)}"
    if end:
        return f"Hasta {local(end).strftime(DATE_FORMAT)}"
    return "Todo el historial"


def describe_filters(filters: ExportFilters) -> str:
    parts = []
    if filters.statuses:
        parts.append(
            "Estado: " + ", ".join(_label(STATUS_LABELS, s) for s in filters.statuses)
        )
    if filters.priorities:
        parts.append(
            "Prioridad: "
            + ", ".join(_label(PRIORITY_LABELS, p) for p in filters.priorities)
        )
    if filters.categories:
        parts.append("Categoría: " + ", ".join(filters.categories))
    if filters.technician_ids:
        parts.append(f"Técnicos: {len(filters.technician_ids)}")
    return " · ".join(parts) or "Sin filtros"


class TicketsExport(ExportDefinition):
    key = "tickets"
    permission = "tickets:exportar"
    title = "Reporte de tickets"
    columns = COLUMNS
    pdf_default = PDF_DEFAULT

    async def count(
        self, repo: ExportRepository, filters: ExportFilters, scope: Scope
    ) -> int:
        return await repo.count_tickets(
            filters,
            requester_id=scope.requester_id,
            technician_id=scope.technician_id,
        )

    async def rows(
        self,
        repo: ExportRepository,
        filters: ExportFilters,
        scope: Scope,
        limit: int,
    ) -> list[dict[str, Any]]:
        return await repo.export_tickets(
            filters,
            requester_id=scope.requester_id,
            technician_id=scope.technician_id,
            limit=limit,
        )

    def build(self, rows: list[dict[str, Any]], context: ExportContext) -> ReportExport:
        data = [prepare(row) for row in rows]
        meta = meta_items(
            code=report_code("TICK", context.generated_at),
            generated_by=context.generated_by,
            generated_at=context.generated_at,
            records=len(data),
            period=describe_period(context.filters),
            filters=describe_filters(context.filters),
        )
        return ReportExport(
            key=self.key,
            title=self.title.upper(),
            section="Desglose de tickets",
            columns=self.columns,
            rows=data,
            sheet_name="Detalle",
            subtitle="Gestión de equipos tecnológicos",
            meta_left=meta[0],
            meta_right=meta[1],
            summary=self._summary(data),
            extra_sheets=[self._by_technician(data)],
        )

    @staticmethod
    def _summary(data: list[dict[str, Any]]) -> list[SummaryGroup]:
        by_status = Counter(row["status"] for row in data)
        by_priority = Counter(row["priority"] for row in data)
        by_category = Counter(row["category"] for row in data)
        hours = [
            r["resolution_hours"] for r in data if r["resolution_hours"] is not None
        ]
        measurable = [r for r in data if r["sla_met"] is not None]
        met = sum(1 for r in measurable if r["sla_met"])
        cost = sum((r["total_cost"] for r in data), Decimal(0))
        open_count = sum(1 for r in data if r["status_code"] in OPEN_STATUSES)
        done = sum(1 for r in data if r["status_code"] in DONE_STATUSES)
        mean_hours = round(sum(hours) / len(hours), 1) if hours else None
        sla_pct = round(met / len(measurable) * 100, 1) if measurable else None
        totals = [
            SummaryLine(
                "Total de tickets", len(data), str(len(data)), "Registros del reporte"
            ),
            SummaryLine(
                "Abiertos", open_count, str(open_count), "En espera de atención", "warn"
            ),
            SummaryLine("Resueltos o cerrados", done, str(done), "Finalizados", "good"),
            SummaryLine(
                "Tiempo medio de resolución (h)",
                mean_hours,
                format_value(mean_hours, "number") if mean_hours is not None else "N/A",
                "Horas hasta resolver",
            ),
            SummaryLine(
                "Cumplimiento de SLA (%)",
                sla_pct,
                f"{format_value(sla_pct, 'number')} %"
                if sla_pct is not None
                else "N/A",
                "Dentro del tiempo acordado",
                "good",
            ),
            SummaryLine(
                "Costo total", float(cost), _money(cost), "Mano de obra y repuestos"
            ),
        ]
        return [
            SummaryGroup(
                "Por estado",
                _count_lines(by_status, list(STATUS_LABELS.values())),
                chart="bar",
            ),
            SummaryGroup(
                "Por prioridad",
                _count_lines(by_priority, list(PRIORITY_LABELS.values())),
                chart="pie",
            ),
            SummaryGroup("Por categoría", _count_lines(by_category)),
            SummaryGroup("Indicadores", totals, kpi=True),
        ]

    @staticmethod
    def _by_technician(data: list[dict[str, Any]]) -> ExtraSheet:
        groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for row in data:
            groups[row["technician"] or NO_TECHNICIAN].append(row)
        rows = []
        for name in sorted(groups, key=lambda n: (n == NO_TECHNICIAN, n)):
            items = groups[name]
            hours = [
                r["resolution_hours"]
                for r in items
                if r["resolution_hours"] is not None
            ]
            rows.append(
                {
                    "technician": name,
                    "tickets": len(items),
                    "resolved": sum(
                        1 for r in items if r["status_code"] in DONE_STATUSES
                    ),
                    "mean_hours": round(sum(hours) / len(hours), 1) if hours else None,
                    "total_cost": sum((r["total_cost"] for r in items), Decimal(0)),
                }
            )
        return ExtraSheet(
            name="Por técnico",
            title="TICKETS POR TÉCNICO",
            columns=[
                ExportColumn("technician", "Técnico", width=28),
                ExportColumn("tickets", "Tickets", "int", width=12, total="sum"),
                ExportColumn(
                    "resolved", "Resueltos o cerrados", "int", width=18, total="sum"
                ),
                ExportColumn("mean_hours", "Tiempo medio (h)", "number", width=16),
                ExportColumn(
                    "total_cost", "Costo total", "money", width=16, total="sum"
                ),
            ],
            rows=rows,
        )
