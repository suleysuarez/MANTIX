import asyncio
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from app.core.authz import AuthContext
from app.core.exceptions import UnprocessableError
from app.exports.generic import build_generic_export
from app.exports.pdf import render_pdf
from app.exports.xlsx import render_xlsx
from app.repositories.base import Page
from app.repositories.report import MAX_EXPORT_ROWS
from app.repositories.report_builder import ReportBuilderRepository, RunRow
from app.schemas.dashboard import Period
from app.schemas.report_builder import (
    MAX_RANGE_DAYS,
    CatalogResponse,
    Comparison,
    ExportFormat,
    FilterDefinition,
    FilterOption,
    LastExport,
    PreviewColumn,
    ReportDefinitionResponse,
    ReportFilters,
    ReportGenerateRequest,
    ReportPreview,
    ReportPreviewRequest,
    ReportRunResponse,
    ReportsOverview,
    UsedReport,
)
from app.services.audit import AuditService
from app.services.dashboard_kpis import (
    MIN_SAMPLE,
    DashboardKpiService,
    change_pct,
    period_window,
    previous_window,
)
from app.services.exporters import Column, ReportTable, cell_text, get_exporter
from app.services.report import ExportedFile

PREVIEW_ROWS = 15

TICKET_STATUSES = {
    "submitted": "Enviado",
    "triaged": "Clasificado",
    "assigned": "Asignado",
    "in_progress": "En curso",
    "waiting": "En espera",
    "resolved": "Resuelto",
    "closed": "Cerrado",
    "cancelled": "Cancelado",
}
PRIORITIES = {"critical": "Crítica", "high": "Alta", "medium": "Media", "low": "Baja"}
EQUIPMENT_STATUSES = {
    "in_storage": "En almacén",
    "assigned": "Asignado",
    "in_repair": "En mantenimiento",
    "lost": "Extraviado",
    "retired": "Retirado",
    "disposed": "Dado de baja",
}
PLAN_STATUSES = {
    "overdue": "Vencido",
    "scheduled": "Programado",
    "inactive": "Inactivo",
}
ITEM_STATUSES = {
    "ok": "En stock",
    "low": "Bajo mínimo",
    "out": "Agotado",
    "inactive": "Inactivo",
}
CATEGORIES = {
    "spare_part": "Repuesto",
    "consumable": "Consumible",
    "accessory": "Accesorio",
    "tool": "Herramienta",
    "other": "Otro",
}
KINDS = {"in": "Entrada", "out": "Consumo", "adjust": "Ajuste"}
SUMMARY_DAYS = (7, 30, 90, 365)

#: Label maps applied to the coded columns of each report (by column key).
_LABELS: dict[str, dict[str, dict[str, str]]] = {
    "equipment": {"status": EQUIPMENT_STATUSES},
    "tickets": {"status": TICKET_STATUSES, "priority": PRIORITIES},
    "maintenance_plans": {"status": PLAN_STATUSES},
    "inventory_items": {"status": ITEM_STATUSES, "category": CATEGORIES},
    "inventory_movements": {"kind": KINDS},
}


def _options(values: dict[str, str]) -> list[FilterOption]:
    return [FilterOption(value=k, label=v) for k, v in values.items()]


@dataclass(frozen=True, slots=True)
class Dataset:
    key: str
    title: str
    description: str
    icon: str
    columns: tuple[Column, ...]
    #: Filter fields the report accepts, and the allowed values of the coded ones.
    allowed: frozenset[str]
    values: dict[str, frozenset[str]]
    supports_compare: bool = False


