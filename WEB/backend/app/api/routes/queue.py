from fastapi import APIRouter, Depends, Query

from app.api.dependencies import require_permission
from app.api.providers import get_queue_service
from app.core.authz import AuthContext
from app.schemas.dashboard import Period
from app.schemas.queue import QueueSummary, RequestCategoryResponse
from app.services.queue import QueueService

router = APIRouter(prefix="/maintenance", tags=["maintenance"])

PERIOD = Query(default="30d", description="Global dashboard period")


@router.get(
    "/categories",
    response_model=list[RequestCategoryResponse],
    summary="Active request categories",
)
async def list_categories(
    _: AuthContext = Depends(require_permission("tickets:ver")),  # noqa: B008
    service: QueueService = Depends(get_queue_service),  # noqa: B008
) -> list[RequestCategoryResponse]:
    return await service.categories()


@router.get(
    "/queue/summary",
    response_model=QueueSummary,
    summary="Pending-requests queue metrics",
    description=(
        "Requests waiting for work (submitted, triaged or assigned but not started): "
        "oldest and median time in queue, split by priority and category, how many "
        "have no technician, plus, for the period and compared with the previous "
        "one: mean time to first decision and approval/rejection rate (a rejection "
        "is a cancellation made while the request was still `submitted`). "
        "ADMIN and SUPERVISOR only."
    ),
)
async def queue_summary(
    period: Period = PERIOD,
    actor: AuthContext = Depends(require_permission("solicitudes:ver_todos")),  # noqa: B008
    service: QueueService = Depends(get_queue_service),  # noqa: B008
) -> QueueSummary:
    return await service.summary(actor, period=period)
