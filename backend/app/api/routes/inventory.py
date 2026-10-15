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
from app.schemas.dashboard import Period
from app.schemas.inventory import (
    Category,
    InventoryOverview,
    ItemCreate,
    ItemResponse,
    ItemUpdate,
    MovementCreate,
    MovementResponse,
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
FILE = File(description="CSV or XLSX file")


@router.get(
    "/items",
    response_model=list[ItemResponse],
    summary="List stock items",
    description=(
        "Filter by text, category and stock status. Sort fields: `name` (default), "
        "`sku`, `stock`, `unit_cost`, `stock_value`, `updated_at`, `created_at`."
    ),
)
async def list_items(
    response: Response,
    search: str | None = SEARCH,
    category: Category | None = CATEGORY,
    status_filter: Literal["ok", "low", "out", "stale", "active", "inactive"]
    | None = Query(default=None, alias="status", description=STATUS.description),
    params: PageParams = Depends(page_params()),  # noqa: B008
    _: AuthContext = Depends(require_permission("inventory.read")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> list[ItemResponse]:
    page = await service.list_items(
        search=search, category=category, status=status_filter, params=params
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
    actor: AuthContext = Depends(require_permission("inventory.manage")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> ItemResponse:
    return await service.create(payload, actor)


@router.get(
    "/items/{item_id}",
    response_model=ItemResponse,
    summary="Get a stock item",
    responses=error_responses(404),
)
async def get_item(
    item_id: int,
    _: AuthContext = Depends(require_permission("inventory.read")),  # noqa: B008
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
    actor: AuthContext = Depends(require_permission("inventory.manage")),  # noqa: B008
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
    actor: AuthContext = Depends(require_permission("inventory.manage")),  # noqa: B008
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
    actor: AuthContext = Depends(require_permission("inventory.consume")),  # noqa: B008
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
    _: AuthContext = Depends(require_permission("inventory.read")),  # noqa: B008
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
    _: AuthContext = Depends(require_permission("inventory.read")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> InventoryOverview:
    return await service.overview(period=period)


@router.post(
    "/import",
    response_model=ImportResult,
    summary="Bulk-import stock items from CSV or Excel",
    description=(
        "Upload a `.csv` or `.xlsx` file, max 5 MB. Required columns: `sku`, `name`. "
        "Optional: `description`, `category`, `unit`, `unit_cost`, `stock` (initial), "
        "`min_stock`, `max_stock`, `location`, `supplier`. All-or-nothing; use "
        "`dry_run=true` to validate only."
    ),
    responses=error_responses(403, 413, 415, 422),
)
async def import_items(
    file: UploadFile = FILE,
    dry_run: bool = DRY_RUN,
    actor: AuthContext = Depends(require_permission("inventory.manage")),  # noqa: B008
    service: InventoryService = Depends(get_inventory_service),  # noqa: B008
) -> ImportResult:
    filename = safe_filename(file.filename)
    content = await read_limited(file, max_bytes=MAX_IMPORT_BYTES)
    validate_content(filename, content, IMPORT_EXTENSIONS)
    rows = parse_table(extension_of(filename), content)
    return await service.import_items(rows, actor, dry_run=dry_run)
