from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import require_permission
from app.db.session import get_db
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
    limit: int = Query(default=200, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    _: User = Depends(require_permission("equipment.read")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> list[EquipmentResponse]:
    return await EquipmentService(session).list_equipment(
        status=status_filter,
        equipment_type_id=equipment_type_id,
        limit=limit,
        offset=offset,
    )


@router.get("/types", response_model=list[EquipmentTypeResponse])
async def list_equipment_types(
    _: User = Depends(require_permission("equipment.read")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> list[EquipmentTypeResponse]:
    return await EquipmentService(session).list_types()


@router.get("/{equipment_id}", response_model=EquipmentResponse)
async def get_equipment(
    equipment_id: int,
    _: User = Depends(require_permission("equipment.read")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> EquipmentResponse:
    return await EquipmentService(session).get(equipment_id)


@router.post(
    "",
    response_model=EquipmentResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_equipment(
    payload: EquipmentCreate,
    actor: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> EquipmentResponse:
    return await EquipmentService(session).create(payload, actor)


@router.patch("/{equipment_id}", response_model=EquipmentResponse)
async def update_equipment(
    equipment_id: int,
    payload: EquipmentUpdate,
    actor: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> EquipmentResponse:
    return await EquipmentService(session).update(equipment_id, payload, actor)


@router.post("/{equipment_id}/location", response_model=EquipmentResponse)
async def assign_equipment_location(
    equipment_id: int,
    payload: EquipmentLocationAssignRequest,
    actor: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> EquipmentResponse:
    return await EquipmentService(session).assign_location(equipment_id, payload, actor)


@router.post("/{equipment_id}/custody", response_model=EquipmentResponse)
async def assign_equipment_custody(
    equipment_id: int,
    payload: EquipmentCustodyAssignRequest,
    actor: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> EquipmentResponse:
    return await EquipmentService(session).assign_custody(equipment_id, payload, actor)


location_router = APIRouter(prefix="/locations", tags=["equipment"])


@location_router.get("", response_model=list[LocationResponse])
async def list_locations(
    _: User = Depends(require_permission("equipment.read")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> list[LocationResponse]:
    return await EquipmentService(session).list_locations()


@location_router.post(
    "", response_model=LocationResponse, status_code=status.HTTP_201_CREATED
)
async def create_location(
    payload: LocationCreate,
    _: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> LocationResponse:
    return await EquipmentService(session).create_location(payload)