DATASETS: dict[str, Dataset] = {
    d.key: d
    for d in (
        Dataset(
            "equipment",
            "Inventario de equipos",
            "Cada equipo con su estado, ubicación, responsable, compra y garantía.",
            "desktop_windows",
            (
                Column("asset_tag", "Código de activo", 16),
                Column("serial_number", "Serie", 18),
                Column("equipment_type", "Tipo", 14),
                Column("brand", "Marca", 14),
                Column("model", "Modelo", 18),
                Column("status", "Estado", 16),
                Column("location", "Ubicación", 18),
                Column("custodian", "Responsable", 20),
                Column("purchase_date", "Fecha de compra", 14),
                Column("purchase_cost", "Costo de compra", 14),
                Column("warranty_end_date", "Fin de garantía", 14),
            ),
            frozenset({"statuses", "equipment_type_ids"}),
            {"statuses": frozenset(EQUIPMENT_STATUSES)},
        ),
        Dataset(
            "tickets",
            "Tickets de mantenimiento",
            "Solicitudes con prioridad, estado, técnico y tiempo de resolución.",
            "confirmation_number",
            (
                Column("ticket_number", "Ticket", 16),
                Column("title", "Título", 34),
                Column("priority", "Prioridad", 11),
                Column("status", "Estado", 13),
                Column("asset_tag", "Equipo", 14),
                Column("requested_by", "Solicitante", 20),
                Column("technician", "Técnico", 20),
                Column("created_at", "Creado", 17),
                Column("resolved_at", "Resuelto", 17),
                Column("closed_at", "Cerrado", 17),
                Column("hours_to_resolve", "Horas a resolver", 13),
            ),
            frozenset({"statuses", "priorities", "date_from", "date_to"}),
            {"statuses": frozenset(TICKET_STATUSES)},
            supports_compare=True,
        ),
        Dataset(
            "summary",
            "Resumen operativo",
            "Métricas del dashboard en una tabla imprimible: tickets, equipos y resolución.",
            "monitoring",
            (
                Column("section", "Sección", 24),
                Column("metric", "Métrica", 32),
                Column("value", "Valor", 16),
            ),
            frozenset({"days"}),
            {},
        ),
        Dataset(
            "maintenance_plans",
            "Planes de mantenimiento",
            "Planes preventivos con su próxima fecha, último servicio y cuántas veces se hicieron.",
            "event_repeat",
            (
                Column("title", "Plan", 30),
                Column("asset_tag", "Equipo", 14),
                Column("technician", "Técnico", 20),
                Column("interval_days", "Cada (días)", 12),
                Column("estimated_hours", "Horas estimadas", 14),
                Column("next_due_at", "Próximo servicio", 17),
                Column("status", "Estado", 13),
                Column("last_done", "Último servicio", 17),
                Column("runs", "Servicios hechos", 14),
            ),
            frozenset({"statuses", "date_from", "date_to"}),
            {"statuses": frozenset(PLAN_STATUSES)},
            supports_compare=True,
        ),
        Dataset(
            "inventory_items",
            "Existencias del inventario",
            "Ítems con stock, mínimos, valor y proveedor.",
            "inventory_2",
            (
                Column("sku", "SKU", 14),
                Column("name", "Nombre", 30),
                Column("category", "Categoría", 13),
                Column("unit", "Unidad", 10),
                Column("unit_cost", "Costo unitario", 14),
                Column("stock", "Stock", 8),
                Column("min_stock", "Mínimo", 8),
                Column("max_stock", "Máximo", 8),
                Column("stock_value", "Valor", 14),
                Column("status", "Estado", 13),
                Column("location", "Ubicación", 16),
                Column("supplier", "Proveedor", 20),
            ),
            frozenset({"categories", "statuses"}),
            {"categories": frozenset(CATEGORIES), "statuses": frozenset(ITEM_STATUSES)},
        ),
        Dataset(
            "inventory_movements",
            "Movimientos de inventario",
            "Entradas, consumos y ajustes de stock con quién los registró.",
            "swap_vert",
            (
                Column("created_at", "Fecha", 17),
                Column("sku", "SKU", 14),
                Column("name", "Ítem", 30),
                Column("kind", "Tipo", 11),
                Column("quantity", "Cantidad", 10),
                Column("stock_after", "Stock resultante", 14),
                Column("registered_by", "Registrado por", 20),
                Column("notes", "Nota", 30),
            ),
            frozenset({"kinds", "date_from", "date_to"}),
            {"kinds": frozenset(KINDS)},
            supports_compare=True,
        ),
    )
}

