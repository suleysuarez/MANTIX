from datetime import datetime
from decimal import Decimal
from typing import Literal

from fastapi import APIRouter, Depends, File, Query, Response, UploadFile, status

from app.api.dependencies import require_permission
from app.api.pagination import page_params, set_page_headers
from app.api.providers import get_inventory_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.core.pagination import PageParams
from app.core.tabular import parse_table
from app.core.uploads import extension_of, read_limited, safe_filename, validate_content
from app.repositories.inventory import ItemRanges
from app.schemas.dashboard import Period
from app.schemas.inventory import (
    MAX_QUANTITY,
    Category,
    InventoryOverview,
    ItemCreate,
    ItemResponse,
    ItemUpdate,
    MovementCreate,
    MovementResponse,
    OptionCreate,
    OptionKind,
    OptionResponse,
)
from app.schemas.report import ImportResult
from app.services.inventory import InventoryService

MAX_IMPORT_BYTES = 5 * 1024 * 1024
IMPORT_EXTENSIONS = frozenset({".csv", ".xlsx"})

router = APIRouter(prefix="/inventory", tags=["inventory"])

PERIOD = Query(default="30d", description="Global dashboard period")
SEARCH = Query(
    default=None, max_length=100, description="SKU, name, supplier or location"
)
CATEGORY = Query(default=None)
STATUS = Query(
    default=None,
    description="`ok`, `low`, `out`, `stale` (no movement for 90 days), `active` or `inactive`",
)
DRY_RUN = Query(default=False)
STOCK_MIN = Query(default=None, ge=0, le=MAX_QUANTITY)
STOCK_MAX = Query(default=None, ge=0, le=MAX_QUANTITY)
COST_MIN = Query(default=None, ge=0, le=1_000_000)
COST_MAX = Query(default=None, ge=0, le=1_000_000)
CREATED_FROM = Query(default=None, description="Added at or after")
CREATED_TO = Query(default=None, description="Added at or before")
MOVED_FROM = Query(default=None, description="Last movement at or after")
MOVED_TO = Query(default=None, description="Last movement at or before")
KIND = Query(default=None)
SKIP_INVALID = Query(
    default=False,
    description="Import the valid rows and report the rest instead of importing nothing",
)
FILE = File(description="CSV or XLSX file")


