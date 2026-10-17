"""Technician roster export: who they are, whether they can take work, how much they hold
and the hourly rate. Only admins and supervisors may export it (rates are not for everyone)."""

from collections import Counter
from decimal import Decimal
from typing import Any

from app.core.exceptions import ForbiddenError
from app.exports.base import ExportContext, ExportDefinition, Scope
from app.exports.formatting import format_value
from app.exports.meta import meta_items, report_code
from app.exports.model import (
    ExportColumn,
    ReportExport,
    SummaryGroup,
    SummaryLine,
)
from app.repositories.export import ExportRepository
from app.schemas.export import ExportFilters

ACTIVE = "Activo"
INACTIVE = "Inactivo"
AVAILABLE = "Disponible"
UNAVAILABLE = "No disponible"
NO_SPECIALTY = "Sin especialidad"
LOAD_LABELS = {"none": "Sin tickets", "low": "1 a 2 tickets", "high": "3 o más tickets"}

COLUMNS = (
    ExportColumn("full_name", "Técnico", width=26, total="count"),
    ExportColumn("employee_code", "Código", width=12),
    ExportColumn("email", "Correo", width=30),
    ExportColumn("specialization", "Especialidad", width=24),
    ExportColumn("status", "Estado", width=11, align="center", pill=True),
    ExportColumn("availability", "Disponibilidad", width=15, align="center", pill=True),
    ExportColumn("open_tickets", "Tickets abiertos", "int", width=14, total="sum"),
    ExportColumn("resolved", "Tickets resueltos", "int", width=14, total="sum"),
    ExportColumn("hourly_rate", "Tarifa por hora", "money", width=15, total="avg"),
    ExportColumn("created_at", "Alta", "date", width=12),
)
#: The printed roster: no e-mail or registration date, which add width and little else.
PDF_DEFAULT = (
    "full_name",
    "employee_code",
    "specialization",
    "status",
    "availability",
    "open_tickets",
    "resolved",
    "hourly_rate",
)


def prepare(raw: dict[str, Any]) -> dict[str, Any]:
    """A database row with Spanish labels."""
    row = dict(raw)
    row["status"] = ACTIVE if row["is_active"] else INACTIVE
    row["availability"] = AVAILABLE if row["is_available"] else UNAVAILABLE
    row["specialization"] = row.get("specialization") or None
    return row


def _load_bucket(open_tickets: int) -> str:
    if open_tickets == 0:
        return LOAD_LABELS["none"]
    return LOAD_LABELS["low"] if open_tickets <= 2 else LOAD_LABELS["high"]


def describe_filters(filters: ExportFilters) -> str:
    parts = []
    if filters.search:
        parts.append(f"Búsqueda: {filters.search}")
    if filters.is_active is not None:
        parts.append("Estado: " + (ACTIVE if filters.is_active else INACTIVE))
    if filters.specialty:
        parts.append(f"Especialidad: {filters.specialty}")
    if filters.is_available is not None:
        parts.append(
            "Disponibilidad: " + (AVAILABLE if filters.is_available else UNAVAILABLE)
        )
    if filters.load:
        parts.append("Carga: " + LOAD_LABELS[filters.load])
    return " · ".join(parts) or "Sin filtros"


def _counts(counter: Counter[str], order: list[str]) -> list[SummaryLine]:
    keys = [k for k in order if k in counter]
    return [SummaryLine(key, counter[key], str(counter[key])) for key in keys]


class TechniciansExport(ExportDefinition):
    key = "technicians"
    title = "Técnicos"
    columns = COLUMNS
    pdf_default = PDF_DEFAULT

    @staticmethod
    def _only_elevated(scope: Scope) -> None:
        if scope.requester_id is not None or scope.technician_id is not None:
            raise ForbiddenError(
                "only administrators and supervisors can export technicians"
            )

    async def count(
        self, repo: ExportRepository, filters: ExportFilters, scope: Scope
    ) -> int:
        self._only_elevated(scope)
        return await repo.count_technicians(filters)

    async def rows(
        self,
        repo: ExportRepository,
        filters: ExportFilters,
        scope: Scope,
        limit: int,
    ) -> list[dict[str, Any]]:
        self._only_elevated(scope)
        return await repo.export_technicians(filters, limit=limit)

    def build(self, rows: list[dict[str, Any]], context: ExportContext) -> ReportExport:
        data = [prepare(row) for row in rows]
        meta = meta_items(
            code=report_code("TEC", context.generated_at),
            generated_by=context.generated_by,
            generated_at=context.generated_at,
            records=len(data),
            period="Todos los perfiles",
            filters=describe_filters(context.filters),
        )
        return ReportExport(
            key=self.key,
            title=self.title.upper(),
            section="Listado de técnicos",
            columns=self.columns,
            rows=data,
            sheet_name="Detalle",
            subtitle="Personal técnico y especialistas",
            meta_left=meta[0],
            meta_right=meta[1],
            summary=self._summary(data),
        )

    @staticmethod
    def _summary(data: list[dict[str, Any]]) -> list[SummaryGroup]:
        availability = Counter(row["availability"] for row in data)
        load = Counter(_load_bucket(int(row["open_tickets"])) for row in data)
        rates = [
            Decimal(row["hourly_rate"])
            for row in data
            if row["hourly_rate"] is not None
        ]
        mean_rate = sum(rates, Decimal(0)) / len(rates) if rates else None
        open_total = sum(int(row["open_tickets"]) for row in data)
        resolved_total = sum(int(row["resolved"]) for row in data)
        free = sum(1 for row in data if row["is_available"])
        totals = [
            SummaryLine(
                "Total de técnicos", len(data), str(len(data)), "Perfiles del reporte"
            ),
            SummaryLine(
                "Disponibles", free, str(free), "Abiertos a nuevo trabajo", "good"
            ),
            SummaryLine(
                "Tickets abiertos",
                open_total,
                str(open_total),
                "En manos del equipo",
                "warn",
            ),
            SummaryLine(
                "Tickets resueltos",
                resolved_total,
                str(resolved_total),
                "Cerrados por el equipo",
                "good",
            ),
            SummaryLine(
                "Tarifa media por hora",
                float(mean_rate) if mean_rate is not None else None,
                format_value(mean_rate, "money") if mean_rate is not None else "N/A",
                "Promedio de los perfiles",
            ),
        ]
        return [
            SummaryGroup(
                "Por disponibilidad",
                _counts(availability, [AVAILABLE, UNAVAILABLE]),
                chart="pie",
            ),
            SummaryGroup(
                "Por carga de tickets",
                _counts(load, list(LOAD_LABELS.values())),
                chart="bar",
            ),
            SummaryGroup("Indicadores", totals, kpi=True),
        ]