#: Which `ReportFilters` fields are really one filter in the catalog (dates are a pair).
_CATALOG_FIELD = {"date_from": "dates", "date_to": "dates"}


def _human(report: str, filters: ReportFilters) -> str:
    """Filter summary printed under the title of a PDF or sheet."""
    labels = _LABELS.get(report, {})
    parts: list[str] = []

    def values(name: str, mapping: dict[str, str] | None, title: str) -> None:
        chosen = getattr(filters, name)
        if chosen:
            parts.append(
                f"{title}: "
                + ", ".join((mapping or {}).get(str(v), str(v)) for v in chosen)
            )

    values("statuses", labels.get("status"), "Estados")
    values("priorities", PRIORITIES, "Prioridades")
    values("categories", CATEGORIES, "Categorías")
    values("kinds", KINDS, "Tipos")
    if filters.equipment_type_ids:
        parts.append(
            f"Tipos de equipo: {len(filters.equipment_type_ids)} seleccionados"
        )
    if filters.date_from or filters.date_to:
        start = f"{filters.date_from:%Y-%m-%d}" if filters.date_from else "…"
        end = f"{filters.date_to:%Y-%m-%d}" if filters.date_to else "…"
        parts.append(f"Fechas: {start} a {end}")
    if filters.days:
        parts.append(f"Últimos {filters.days} días")
    return " · ".join(parts) or "Sin filtros"


def _period(filters: ReportFilters) -> str:
    """The date range of a report as shown in its metadata block."""
    if filters.date_from or filters.date_to:
        start = f"{filters.date_from:%d/%m/%Y}" if filters.date_from else "…"
        end = f"{filters.date_to:%d/%m/%Y}" if filters.date_to else "…"
        return f"{start} – {end}"
    return f"Últimos {filters.days} días" if filters.days else "Todo el historial"


