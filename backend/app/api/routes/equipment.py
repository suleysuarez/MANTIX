from fastapi import APIRouter, Depends, Query, status

from app.api.dependencies import require_permission
from app.api.providers import get_equipment_service
from app.models.auth import User
from app.schemas.equipment import (
    EquipmentCreate,
    EquipmentCustodyAssignRequest,
    EquipmentLocationAssignRequest,
    EquipmentResponse,
    EquipmentTypeResponse,
    EquipmentUpdate,
    LocationCreate,
    LocationResponse,
)
from app.services.equipment import EquipmentService

router = APIRouter(prefix="/equipment", tags=["equipment"])


@router.get("", response_model=list[EquipmentResponse])
async def list_equipment(
    status_filter: str | None = Query(default=None, alias="status"),
    equipment_type_id: int | None = Query(default=None),
    search: str | None = Query(default=None, max_length=100),
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    _: User = Depends(require_permission("equipment.read")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> list[EquipmentResponse]:
    return await service.list_equipment(
        status=status_filter,
        equipment_type_id=equipment_type_id,
        search=search,
        limit=limit,
        offset=offset,
    )


@router.get("/types", response_model=list[EquipmentTypeResponse])
async def list_equipment_types(
    _: User = Depends(require_permission("equipment.read")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> list[EquipmentTypeResponse]:
    return await service.list_types()


@router.get("/{equipment_id}", response_model=EquipmentResponse)
async def get_equipment(
    equipment_id: int,
    _: User = Depends(require_permission("equipment.read")),  # noqa: B008
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
    actor: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> EquipmentResponse:
    return await service.create(payload, actor)


@router.patch("/{equipment_id}", response_model=EquipmentResponse)
async def update_equipment(
    equipment_id: int,
    payload: EquipmentUpdate,
    actor: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> EquipmentResponse:
    return await service.update(equipment_id, payload, actor)


@router.post("/{equipment_id}/location", response_model=EquipmentResponse)
async def assign_equipment_location(
    equipment_id: int,
    payload: EquipmentLocationAssignRequest,
    actor: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> EquipmentResponse:
    return await service.assign_location(equipment_id, payload, actor)


@router.post("/{equipment_id}/custody", response_model=EquipmentResponse)
async def assign_equipment_custody(
    equipment_id: int,
    payload: EquipmentCustodyAssignRequest,
    actor: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> EquipmentResponse:
    return await service.assign_custody(equipment_id, payload, actor)


location_router = APIRouter(prefix="/locations", tags=["equipment"])


@location_router.get("", response_model=list[LocationResponse])
async def list_locations(
    _: User = Depends(require_permission("equipment.read")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> list[LocationResponse]:
    return await service.list_locations()


@location_router.post(
    "", response_model=LocationResponse, status_code=status.HTTP_201_CREATED
)
async def create_location(
    payload: LocationCreate,
    _: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    service: EquipmentService = Depends(get_equipment_service),  # noqa: B008
) -> LocationResponse:
    return await service.create_location(payload)
