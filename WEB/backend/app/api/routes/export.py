from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response

from app.api.dependencies import require_authenticated
from app.api.providers import get_export_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.schemas.export import (
    DocumentFormat,
    ExportCount,
    ExportFilters,
    ExportOptions,
    ExportReportKey,
    ExportRequest,
)
from app.services.export import ExportService

router = APIRouter(prefix="/reports", tags=["reports"])

Service = Annotated[ExportService, Depends(get_export_service)]
#: Who may export is decided per report (`ExportDefinition.permission`), so a technician can export
#: their own tickets without being able to open the Reports screen.
Reader = Annotated[AuthContext, Depends(require_authenticated())]


@router.get(
    "/{report}/export/options",
    response_model=ExportOptions,
    summary="What a report export offers",
    description="Columns (with the defaults per format), formats and limits.",
    responses=error_responses(403, 422),
)
async def export_options(
    report: ExportReportKey, actor: Reader, service: Service
) -> ExportOptions:
    return service.options(report, actor)


@router.post(
    "/{report}/export/count",
    response_model=ExportCount,
    summary="How many records an export would contain",
    description="Same filters as the export, so the screen can say "
    "'N records will be exported' before generating anything.",
    responses=error_responses(403, 422),
)
async def export_count(
    report: ExportReportKey,
    filters: ExportFilters,
    actor: Reader,
    service: Service,
) -> ExportCount:
    return await service.count(actor, report, filters)


@router.post(
    "/{report}/export",
    summary="Export a report as PDF or Excel",
    description=(
        "PDF (header, metadata, table, executive summary and charts, page numbers) or "
        "Excel (Resumen with native charts and Detalle with filters, frozen header and "
        "totals formulas). Only the records the caller may see are included. Responds "
        "422 with a specific message for an inverted or oversized date range, unknown "
        "columns, no matching records, or more than 10,000. Audited with the filters "
        "and the record count."
    ),
    response_class=Response,
    responses={
        200: {
            "description": "The generated file",
            "content": {
                "application/pdf": {},
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": {},
            },
        },
        **error_responses(403, 422),
    },
)
async def export_report(
    report: ExportReportKey,
    payload: ExportRequest,
    actor: Reader,
    service: Service,
    export_format: Annotated[DocumentFormat, Query(alias="format")] = "pdf",
) -> Response:
    file = await service.export(actor, report, export_format, payload)
    return Response(
        content=file.content,
        media_type=file.media_type,
        headers={
            "Content-Disposition": f'attachment; filename="{file.filename}"',
            "Cache-Control": "no-store",
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )
