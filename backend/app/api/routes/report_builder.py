from fastapi import APIRouter, Depends, Query, Response

from app.api.dependencies import require_permission
from app.api.pagination import set_page_headers
from app.api.providers import get_report_builder_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.schemas.dashboard import Period
from app.schemas.report_builder import (
    CatalogResponse,
    ReportGenerateRequest,
    ReportPreview,
    ReportPreviewRequest,
    ReportRunResponse,
    ReportsOverview,
)
from app.services.report_builder import ReportBuilderService

router = APIRouter(prefix="/reports", tags=["reports"])

PERIOD = Query(default="30d", description="Global dashboard period")
PAGE = Query(default=1, ge=1)
SIZE = Query(default=10, ge=1, le=100)


@router.get(
    "/catalog",
    response_model=CatalogResponse,
    summary="Report gallery",
    description="Every report with the filters it accepts (and their options), the "
    "export formats and the limits.",
)
async def catalog(
    _: AuthContext = Depends(require_permission("reports.read")),  # noqa: B008
    service: ReportBuilderService = Depends(get_report_builder_service),  # noqa: B008
) -> CatalogResponse:
    return await service.catalog()


@router.post(
    "/preview",
    response_model=ReportPreview,
    summary="Preview a report with its filters",
    description=(
        "The first rows and the total. With `compare` (needs `date_from` and `date_to`), "
        "also the row count of the previous period of equal length. Filters the report "
        "does not take, unknown values and ranges above 366 days are rejected."
    ),
    responses=error_responses(403, 422),
)
async def preview_report(
    payload: ReportPreviewRequest,
    actor: AuthContext = Depends(require_permission("reports.read")),  # noqa: B008
    service: ReportBuilderService = Depends(get_report_builder_service),  # noqa: B008
) -> ReportPreview:
    return await service.preview(actor, payload)


@router.post(
    "/generate",
    summary="Generate and download a report",
    description=(
        "CSV, Excel or PDF with the chosen filters (max 10,000 rows; narrower filters "
        "are asked for instead of truncating). Each file generated is logged."
    ),
    responses={
        200: {
            "description": "The generated file",
            "content": {"text/csv": {}, "application/pdf": {}},
        },
        **error_responses(403, 422),
    },
    response_class=Response,
)
async def generate_report(
    payload: ReportGenerateRequest,
    actor: AuthContext = Depends(require_permission("reports.read")),  # noqa: B008
    service: ReportBuilderService = Depends(get_report_builder_service),  # noqa: B008
) -> Response:
    report = await service.generate(actor, payload)
    return Response(
        content=report.content,
        media_type=report.media_type,
        headers={
            "Content-Disposition": f'attachment; filename="{report.filename}"',
            "Cache-Control": "no-store",
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.get(
    "/overview",
    response_model=ReportsOverview,
    summary="Report activity for the period",
    description="Reports generated (against the previous period), most used, by "
    "format, people and the last export.",
)
async def reports_overview(
    period: Period = PERIOD,
    _: AuthContext = Depends(require_permission("reports.read")),  # noqa: B008
    service: ReportBuilderService = Depends(get_report_builder_service),  # noqa: B008
) -> ReportsOverview:
    return await service.overview(period=period)


@router.get(
    "/history",
    response_model=list[ReportRunResponse],
    summary="Recent exports, newest first",
)
async def report_history(
    response: Response,
    page: int = PAGE,
    size: int = SIZE,
    _: AuthContext = Depends(require_permission("reports.read")),  # noqa: B008
    service: ReportBuilderService = Depends(get_report_builder_service),  # noqa: B008
) -> list[ReportRunResponse]:
    result = await service.history(page=page, size=size)
    set_page_headers(response, result)
    return result.items