@router.get(
    "/items",
    response_model=list[ItemResponse],
    summary="List stock items",
    description=(
        "Filter by text, category and stock status, and by ranges: stock, unit cost, the "
        "date an item was added (`created_*`) and the date of its last movement "
        "(`moved_*`); a range whose end is before its start is a 422. Sort fields: "
        "`name` (default), `sku`, `stock`, `unit_cost`, `stock_value`, `updated_at`, "
        "`created_at`."
    ),
    responses=error_responses(422),
)
async def list_items(
    response: Response,
    search: str | None = SEARCH,
    category: Category | None = CATEGORY,
    status_filter: Literal["ok", "low", "out", "stale", "active", "inactive"]
    | None = Query(default=None, alias="status", description=STATUS.description),
    stock_min: int | None = STOCK_MIN,
    stock_max: int | None = STOCK_MAX,
    cost_min: Decimal | None = COST_MIN,
    cost_max: Decimal | None = COST_MAX,
    created_from: datetime | None = CREATED_FROM,
    created_to: datetime | None = CREATED_TO,
    moved_from: datetime | None = MOVED_FROM,
    moved_to: datetime | None = MOVED_TO,
    params: PageParams = Depends(page_params()),  # noqa: B008
    _: AuthContext = Depends(require_permission("inventario:ver")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> list[ItemResponse]:
    page = await service.list_items(
        search=search,
        category=category,
        status=status_filter,
        params=params,
        ranges=ItemRanges(
            stock_min=stock_min,
            stock_max=stock_max,
            cost_min=cost_min,
            cost_max=cost_max,
            created_from=created_from,
            created_to=created_to,
            moved_from=moved_from,
            moved_to=moved_to,
        ),
    )
    set_page_headers(response, page)
    return page.items


@router.post(
    "/items",
    response_model=ItemResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a stock item",
    description="`initial_stock` is recorded as an entry in the ledger. The SKU is unique.",
    responses=error_responses(409, 422),
)
async def create_item(
    payload: ItemCreate,
    actor: AuthContext = Depends(require_permission("inventario:crear")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> ItemResponse:
    return await service.create(payload, actor)


@router.get(
    "/options",
    response_model=list[OptionResponse],
    summary="Values of the item drop-downs",
    description="Categories, units, locations and suppliers, optionally one `kind`.",
    responses=error_responses(403),
)
async def list_options(
    kind: OptionKind | None = KIND,
    _: AuthContext = Depends(require_permission("inventario:ver")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> list[OptionResponse]:
    return await service.list_options(kind)


@router.post(
    "/options",
    response_model=OptionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add a value to an item drop-down",
    description=(
        "The name is normalised (spaces collapsed, title case; units in lower case). A "
        "value that already exists, in any case, is a 409. Audited."
    ),
    responses=error_responses(403, 409, 422),
)
async def create_option(
    payload: OptionCreate,
    actor: AuthContext = Depends(require_permission("inventario:crear")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> OptionResponse:
    return await service.create_option(payload, actor)


@router.get(
    "/items/{item_id}",
    response_model=ItemResponse,
    summary="Get a stock item",
    responses=error_responses(404),
)
async def get_item(
    item_id: int,
    _: AuthContext = Depends(require_permission("inventario:ver")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> ItemResponse:
    return await service.get(item_id)


@router.patch(
    "/items/{item_id}",
    response_model=ItemResponse,
    summary="Update a stock item",
    description="Stock cannot be edited here; register a movement instead.",
    responses=error_responses(404, 422),
)
async def update_item(
    item_id: int,
    payload: ItemUpdate,
    actor: AuthContext = Depends(require_permission("inventario:editar")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> ItemResponse:
    return await service.update(item_id, payload, actor)


@router.delete(
    "/items/{item_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a stock item",
    description="Only items that never moved can be deleted; otherwise deactivate them.",
    responses=error_responses(404, 409),
)
async def delete_item(
    item_id: int,
    actor: AuthContext = Depends(require_permission("inventario:eliminar")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> Response:
    await service.delete(item_id, actor)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/items/{item_id}/movements",
    response_model=MovementResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register a stock movement",
    description=(
        "`out` (consumption, optionally linked to a maintenance record or ticket) is open "
        "to anyone who can consume stock; `in` and `adjust` need `inventory.manage`. "
        "Consumption beyond the available stock is rejected with 409."
    ),
    responses=error_responses(404, 409, 422),
)
async def register_movement(
    item_id: int,
    payload: MovementCreate,
    actor: AuthContext = Depends(require_permission("inventario:consumir")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> MovementResponse:
    return await service.move(item_id, payload, actor)


@router.get(
    "/items/{item_id}/movements",
    response_model=list[MovementResponse],
    summary="Movement history of an item, newest first",
    responses=error_responses(404),
)
async def list_movements(
    item_id: int,
    response: Response,
    params: PageParams = Depends(page_params()),  # noqa: B008
    _: AuthContext = Depends(require_permission("inventario:ver")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> list[MovementResponse]:
    page = await service.movements(item_id, params=params)
    set_page_headers(response, page)
    return page.items


@router.get(
    "/overview",
    response_model=InventoryOverview,
    summary="Inventory metrics for the period",
    description=(
        "Stock value, items at or below their minimum, consumption and rotation with "
        "their change against the previous period, monthly consumption, items with no "
        "movement for 90 days, most-used items in maintenance and replenishment alerts."
    ),
)
async def inventory_overview(
    period: Period = PERIOD,
    _: AuthContext = Depends(require_permission("inventario:ver")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> InventoryOverview:
    return await service.overview(period=period)


@router.get(
    "/import/template",
    summary="Excel template for the import",
    description=(
        "A styled workbook with the columns, drop-downs and number rules, and an "
        "«Instrucciones» sheet. It holds no example row, so nothing is imported by accident."
    ),
    response_class=Response,
    responses={
        200: {
            "content": {
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": {}
            }
        },
        **error_responses(403),
    },
)
async def import_template(
    _: AuthContext = Depends(require_permission("inventario:importar")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> Response:
    return Response(
        content=await service.import_template(),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": 'attachment; filename="plantilla-inventario.xlsx"',
            "Cache-Control": "no-store",
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.post(
    "/import",
    response_model=ImportResult,
    summary="Bulk-import stock items from CSV or Excel",
    description=(
        "Upload a `.csv` or `.xlsx` file, max 5 MB. Required columns: `sku`, `name`. "
        "Optional: `description`, `category`, `unit`, `unit_cost`, `stock` (initial), "
        "`min_stock`, `max_stock`, `location`, `supplier`. Every row is checked "
        "(negatives, types, duplicate codes, minimum above maximum, unknown category) "
        "and the answer says how many are valid and lists each problem by row. "
        "All-or-nothing by default; `skip_invalid=true` imports the valid rows only. "
        "`dry_run=true` validates without writing."
    ),
    responses=error_responses(403, 413, 415, 422),
)
async def import_items(
    file: UploadFile = FILE,
    dry_run: bool = DRY_RUN,
    skip_invalid: bool = SKIP_INVALID,
    actor: AuthContext = Depends(require_permission("inventario:importar")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> ImportResult:
    filename = safe_filename(file.filename)
    content = await read_limited(file, max_bytes=MAX_IMPORT_BYTES)
    validate_content(filename, content, IMPORT_EXTENSIONS)
    rows = parse_table(extension_of(filename), content)
    return await service.import_items(
        rows, actor, dry_run=dry_run, skip_invalid=skip_invalid
    )
