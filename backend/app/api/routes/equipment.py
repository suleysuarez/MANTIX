from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import require_permission
from app.db.session import get_db
from app.models.auth import User
from app.schemas.equipment import (
    EquipmentCreate,
    EquipmentResponse,
    EquipmentTypeResponse,
    EquipmentUpdate,
)
from app.services.equipment import EquipmentService

router = APIRouter(prefix="/equipment", tags=["equipment"])


@router.get("", response_model=list[EquipmentResponse])
async def list_equipment(
    _: User = Depends(require_permission("equipment.read")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> list[EquipmentResponse]:
    return await EquipmentService(session).list_equipment()


@router.get("/types", response_model=list[EquipmentTypeResponse])
async def list_equipment_types(
    _: User = Depends(require_permission("equipment.read")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> list[EquipmentTypeResponse]:
    return await EquipmentService(session).list_types()


@router.post(
    "",
    response_model=EquipmentResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_equipment(
    payload: EquipmentCreate,
    _: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> EquipmentResponse:
    return await EquipmentService(session).create(payload)


@router.patch("/{equipment_id}", response_model=EquipmentResponse)
async def update_equipment(
    equipment_id: int,
    payload: EquipmentUpdate,
    _: User = Depends(require_permission("equipment.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> EquipmentResponse:
    return await EquipmentService(session).update(equipment_id, payload)
