from fastapi import APIRouter, Depends, Query, Response, status
from pydantic import AwareDatetime

from app.api.dependencies import require_permission
from app.api.pagination import page_params, set_page_headers
from app.api.providers import get_reminder_service, get_schedule_service
from app.core.authz import AuthContext
from app.core.errors import error_responses
from app.core.pagination import PageParams
from app.schemas.schedule import (
    ReminderRunResponse,
    ScheduleCompleteRequest,
    ScheduleCreate,
    ScheduleHistoryResponse,
    ScheduleResponse,
    ScheduleUpdate,
)
from app.services.reminders import ReminderService
from app.services.schedule import ScheduleService

DUE_FROM = Query(default=None, description="Next service at or after")
DUE_TO = Query(default=None, description="Next service before")
OVERDUE = Query(default=False, description="Only active plans already overdue")

router = APIRouter(prefix="/maintenance/schedules", tags=["schedules"])


@router.get(
    "",
    response_model=list[ScheduleResponse],
    summary="List preventive-maintenance plans",
    description="Sort fields: `next_due_at` (default), `title`, `created_at`.",
)
async def list_schedules(
    response: Response,
    equipment_id: int | None = Query(default=None),
    is_active: bool | None = Query(default=None),
    search: str | None = Query(default=None, max_length=100),
    technician_id: int | None = Query(default=None),
    due_from: AwareDatetime | None = DUE_FROM,
    due_to: AwareDatetime | None = DUE_TO,
    overdue: bool = OVERDUE,
    params: PageParams = Depends(page_params()),  # noqa: B008
    actor: AuthContext = Depends(require_permission("mantenimiento:ver")),  # noqa: B008
    service: ScheduleService = Depends(get_schedule_service),  # noqa: B008
) -> list[ScheduleResponse]:
    page = await service.list(
        actor=actor,
        equipment_id=equipment_id,
        is_active=is_active,
        search=search,
        technician_id=technician_id,
        due_from=due_from,
        due_to=due_to,
        overdue=overdue,
        params=params,
    )
    set_page_headers(response, page)
    return page.items


@router.post(
    "",
    response_model=ScheduleResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a preventive-maintenance plan",
    description=(
        "A recurring service for one equipment item. The assigned technician (or the "
        "creator, when none is set) gets an in-app reminder `remind_days_before` days "
        "ahead of every due date."
    ),
    responses=error_responses(404, 422),
)
async def create_schedule(
    payload: ScheduleCreate,
    actor: AuthContext = Depends(require_permission("mantenimiento:crear")),  # noqa: B008
    service: ScheduleService = Depends(get_schedule_service),  # noqa: B008
) -> ScheduleResponse:
    return await service.create(payload, actor)


@router.post(
    "/run-reminders",
    response_model=ReminderRunResponse,
    summary="Run the reminder job now",
    description=(
        "Runs the same job the background scheduler runs. Idempotent: each plan is "
        "reminded once per due date."
    ),
)
async def run_reminders(
    _: AuthContext = Depends(require_permission("mantenimiento:editar")),  # noqa: B008
    service: ReminderService = Depends(get_reminder_service),  # noqa: B008
) -> ReminderRunResponse:
    return await service.run()


@router.get(
    "/{schedule_id}",
    response_model=ScheduleResponse,
    summary="Get a plan",
    responses=error_responses(404),
)
async def get_schedule(
    schedule_id: int,
    actor: AuthContext = Depends(require_permission("mantenimiento:ver")),  # noqa: B008
    service: ScheduleService = Depends(get_schedule_service),  # noqa: B008
) -> ScheduleResponse:
    return await service.get(schedule_id, actor)


@router.patch(
    "/{schedule_id}",
    response_model=ScheduleResponse,
    summary="Update a plan",
    description="Deactivate a plan with `is_active=false`. Changing `next_due_at` "
    "re-arms its reminder.",
    responses=error_responses(404, 422),
)
async def update_schedule(
    schedule_id: int,
    payload: ScheduleUpdate,
    actor: AuthContext = Depends(require_permission("mantenimiento:editar")),  # noqa: B008
    service: ScheduleService = Depends(get_schedule_service),  # noqa: B008
) -> ScheduleResponse:
    return await service.update(schedule_id, payload, actor)


@router.post(
    "/{schedule_id}/complete",
    response_model=ScheduleResponse,
    summary="Mark the service as done",
    description="Moves `next_due_at` forward by one interval and re-arms the reminder.",
    responses=error_responses(404, 422),
)
async def complete_schedule(
    schedule_id: int,
    payload: ScheduleCompleteRequest | None = None,
    actor: AuthContext = Depends(require_permission("mantenimiento:editar")),  # noqa: B008
    service: ScheduleService = Depends(get_schedule_service),  # noqa: B008
) -> ScheduleResponse:
    hours = payload.actual_hours if payload else None
    return await service.complete(schedule_id, actor, actual_hours=hours)


@router.get(
    "/{schedule_id}/history",
    response_model=ScheduleHistoryResponse,
    summary="Completions and reschedules of a plan",
    responses=error_responses(404),
)
async def schedule_history(
    schedule_id: int,
    actor: AuthContext = Depends(require_permission("mantenimiento:ver")),  # noqa: B008
    service: ScheduleService = Depends(get_schedule_service),  # noqa: B008
) -> ScheduleHistoryResponse:
    return await service.history(schedule_id, actor)
