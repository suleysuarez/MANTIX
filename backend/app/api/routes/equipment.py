from fastapi import APIRouter, Depends, Query, Response, status

from app.api.dependencies import require_permission
from app.api.pagination import page_params, set_page_headers
from app.api.providers import get_equipment_service
from app.core.authz import AuthContext
from app.core.pagination import PageParams
from app.schemas.equipment import (
    CustodianCandidate,
    EquipmentCreate,
    EquipmentCustodyAssignRequest,
    EquipmentLocationAssignRequest,
    EquipmentResponse,
    EquipmentSummaryResponse,
    EquipmentTypeResponse,
    EquipmentUpdate,
    LocationCreate,
    LocationResponse,
)
from app.services.equipment import EquipmentService

router = APIRouter(prefix="/equipment", tags=["equipment"])


@router.get(
    "",
    response_model=list[EquipmentResponse],
    summary="List equipment",
    description=(
        "Paginated, filterable and sortable equipment catalog. "
        "Sort fields: `asset_tag`, `brand`, `model`, `status`, `purchase_date`, "
        "`created_at`. Pagination metadata is returned in the `X-Total-Count`, "
        "`X-Page`, `X-Page-Size` and `X-Total-Pages` headers."
    ),
)
async def list_equipment(
    response: Response,
    status_filter: str | None = Query(
        default=None,
        alias="status",
        description="One status or a comma-separated list (e.g. `assigned,in_storage`)",
    ),
    equipment_type_id: int | None = Query(default=None),
    location_id: int | None = Query(
        default=None, description="Items currently placed in this location"
    ),
    brand: str | None = Query(default=None, max_length=100),
    search: str | None = Query(
        default=None,
        max_length=100,
        description="Matches asset tag, serial number, brand or model",
    ),
    params: PageParams = Depends(page_params(default_size=200)),  # noqa: B008
    _: AuthContext = Depends(require_permission("equipment.read")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> list[EquipmentResponse]:
    page = await service.list_equipment(
        status=status_filter,
        equipment_type_id=equipment_type_id,
        location_id=location_id,
        brand=brand,
        search=search,
        params=params,
    )
    set_page_headers(response, page)
    return page.items


@router.get(
    "/summary",
    response_model=EquipmentSummaryResponse,
    summary="Equipment counts by status",
    description="Total and per-status counts for the whole catalog.",
)
async def equipment_summary(
    _: AuthContext = Depends(require_permission("equipment.read")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> EquipmentSummaryResponse:
    return await service.summary()


@router.get(
    "/custodian-candidates",
    response_model=list[CustodianCandidate],
    summary="Search users who can hold equipment",
    description="Active users matching `search` (name or e-mail), at most 20.",
)
async def custodian_candidates(
    search: str | None = Query(default=None, max_length=100),
    _: AuthContext = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> list[CustodianCandidate]:
    return await service.custodian_candidates(search)


@router.get("/types", response_model=list[EquipmentTypeResponse])
async def list_equipment_types(
    _: AuthContext = Depends(require_permission("equipment.read")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> list[EquipmentTypeResponse]:
    return await service.list_types()


@router.get("/{equipment_id}", response_model=EquipmentResponse)
async def get_equipment(
    equipment_id: int,
    _: AuthContext = Depends(require_permission("equipment.read")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> EquipmentResponse:
    return await service.get(equipment_id)


@router.post(
    "",
    response_model=EquipmentResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_equipment(
    payload: EquipmentCreate,
    actor: AuthContext = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> EquipmentResponse:
    return await service.create(payload, actor)


@router.patch("/{equipment_id}", response_model=EquipmentResponse)
async def update_equipment(
    equipment_id: int,
    payload: EquipmentUpdate,
    actor: AuthContext = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> EquipmentResponse:
    return await service.update(equipment_id, payload, actor)


@router.post("/{equipment_id}/location", response_model=EquipmentResponse)
async def assign_equipment_location(
    equipment_id: int,
    payload: EquipmentLocationAssignRequest,
    actor: AuthContext = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> EquipmentResponse:
    return await service.assign_location(equipment_id, payload, actor)


@router.post("/{equipment_id}/custody", response_model=EquipmentResponse)
async def assign_equipment_custody(
    equipment_id: int,
    payload: EquipmentCustodyAssignRequest,
    actor: AuthContext = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> EquipmentResponse:
    return await service.assign_custody(equipment_id, payload, actor)


location_router = APIRouter(prefix="/locations", tags=["equipment"])


@location_router.get(
    "", response_model=list[LocationResponse], summary="List locations"
)
async def list_locations(
    response: Response,
    search: str | None = Query(default=None, max_length=100),
    params: PageParams = Depends(page_params(default_size=200)),  # noqa: B008
    _: AuthContext = Depends(require_permission("equipment.read")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> list[LocationResponse]:
    page = await service.list_locations(search=search, params=params)
    set_page_headers(response, page)
    return page.items


@location_router.post(
    "", response_model=LocationResponse, status_code=status.HTTP_201_CREATED
)
async def create_location(
    payload: LocationCreate,
    actor: AuthContext = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> LocationResponse:
    return await service.create_location(payload, actor)
