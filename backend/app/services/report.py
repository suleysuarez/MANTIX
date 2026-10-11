from dataclasses import dataclass
from datetime import UTC, datetime

from app.core.authz import AuthContext
from app.repositories.report import ReportRepository
from app.services.dashboard import DashboardService
from app.services.exporters import Column, ReportTable, get_exporter

EQUIPMENT_COLUMNS = (
    Column("asset_tag", "Asset tag", 14),
    Column("serial_number", "Serial number", 18),
    Column("equipment_type", "Equipment type", 16),
    Column("brand", "Brand", 14),
    Column("model", "Model", 18),
    Column("status", "Status", 12),
    Column("location", "Location", 18),
    Column("custodian", "Custodian", 20),
    Column("purchase_date", "Purchase date", 13),
    Column("purchase_cost", "Purchase cost", 13),
    Column("warranty_end_date", "Warranty end", 13),
)

TICKET_COLUMNS = (
    Column("ticket_number", "Ticket", 15),
    Column("title", "Title", 34),
    Column("priority", "Priority", 10),
    Column("status", "Status", 12),
    Column("asset_tag", "Asset tag", 13),
    Column("requested_by", "Requested by", 20),
    Column("technician", "Technician", 20),
    Column("created_at", "Created", 17),
    Column("resolved_at", "Resolved", 17),
    Column("closed_at", "Closed", 17),
    Column("hours_to_resolve", "Hours to resolve", 12),
)

SUMMARY_COLUMNS = (
    Column("section", "Section", 22),
    Column("metric", "Metric", 30),
    Column("value", "Value", 16),
)


@dataclass(frozen=True, slots=True)
class ExportedFile:
    content: bytes
    filename: str
    media_type: str


class ReportService:
    """Builds report tables from repository read-models and renders them."""

    def __init__(self, repository: ReportRepository, dashboard: DashboardService):
        self.repository = repository
        self.dashboard = dashboard

    @staticmethod
    def _filename(stem: str, extension: str) -> str:
        return f"{stem}-{datetime.now(UTC):%Y%m%d-%H%M}.{extension}"

    def _render(
        self, table: ReportTable, export_format: str, stem: str
    ) -> ExportedFile:
        exporter = get_exporter(export_format)
        return ExportedFile(
            content=exporter.render(table),
            filename=self._filename(stem, exporter.extension),
            media_type=exporter.media_type,
        )

    async def equipment_report(
        self,
        *,
        export_format: str,
        status: str | None = None,
        equipment_type_id: int | None = None,
    ) -> ExportedFile:
        get_exporter(export_format)  # fail on an unknown format before querying
        rows = await self.repository.equipment_rows(
            status=status, equipment_type_id=equipment_type_id
        )
        table = ReportTable("Equipment inventory", EQUIPMENT_COLUMNS, rows)
        return self._render(table, export_format, "equipment")

    async def ticket_report(
        self,
        *,
        export_format: str,
        status: str | None = None,
        priority: str | None = None,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
    ) -> ExportedFile:
        get_exporter(export_format)
        rows = await self.repository.ticket_rows(
            status=status, priority=priority, date_from=date_from, date_to=date_to
        )
        table = ReportTable("Maintenance tickets", TICKET_COLUMNS, rows)
        return self._render(table, export_format, "tickets")

    async def summary_report(
        self, actor: AuthContext, *, export_format: str, days: int
    ) -> ExportedFile:
        get_exporter(export_format)
        summary = await self.dashboard.summary(actor, days=days)
        resolution = await self.dashboard.resolution_times(actor, days=days)
        top = await self.dashboard.top_failing_equipment(days=days, limit=10)
        rows: list[dict] = []

        def add(section: str, metric: str, value: object) -> None:
            rows.append({"section": section, "metric": metric, "value": value})

        add("Tickets", "Total", summary.tickets.total)
        add("Tickets", "Open", summary.tickets.open)
        add("Tickets", "Overdue (past SLA)", summary.tickets.overdue)
        for item in summary.tickets.by_status:
            add("Tickets by status", item.key, item.count)
        for item in summary.tickets.open_by_priority:
            add("Open tickets by priority", item.key, item.count)
        for item in summary.equipment_by_status:
            add("Equipment by status", item.key, item.count)
        add("Resolution", "Resolved tickets", resolution.overall.resolved_count)
        add("Resolution", "Mean hours", resolution.overall.avg_hours)
        add("Resolution", "Median hours", resolution.overall.median_hours)
        for item in resolution.by_priority:
            add("Mean hours by priority", item.priority or "-", item.avg_hours)
        for equipment in top.equipment:
            add("Most tickets", equipment.asset_tag, equipment.tickets)

        table = ReportTable(
            "Maintenance summary",
            SUMMARY_COLUMNS,
            rows,
            subtitle=f"Last {days} days",
        )
        return self._render(table, export_format, "summary")
