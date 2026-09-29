from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import require_permission
from app.db.session import get_db
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
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> list[TechnicianResponse]:
    return await TechnicianService(session).list(is_available=is_available)


@router.post("", response_model=TechnicianResponse, status_code=status.HTTP_201_CREATED)
async def create_technician(
    payload: TechnicianCreate,
    _: User = Depends(require_permission("technicians.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> TechnicianResponse:
    return await TechnicianService(session).create(payload)


@router.patch("/{technician_id}", response_model=TechnicianResponse)
async def update_technician(
    technician_id: int,
    payload: TechnicianUpdate,
    _: User = Depends(require_permission("technicians.manage")),  # noqa: B008
    session: AsyncSession = Depends(get_db),  # noqa: B008
) -> TechnicianResponse:
    return await TechnicianService(session).update(technician_id, payload)
