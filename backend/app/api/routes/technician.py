from fastapi import APIRouter, Depends, Query, status

from app.api.dependencies import require_permission
from app.api.providers import get_technician_service
from app.models.auth import User
from app.schemas.technician import (
    TechnicianCreate,
    TechnicianResponse,
    TechnicianUpdate,
)
from app.services.technician import TechnicianService

router = APIRouter(prefix="/technicians", tags=["technicians"])


@router.get("", response_model=list[TechnicianResponse])
async def list_technicians(
    is_available: bool | None = Query(default=None),
    _: User = Depends(require_permission("maintenance.read")),  # noqa: B008
    service: TechnicianService = Depends(get_technician_service),  # noqa: B008
) -> list[TechnicianResponse]:
    return await service.list(is_available=is_available)


@router.post("", response_model=TechnicianResponse, status_code=status.HTTP_201_CREATED)
async def create_technician(
    payload: TechnicianCreate,
    _: User = Depends(require_permission("technicians.manage")),  # noqa: B008
    service: TechnicianService = Depends(get_technician_service),  # noqa: B008
) -> TechnicianResponse:
    return await service.create(payload)


@router.patch("/{technician_id}", response_model=TechnicianResponse)
async def update_technician(
    technician_id: int,
    payload: TechnicianUpdate,
    _: User = Depends(require_permission("technicians.manage")),  # noqa: B008
    service: TechnicianService = Depends(get_technician_service),  # noqa: B008
) -> TechnicianResponse:
    return await service.update(technician_id, payload)
