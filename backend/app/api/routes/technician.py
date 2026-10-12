from fastapi import APIRouter, Depends, Query, Response, status

from app.api.dependencies import require_permission
from app.api.pagination import page_params, set_page_headers
from app.api.providers import get_technician_service
from app.core.authz import AuthContext
from app.core.pagination import PageParams
from app.schemas.technician import (
    TechnicianCreate,
    TechnicianResponse,
    TechnicianUpdate,
)
from app.services.technician import TechnicianService

router = APIRouter(prefix="/technicians", tags=["technicians"])


@router.get(
    "",
    response_model=list[TechnicianResponse],
    summary="List technicians",
    description="Sort fields: `name`, `specialization`, `hourly_rate`.",
)
async def list_technicians(
    response: Response,
    is_available: bool | None = Query(default=None),
    search: str | None = Query(
        default=None,
        max_length=100,
        description="Matches name, e-mail or specialization",
    ),
    params: PageParams = Depends(page_params(default_size=200)),  # noqa: B008
    _: AuthContext = Depends(require_permission("maintenance.read")),  # noqa: B008
    service: TechnicianService = Depends(get_technician_service),  # noqa: B008
) -> list[TechnicianResponse]:
    page = await service.list(is_available=is_available, search=search, params=params)
    set_page_headers(response, page)
    return page.items


@router.post("", response_model=TechnicianResponse, status_code=status.HTTP_201_CREATED)
async def create_technician(
    payload: TechnicianCreate,
    _: AuthContext = Depends(require_permission("technicians.manage")),  # noqa: B008
    service: TechnicianService = Depends(get_technician_service),  # noqa: B008
) -> TechnicianResponse:
    return await service.create(payload)


@router.patch("/{technician_id}", response_model=TechnicianResponse)
async def update_technician(
    technician_id: int,
    payload: TechnicianUpdate,
    _: AuthContext = Depends(require_permission("technicians.manage")),  # noqa: B008
    service: TechnicianService = Depends(get_technician_service),  # noqa: B008
) -> TechnicianResponse:
    return await service.update(technician_id, payload)
