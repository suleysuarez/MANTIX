"""PDF and Excel exports of a report with its filters, scoped to what the caller may see."""

import asyncio
from datetime import UTC, datetime

from app.core.authz import AuthContext
from app.core.exceptions import UnprocessableError
from app.exports.base import ExportContext, ExportDefinition, Scope
from app.exports.formatting import local
from app.exports.pdf import render_pdf
from app.exports.tickets import TicketsExport
from app.exports.xlsx import render_xlsx
from app.repositories.export import ExportRepository
from app.repositories.report import MAX_EXPORT_ROWS
from app.schemas.export import (
    DocumentFormat,
    ExportColumnInfo,
    ExportCount,
    ExportFilters,
    ExportOptions,
    ExportRequest,
)
from app.schemas.report_builder import MAX_RANGE_DAYS, ReportKey
from app.services.audit import AuditService
from app.services.report import ExportedFile

#: Above this many rows the file takes noticeably long to build.
WARN_ROWS = 2_000
DEFAULT_COMPANY = "Mantix"
_MEDIA = {
    "pdf": "application/pdf",
    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
}

#: Reports that already have a document export; the rest follow the same pattern.
DEFINITIONS: dict[str, ExportDefinition] = {"tickets": TicketsExport()}


def filename(report: str, extension: str, now: datetime) -> str:
    """`mantix_tickets_2026-10-14.pdf`, dated in display time."""
    return f"mantix_{report}_{local(now):%Y-%m-%d}.{extension}"


class ExportService:
    def __init__(self, repository: ExportRepository, audit: AuditService):
        self.repository = repository
        self.audit = audit

    @staticmethod
    def _definition(report: ReportKey) -> ExportDefinition:
        definition = DEFINITIONS.get(report)
        if definition is None:
            raise UnprocessableError(f"the report '{report}' cannot be exported yet")
        return definition

    def options(self, report: ReportKey) -> ExportOptions:
        definition = self._definition(report)
        pdf_default = set(definition.pdf_default)
        return ExportOptions(
            report=report,
            title=definition.title,
            columns=[
                ExportColumnInfo(
                    key=column.key,
                    label=column.header,
                    kind=column.kind,
                    default_pdf=column.key in pdf_default,
                    default_xlsx=True,
                )
                for column in definition.columns
            ],
            formats=["pdf", "xlsx"],
            max_rows=MAX_EXPORT_ROWS,
            warn_rows=WARN_ROWS,
            max_range_days=MAX_RANGE_DAYS,
        )

    async def _scope(self, actor: AuthContext) -> Scope:
        """Admins and supervisors see everything; a technician their tickets; others their own."""
        if actor.is_elevated:
            return Scope()
        technician_id = await self.repository.technician_id_of(actor.id)
        if technician_id is not None:
            return Scope(technician_id=technician_id)
        return Scope(requester_id=actor.id)

    async def count(
        self, actor: AuthContext, report: ReportKey, filters: ExportFilters
    ) -> ExportCount:
        definition = self._definition(report)
        total = await definition.count(
            self.repository, filters, await self._scope(actor)
        )
        return ExportCount(
            total=total,
            max_rows=MAX_EXPORT_ROWS,
            warn_rows=WARN_ROWS,
            over_limit=total > MAX_EXPORT_ROWS,
            large=WARN_ROWS < total <= MAX_EXPORT_ROWS,
        )

    async def export(
        self,
        actor: AuthContext,
        report: ReportKey,
        export_format: DocumentFormat,
        request: ExportRequest,
        *,
        now: datetime | None = None,
    ) -> ExportedFile:
        now = now or datetime.now(UTC)
        definition = self._definition(report)
        keys = self._columns(definition, export_format, request.columns)
        scope = await self._scope(actor)

        total = await definition.count(self.repository, request.filters, scope)
        if total == 0:
            raise UnprocessableError("no records match the filters; nothing to export")
        if total > MAX_EXPORT_ROWS:
            raise UnprocessableError(
                f"the export has {total} records and the limit is {MAX_EXPORT_ROWS}; "
                "narrow the filters"
            )
        rows = await definition.rows(
            self.repository, request.filters, scope, MAX_EXPORT_ROWS
        )
        organization = await self.repository.organization()
        context = ExportContext(
            company=organization.company_name if organization else DEFAULT_COMPANY,
            generated_by=actor.user.full_name,
            generated_at=now,
            filters=request.filters,
        )
        document = definition.build(rows, context).only(keys)
        render = render_pdf if export_format == "pdf" else render_xlsx
        content = await asyncio.to_thread(
            render,
            document,
            include_summary=request.include_summary,
            include_charts=request.include_charts,
            generated_at=now,
        )

        filters = request.filters.model_dump(mode="json", exclude_none=True)
        run = self.repository.record_run(
            report_key=report,
            export_format=export_format,
            filters=filters,
            row_count=len(rows),
            user_id=actor.id,
        )
        await self.repository.flush()
        self.audit.record(
            user_id=actor.id,
            action="report.exported",
            entity_type="report_run",
            entity_id=run.id,
            new_values={
                "report": report,
                "format": export_format,
                "rows": len(rows),
                "filters": filters,
                "columns": keys,
                "charts": request.include_charts,
                "summary": request.include_summary,
            },
        )
        await self.repository.commit()
        return ExportedFile(
            content=content,
            filename=filename(report, export_format, now),
            media_type=_MEDIA[export_format],
        )

    @staticmethod
    def _columns(
        definition: ExportDefinition,
        export_format: DocumentFormat,
        requested: list[str] | None,
    ) -> list[str]:
        known = [column.key for column in definition.columns]
        if requested is None:
            return list(definition.pdf_default) if export_format == "pdf" else known
        unknown = [key for key in requested if key not in known]
        if unknown:
            raise UnprocessableError(f"unknown columns: {', '.join(unknown)}")
        return requested
