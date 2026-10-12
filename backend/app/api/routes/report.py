from datetime import datetime
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, File, Query, Response, UploadFile

from app.api.dependencies import require_permission
from app.api.providers import get_equipment_import_service, get_report_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.core.tabular import parse_table
from app.core.uploads import extension_of, read_limited, safe_filename, validate_content
from app.schemas.report import ImportResult
from app.services.data_import import EquipmentImportService
from app.services.report import ExportedFile, ReportService

ExportFormat = Literal["csv", "xlsx", "pdf"]
Format = Annotated[
    ExportFormat,
    Query(alias="format", description="File format of the report"),
]

MAX_IMPORT_BYTES = 5 * 1024 * 1024
IMPORT_EXTENSIONS = frozenset({".csv", ".xlsx"})

router = APIRouter(prefix="/reports", tags=["reports"])
import_router = APIRouter(prefix="/imports", tags=["data-exchange"])

_FILE_RESPONSE = {
    200: {
        "description": "The generated file",
        "content": {
            "text/csv": {},
            "application/pdf": {},
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": {},
        },
    }
}


def _download(report: ExportedFile) -> Response:
    return Response(
        content=report.content,
        media_type=report.media_type,
        headers={
            "Content-Disposition": f'attachment; filename="{report.filename}"',
            "Cache-Control": "no-store",
        },
    )


@router.get(
    "/equipment",
    summary="Export the equipment inventory",
    description="CSV, Excel or PDF (max 10,000 rows) with each item's current "
    "location and custodian.",
    responses={**_FILE_RESPONSE, **error_responses(403)},
    response_class=Response,
)
async def equipment_report(
    export_format: Format = "xlsx",
    status: str | None = Query(default=None),
    equipment_type_id: int | None = Query(default=None),
    _: AuthContext = Depends(require_permission("reports.read")),  # noqa: B008
    service: ReportService = Depends(get_report_service),  # noqa: B008
) -> Response:
    return _download(
        await service.equipment_report(
            export_format=export_format,
            status=status,
            equipment_type_id=equipment_type_id,
        )
    )


@router.get(
    "/tickets",
    summary="Export maintenance tickets",
    responses={**_FILE_RESPONSE, **error_responses(403)},
    response_class=Response,
)
async def ticket_report(
    export_format: Format = "xlsx",
    status: str | None = Query(default=None),
    priority: str | None = Query(default=None),
    date_from: datetime | None = Query(default=None, description="Created at or after"),  # noqa: B008
    date_to: datetime | None = Query(default=None, description="Created at or before"),  # noqa: B008
    _: AuthContext = Depends(require_permission("reports.read")),  # noqa: B008
    service: ReportService = Depends(get_report_service),  # noqa: B008
) -> Response:
    return _download(
        await service.ticket_report(
            export_format=export_format,
            status=status,
            priority=priority,
            date_from=date_from,
            date_to=date_to,
        )
    )


@router.get(
    "/summary",
    summary="Export the operational summary",
    description="The dashboard metrics as a printable PDF or a spreadsheet.",
    responses={**_FILE_RESPONSE, **error_responses(403)},
    response_class=Response,
)
async def summary_report(
    export_format: Format = "pdf",
    days: int = Query(default=30, ge=1, le=365),
    actor: AuthContext = Depends(require_permission("reports.read")),  # noqa: B008
    service: ReportService = Depends(get_report_service),  # noqa: B008
) -> Response:
    return _download(
        await service.summary_report(actor, export_format=export_format, days=days)
    )


@import_router.post(
    "/equipment",
    response_model=ImportResult,
    summary="Bulk-import equipment from CSV or Excel",
    description=(
        "Upload a `.csv` (UTF-8, comma or semicolon) or `.xlsx` file, max 5 MB and "
        "5,000 rows. Required columns: `asset_tag`, `equipment_type` (type code), "
        "`brand`, `model`. Optional: `serial_number`, `description`, `status`, "
        "`purchase_date`, `purchase_cost`, `warranty_start_date`, `warranty_end_date`. "
        "The import is all-or-nothing; use `dry_run=true` to validate only."
    ),
    responses=error_responses(403, 413, 415, 422),
)
async def import_equipment(
    file: UploadFile = File(description="CSV or XLSX file"),  # noqa: B008
    dry_run: bool = Query(default=False),
    actor: AuthContext = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentImportService = Depends(get_equipment_import_service),  # noqa: B008
) -> ImportResult:
    filename = safe_filename(file.filename)
    content = await read_limited(file, max_bytes=MAX_IMPORT_BYTES)
    validate_content(filename, content, IMPORT_EXTENSIONS)
    rows = parse_table(extension_of(filename), content)
    return await service.import_equipment(rows, actor, dry_run=dry_run)