class ReportBuilderService:
    """Report gallery: catalog, filtered preview with comparison, export and activity."""

    def __init__(
        self,
        repository: ReportBuilderRepository,
        dashboard: DashboardKpiService,
        audit: AuditService,
    ):
        self.repository = repository
        self.dashboard = dashboard
        self.audit = audit

    # -- catalog -----------------------------------------------------------------------------

    async def catalog(self) -> CatalogResponse:
        types = [
            FilterOption(value=str(i), label=name)
            for i, name in await self.repository.equipment_type_options()
        ]
        filters: dict[str, list[FilterDefinition]] = {
            "equipment": [
                FilterDefinition(
                    key="statuses",
                    label="Estado",
                    kind="multiselect",
                    options=_options(EQUIPMENT_STATUSES),
                ),
                FilterDefinition(
                    key="equipment_type_ids",
                    label="Tipo de equipo",
                    kind="multiselect",
                    options=types,
                ),
            ],
            "tickets": [
                FilterDefinition(
                    key="statuses",
                    label="Estado",
                    kind="multiselect",
                    options=_options(TICKET_STATUSES),
                ),
                FilterDefinition(
                    key="priorities",
                    label="Prioridad",
                    kind="multiselect",
                    options=_options(PRIORITIES),
                ),
                FilterDefinition(key="dates", label="Creados entre", kind="dates"),
            ],
            "summary": [
                FilterDefinition(
                    key="days",
                    label="Periodo",
                    kind="days",
                    options=[
                        FilterOption(value=str(d), label=f"Últimos {d} días")
                        for d in SUMMARY_DAYS
                    ],
                )
            ],
            "maintenance_plans": [
                FilterDefinition(
                    key="statuses",
                    label="Estado",
                    kind="multiselect",
                    options=_options(PLAN_STATUSES),
                ),
                FilterDefinition(
                    key="dates", label="Próximo servicio entre", kind="dates"
                ),
            ],
            "inventory_items": [
                FilterDefinition(
                    key="categories",
                    label="Categoría",
                    kind="multiselect",
                    options=_options(CATEGORIES),
                ),
                FilterDefinition(
                    key="statuses",
                    label="Estado",
                    kind="multiselect",
                    options=_options(ITEM_STATUSES),
                ),
            ],
            "inventory_movements": [
                FilterDefinition(
                    key="kinds",
                    label="Tipo de movimiento",
                    kind="multiselect",
                    options=_options(KINDS),
                ),
                FilterDefinition(key="dates", label="Registrados entre", kind="dates"),
            ],
        }
        return CatalogResponse(
            reports=[
                ReportDefinitionResponse(
                    key=d.key,  # type: ignore[arg-type]
                    title=d.title,
                    description=d.description,
                    icon=d.icon,
                    filters=filters[d.key],
                    supports_compare=d.supports_compare,
                )
                for d in DATASETS.values()
            ],
            max_rows=MAX_EXPORT_ROWS,
            max_range_days=MAX_RANGE_DAYS,
            formats=["xlsx", "pdf", "csv"],
        )

    # -- preview and export ----------------------------------------------------------------------

    async def preview(
        self,
        actor: AuthContext,
        request: ReportPreviewRequest,
        *,
        now: datetime | None = None,
    ) -> ReportPreview:
        now = now or datetime.now(UTC)
        dataset = self._validate(request.report, request.filters)
        rows = await self._rows(actor, dataset, request.filters, now)
        comparison = None
        if request.compare:
            comparison = await self._compare(
                actor, dataset, request.filters, len(rows), now
            )
        shown = rows[:PREVIEW_ROWS]
        return ReportPreview(
            report=dataset.key,  # type: ignore[arg-type]
            title=dataset.title,
            columns=[
                PreviewColumn(key=c.key, header=c.header) for c in dataset.columns
            ],
            rows=[
                {c.key: cell_text(row.get(c.key)) for c in dataset.columns}
                for row in shown
            ],
            total_rows=min(len(rows), MAX_EXPORT_ROWS),
            truncated=len(rows) > MAX_EXPORT_ROWS,
            comparison=comparison,
        )

    async def generate(
        self,
        actor: AuthContext,
        request: ReportGenerateRequest,
        *,
        now: datetime | None = None,
    ) -> ExportedFile:
        now = now or datetime.now(UTC)
        exporter = get_exporter(
            request.export_format
        )  # unknown format fails before querying
        dataset = self._validate(request.report, request.filters)
        rows = await self._rows(actor, dataset, request.filters, now)
        if len(rows) > MAX_EXPORT_ROWS:
            raise UnprocessableError(
                f"the report has more than {MAX_EXPORT_ROWS} rows; narrow the filters"
            )
        if request.export_format == "csv":
            table = ReportTable(
                dataset.title,
                dataset.columns,
                rows,
                subtitle=_human(dataset.key, request.filters),
            )
            content = exporter.render(table)
        else:
            # PDF and Excel share the Mantix document layout used by every report.
            document = build_generic_export(
                key=dataset.key,
                title=dataset.title,
                dataset_columns=dataset.columns,
                rows=rows,
                generated_by=actor.user.full_name,
                generated_at=now,
                filters=_human(dataset.key, request.filters),
                period=_period(request.filters),
            )
            render = render_pdf if request.export_format == "pdf" else render_xlsx
            content = await asyncio.to_thread(render, document, generated_at=now)
        filters = request.filters.model_dump(mode="json", exclude_none=True)
        run = self.repository.record_run(
            report_key=dataset.key,
            export_format=request.export_format,
            filters=filters,
            row_count=len(rows),
            user_id=actor.id,
        )
        await self.repository.flush()
        self.audit.record(
            user_id=actor.id,
            action="report.generated",
            entity_type="report_run",
            entity_id=run.id,
            new_values={
                "report": dataset.key,
                "format": request.export_format,
                "rows": len(rows),
            },
        )
        await self.repository.commit()
        return ExportedFile(
            content=content,
            filename=f"{dataset.key}-{now:%Y%m%d-%H%M}.{exporter.extension}",
            media_type=exporter.media_type,
        )

    # -- activity --------------------------------------------------------------------------------

    async def overview(
        self, *, period: Period, now: datetime | None = None
    ) -> ReportsOverview:
        now = now or datetime.now(UTC)
        start, end = period_window(period, now)
        prev_start, prev_end = previous_window(period, start, end)
        repo = self.repository
        generated = await repo.runs_in(start, end)
        previous = await repo.runs_in(prev_start, prev_end)
        last = await repo.last_run()
        return ReportsOverview(
            generated_at=now,
            period=period,
            window_start=start,
            window_end=end,
            generated=generated,
            previous=previous,
            change_pct=change_pct(float(generated), float(previous)),
            low_sample=0 < generated < MIN_SAMPLE,
            most_used=[
                UsedReport(report=key, title=self._title(key), count=count)  # type: ignore[arg-type]
                for key, count in await repo.most_used(start, end, limit=5)
            ],
            by_format=await repo.by_format(start, end),
            last_export=self._last(last),
            people=await repo.people_in(start, end),
        )

    async def history(self, *, page: int, size: int) -> Page[ReportRunResponse]:
        rows = await self.repository.recent_runs(limit=size, offset=(page - 1) * size)
        total = await self.repository.count_runs()
        return Page(
            items=[self._run(row) for row in rows], total=total, page=page, size=size
        )

    # -- internals -------------------------------------------------------------------------------

    @staticmethod
    def _title(key: str) -> str:
        dataset = DATASETS.get(key)
        return dataset.title if dataset else key

    def _last(self, run: RunRow | None) -> LastExport | None:
        if run is None:
            return None
        return LastExport(
            report=run.report_key,  # type: ignore[arg-type]
            title=self._title(run.report_key),
            export_format=run.export_format,  # type: ignore[arg-type]
            row_count=run.row_count,
            by=run.by,
            at=run.at,
        )

    def _run(self, run: RunRow) -> ReportRunResponse:
        return ReportRunResponse(
            id=run.id,
            report=run.report_key,  # type: ignore[arg-type]
            title=self._title(run.report_key),
            export_format=run.export_format,  # type: ignore[arg-type]
            row_count=run.row_count,
            filters=run.filters,
            by=run.by,
            at=run.at,
        )

    @staticmethod
    def _validate(report: str, filters: ReportFilters) -> Dataset:
        """Reject filters the report does not take and values it does not know."""
        dataset = DATASETS[report]
        supplied = {
            name
            for name in filters.model_fields_set
            if getattr(filters, name) is not None
        }
        unsupported = supplied - dataset.allowed
        if unsupported:
            raise UnprocessableError(
                f"report '{report}' does not accept: " + ", ".join(sorted(unsupported))
            )
        for name, allowed in dataset.values.items():
            unknown = [v for v in (getattr(filters, name) or []) if v not in allowed]
            if unknown:
                raise UnprocessableError(
                    f"unknown {name} for '{report}': {', '.join(map(str, unknown))}"
                )
        if (
            dataset.key == "summary"
            and filters.days is not None
            and filters.days not in SUMMARY_DAYS
        ):
            raise UnprocessableError(
                f"days must be one of {', '.join(map(str, SUMMARY_DAYS))}"
            )
        return dataset

    async def _compare(
        self,
        actor: AuthContext,
        dataset: Dataset,
        filters: ReportFilters,
        current: int,
        now: datetime,
    ) -> Comparison:
        if not dataset.supports_compare:
            raise UnprocessableError(
                f"report '{dataset.key}' cannot be compared between periods"
            )
        if filters.date_from is None or filters.date_to is None:
            raise UnprocessableError("comparing needs both date_from and date_to")
        span = filters.date_to - filters.date_from
        previous_to = filters.date_from - timedelta(microseconds=1)
        previous_from = previous_to - span
        previous = filters.model_copy(
            update={"date_from": previous_from, "date_to": previous_to}
        )
        before = len(await self._rows(actor, dataset, previous, now))
        return Comparison(
            current_total=min(current, MAX_EXPORT_ROWS),
            previous_total=min(before, MAX_EXPORT_ROWS),
            change_pct=change_pct(float(current), float(before)),
            previous_from=previous_from,
            previous_to=previous_to,
        )

    async def _rows(
        self,
        actor: AuthContext,
        dataset: Dataset,
        filters: ReportFilters,
        now: datetime,
    ) -> list[dict[str, Any]]:
        """Rows with coded values already translated, capped one above the export limit."""
        limit = MAX_EXPORT_ROWS + 1
        repo = self.repository
        raw: list[dict[str, Any]]
        match dataset.key:
            case "equipment":
                raw = await repo.equipment_rows(
                    statuses=filters.statuses,
                    equipment_type_ids=filters.equipment_type_ids,
                    limit=limit,
                )
            case "tickets":
                raw = await repo.ticket_rows(
                    statuses=filters.statuses,
                    priorities=filters.priorities,
                    date_from=filters.date_from,
                    date_to=filters.date_to,
                    limit=limit,
                )
            case "summary":
                raw = await self._summary_rows(actor, filters.days or 30)
            case "maintenance_plans":
                raw = await repo.plan_rows(
                    statuses=filters.statuses,
                    date_from=filters.date_from,
                    date_to=filters.date_to,
                    now=now,
                    limit=limit,
                )
            case "inventory_items":
                raw = await repo.item_rows(
                    categories=filters.categories,
                    statuses=filters.statuses,
                    limit=limit,
                )
            case _:
                raw = await repo.movement_rows(
                    kinds=filters.kinds,
                    date_from=filters.date_from,
                    date_to=filters.date_to,
                    limit=limit,
                )
        labels = _LABELS.get(dataset.key, {})
        translate: Callable[[str, Any], Any] = lambda key, value: (
            labels[key].get(value, value)
            if key in labels and isinstance(value, str)
            else value
        )
        return [
            {key: translate(key, value) for key, value in row.items()} for row in raw
        ]

    async def _summary_rows(
        self, actor: AuthContext, days: int
    ) -> list[dict[str, Any]]:
        summary = await self.dashboard.summary(actor, days=days)
        resolution = await self.dashboard.resolution_times(actor, days=days)
        top = await self.dashboard.top_failing_equipment(days=days, limit=10)
        rows: list[dict[str, Any]] = []

        def add(section: str, metric: str, value: object) -> None:
            rows.append({"section": section, "metric": metric, "value": value})

        add("Tickets", "Total", summary.tickets.total)
        add("Tickets", "Abiertos", summary.tickets.open)
        add("Tickets", "Vencidos (fuera de SLA)", summary.tickets.overdue)
        for item in summary.tickets.by_status:
            add(
                "Tickets por estado",
                TICKET_STATUSES.get(item.key, item.key),
                item.count,
            )
        for item in summary.tickets.open_by_priority:
            add(
                "Abiertos por prioridad", PRIORITIES.get(item.key, item.key), item.count
            )
        for item in summary.equipment_by_status:
            add(
                "Equipos por estado",
                EQUIPMENT_STATUSES.get(item.key, item.key),
                item.count,
            )
        add("Resolución", "Tickets resueltos", resolution.overall.resolved_count)
        add("Resolución", "Horas (media)", resolution.overall.avg_hours)
        add("Resolución", "Horas (mediana)", resolution.overall.median_hours)
        for timing in resolution.by_priority:
            add(
                "Horas medias por prioridad",
                PRIORITIES.get(timing.priority or "", "-"),
                timing.avg_hours,
            )
        for equipment in top.equipment:
            add("Equipos con más tickets", equipment.asset_tag, equipment.tickets)
        return rows


def supported_export_formats() -> list[ExportFormat]:
    return ["xlsx", "pdf", "csv"]
