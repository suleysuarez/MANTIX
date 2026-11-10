from fastapi import APIRouter, Depends, Query, Response

from app.api.dependencies import require_permission
from app.api.pagination import page_params, set_page_headers
from app.api.providers import get_queue_service
from app.core.authz import AuthContext
from app.core.pagination import PageParams
from app.schemas.dashboard import Period
from app.schemas.queue import QueueSummary, RequestCategoryResponse
from app.services.queue import QueueService

router = APIRouter(prefix="/maintenance", tags=["maintenance"])

PERIOD = Query(default="30d", description="Global dashboard period")


@router.get(
    "/categories",
    response_model=list[RequestCategoryResponse],
    summary="Active request categories",
    description=(
        "Active categories by name. `search` narrows them by name. Paginated "
        "(`page`, `size`) with the `X-Total-Count`, `X-Page`, `X-Page-Size` and "
        "`X-Total-Pages` headers; the default size returns the whole short catalog."
    ),
)
async def list_categories(
    response: Response,
    search: str | None = Query(default=None, max_length=100),
    params: PageParams = Depends(page_params(default_size=200)),  # noqa: B008
    _: AuthContext = Depends(require_permission("tickets:ver")),  # noqa: B008
    service: QueueService = Depends(get_queue_service),  # noqa: B008
) -> list[RequestCategoryResponse]:
    page = await service.categories(search, params)
    set_page_headers(response, page)
    return page.items


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
