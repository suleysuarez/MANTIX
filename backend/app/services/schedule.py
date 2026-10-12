from datetime import UTC, datetime, timedelta

from app.core.authz import AuthContext
from app.core.exceptions import NotFoundError, UnprocessableError
from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.schedule import MaintenanceSchedule
from app.repositories.base import Page
from app.repositories.equipment import EquipmentRepository
from app.repositories.schedule import ScheduleRepository
from app.repositories.technician import TechnicianRepository
from app.schemas.maintenance import EquipmentSummary, TechnicianSummary
from app.schemas.schedule import (
    ScheduleCreate,
    ScheduleResponse,
    ScheduleUpdate,
)
from app.services.audit import AuditService

_AUDITED_FIELDS = (
    "technician_id",
    "title",
    "description",
    "interval_days",
    "remind_days_before",
    "next_due_at",
    "is_active",
)


def _jsonable(values: dict) -> dict:
    return {
        key: value.isoformat() if isinstance(value, datetime) else value
        for key, value in values.items()
    }


class ScheduleService:
    """Preventive-maintenance plans: CRUD plus "mark as done"."""

    def __init__(
        self,
        repository: ScheduleRepository,
        equipment: EquipmentRepository,
        technicians: TechnicianRepository,
        audit: AuditService,
    ):
        self.repository = repository
        self.equipment = equipment
        self.technicians = technicians
        self.audit = audit

    async def list(
        self,
        *,
        equipment_id: int | None = None,
        is_active: bool | None = None,
        search: str | None = None,
        params: PageParams = DEFAULT_PAGE,
    ) -> Page[ScheduleResponse]:
        page = await self.repository.search(
            equipment_id=equipment_id,
            is_active=is_active,
            search=search,
            params=params,
        )
        return page.map(self._response)

    async def get(self, schedule_id: int) -> ScheduleResponse:
        return self._response(await self._require(schedule_id))

    async def create(
        self, payload: ScheduleCreate, actor: AuthContext
    ) -> ScheduleResponse:
        if await self.equipment.get(payload.equipment_id) is None:
            raise NotFoundError("equipment not found")
        await self._require_technician(payload.technician_id)
        schedule = await self.repository.add_and_flush(
            MaintenanceSchedule(
                equipment_id=payload.equipment_id,
                technician_id=payload.technician_id,
                title=payload.title,
                description=payload.description,
                interval_days=payload.interval_days,
                remind_days_before=payload.remind_days_before,
                next_due_at=payload.first_due_at,
                is_active=True,
                created_by_user_id=actor.id,
            )
        )
        self.audit.record(
            user_id=actor.id,
            action="schedule.created",
            entity_type="maintenance_schedule",
            entity_id=schedule.id,
            new_values=_jsonable(
                {
                    "equipment_id": payload.equipment_id,
                    "title": payload.title,
                    "interval_days": payload.interval_days,
                    "next_due_at": payload.first_due_at,
                }
            ),
        )
        await self.repository.commit()
        return self._response(await self._require(schedule.id))

    async def update(
        self, schedule_id: int, payload: ScheduleUpdate, actor: AuthContext
    ) -> ScheduleResponse:
        schedule = await self._require(schedule_id)
        changes = payload.model_dump(exclude_unset=True)
        if "technician_id" in changes:
            await self._require_technician(changes["technician_id"])
        interval = changes.get("interval_days", schedule.interval_days)
        remind = changes.get("remind_days_before", schedule.remind_days_before)
        if remind > interval:
            raise UnprocessableError("remind_days_before cannot exceed interval_days")
        for field in ("title", "interval_days", "remind_days_before", "next_due_at"):
            if field in changes and changes[field] is None:
                raise UnprocessableError(f"{field} cannot be null")

        old_values = {field: getattr(schedule, field) for field in changes}
        await self.repository.update_fields(schedule, changes)
        if "technician_id" in changes:
            self.repository.expire(schedule, ["technician"])
        if "next_due_at" in changes:
            schedule.last_reminded_at = None  # a new date deserves a new reminder
        self.audit.record(
            user_id=actor.id,
            action="schedule.updated",
            entity_type="maintenance_schedule",
            entity_id=schedule_id,
            old_values=_jsonable(old_values),
            new_values=_jsonable(changes),
        )
        await self.repository.commit()
        return self._response(await self._require(schedule_id))

    async def complete(
        self, schedule_id: int, actor: AuthContext, *, now: datetime | None = None
    ) -> ScheduleResponse:
        """Record that the service was done and schedule the next one.

        The next date counts from the later of "now" and the old due date, so
        finishing early does not shorten the interval and finishing late does
        not leave the plan permanently overdue.
        """
        now = now or datetime.now(UTC)
        schedule = await self._require(schedule_id)
        if not schedule.is_active:
            raise UnprocessableError("the schedule is inactive")
        previous = schedule.next_due_at
        schedule.next_due_at = max(now, previous) + timedelta(
            days=schedule.interval_days
        )
        schedule.last_reminded_at = None
        await self.repository.flush()
        self.audit.record(
            user_id=actor.id,
            action="schedule.completed",
            entity_type="maintenance_schedule",
            entity_id=schedule_id,
            old_values=_jsonable({"next_due_at": previous}),
            new_values=_jsonable({"next_due_at": schedule.next_due_at}),
        )
        await self.repository.commit()
        return self._response(await self._require(schedule_id))

    # -- Internals ---------------------------------------------------------------

    async def _require(self, schedule_id: int) -> MaintenanceSchedule:
        schedule = await self.repository.get(schedule_id)
        if schedule is None:
            raise NotFoundError("maintenance schedule not found")
        return schedule

    async def _require_technician(self, technician_id: int | None) -> None:
        if (
            technician_id is not None
            and await self.technicians.get(technician_id) is None
        ):
            raise NotFoundError("technician not found")

    @staticmethod
    def _response(schedule: MaintenanceSchedule) -> ScheduleResponse:
        technician = schedule.technician
        return ScheduleResponse(
            id=schedule.id,
            equipment=EquipmentSummary.model_validate(schedule.equipment),
            technician=(
                TechnicianSummary(
                    id=technician.id,
                    user_id=technician.user_id,
                    full_name=technician.user.full_name,
                )
                if technician is not None
                else None
            ),
            title=schedule.title,
            description=schedule.description,
            interval_days=schedule.interval_days,
            remind_days_before=schedule.remind_days_before,
            next_due_at=schedule.next_due_at,
            last_reminded_at=schedule.last_reminded_at,
            is_active=schedule.is_active,
            created_at=schedule.created_at,
        )
