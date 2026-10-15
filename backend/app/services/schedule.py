from datetime import UTC, datetime, timedelta
from typing import Any

from app.core.authz import AuthContext
from app.core.exceptions import BusinessRuleError, NotFoundError, UnprocessableError
from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.schedule import MaintenanceSchedule
from app.repositories.base import Page
from app.repositories.equipment import EquipmentRepository
from app.repositories.schedule import ScheduleRepository
from app.repositories.technician import TechnicianRepository
from app.schemas.maintenance import EquipmentSummary, TechnicianSummary
from app.schemas.schedule import (
    ScheduleCreate,
    ScheduleHistoryResponse,
    ScheduleRescheduleResponse,
    ScheduleResponse,
    ScheduleRunResponse,
    ScheduleUpdate,
)
from app.services.audit import AuditService

_AUDITED_FIELDS = (
    "technician_id",
    "title",
    "description",
    "interval_days",
    "estimated_hours",
    "remind_days_before",
    "next_due_at",
    "is_active",
)

#: Equipment that is gone for good gets no preventive plan.
UNSERVICEABLE_STATUSES = ("retired", "disposed", "lost")
#: Longest due-date window a listing may ask for.
MAX_DUE_RANGE = timedelta(days=400)


def _jsonable(values: dict[str, Any]) -> dict[str, Any]:
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
        technician_id: int | None = None,
        due_from: datetime | None = None,
        due_to: datetime | None = None,
        overdue: bool = False,
        params: PageParams = DEFAULT_PAGE,
        now: datetime | None = None,
    ) -> Page[ScheduleResponse]:
        if due_from is not None and due_to is not None:
            if due_to <= due_from:
                raise UnprocessableError("due_to must be after due_from")
            if due_to - due_from > MAX_DUE_RANGE:
                raise UnprocessableError(
                    f"the due date range cannot exceed {MAX_DUE_RANGE.days} days"
                )
        page = await self.repository.search(
            equipment_id=equipment_id,
            is_active=is_active,
            search=search,
            technician_id=technician_id,
            due_from=due_from,
            due_to=due_to,
            overdue_at=(now or datetime.now(UTC)) if overdue else None,
            params=params,
        )
        return page.map(self._response)

    async def get(self, schedule_id: int) -> ScheduleResponse:
        return self._response(await self._require(schedule_id))

    async def create(
        self,
        payload: ScheduleCreate,
        actor: AuthContext,
        *,
        now: datetime | None = None,
    ) -> ScheduleResponse:
        equipment = await self.equipment.get(payload.equipment_id)
        if equipment is None:
            raise NotFoundError("equipment not found")
        if getattr(equipment, "status", None) in UNSERVICEABLE_STATUSES:
            raise BusinessRuleError(
                f"cannot schedule maintenance for equipment that is {equipment.status}"
            )
        self._require_not_past(payload.first_due_at, now)
        await self._require_technician(payload.technician_id)
        schedule = await self.repository.add_and_flush(
            MaintenanceSchedule(
                equipment_id=payload.equipment_id,
                technician_id=payload.technician_id,
                title=payload.title,
                description=payload.description,
                interval_days=payload.interval_days,
                estimated_hours=payload.estimated_hours,
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
        self,
        schedule_id: int,
        payload: ScheduleUpdate,
        actor: AuthContext,
        *,
        now: datetime | None = None,
    ) -> ScheduleResponse:
        schedule = await self._require(schedule_id)
        changes = payload.model_dump(exclude_unset=True)
        reason = changes.pop("reschedule_reason", None)
        moved = (
            "next_due_at" in changes
            and changes["next_due_at"] is not None
            and changes["next_due_at"] != schedule.next_due_at
        )
        if reason is not None and not moved:
            raise UnprocessableError("reschedule_reason needs a new next_due_at")
        if moved:
            self._require_not_past(changes["next_due_at"], now)
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
        if moved:
            self.repository.record_reschedule(
                schedule_id=schedule_id,
                old_due_at=old_values["next_due_at"],
                new_due_at=changes["next_due_at"],
                reason=reason,
                user_id=actor.id,
            )
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
        self,
        schedule_id: int,
        actor: AuthContext,
        *,
        actual_hours: Any = None,
        now: datetime | None = None,
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
        self.repository.record_run(
            schedule_id=schedule_id,
            due_at=previous,
            completed_at=now,
            actual_hours=actual_hours,
            user_id=actor.id,
        )
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

    async def history(self, schedule_id: int) -> ScheduleHistoryResponse:
        await self._require(schedule_id)
        runs, moves = await self.repository.history(schedule_id)
        return ScheduleHistoryResponse(
            runs=[
                ScheduleRunResponse(
                    id=r.id,
                    due_at=r.due_at,
                    completed_at=r.completed_at,
                    on_time=r.completed_at <= r.due_at,
                    actual_hours=r.actual_hours,
                )
                for r in runs
            ],
            reschedules=[
                ScheduleRescheduleResponse(
                    id=m.id,
                    old_due_at=m.old_due_at,
                    new_due_at=m.new_due_at,
                    reason=m.reason,
                    changed_at=m.changed_at,
                )
                for m in moves
            ],
        )

    # -- Internals ---------------------------------------------------------------

    async def _require(self, schedule_id: int) -> MaintenanceSchedule:
        schedule = await self.repository.get(schedule_id)
        if schedule is None:
            raise NotFoundError("maintenance schedule not found")
        return schedule

    @staticmethod
    def _require_not_past(value: datetime, now: datetime | None) -> None:
        if value < (now or datetime.now(UTC)):
            raise UnprocessableError("a service cannot be scheduled in the past")

    async def _require_technician(self, technician_id: int | None) -> None:
        if technician_id is None:
            return
        technician = await self.technicians.get(technician_id)
        if technician is None:
            raise NotFoundError("technician not found")
        user = getattr(technician, "user", None)
        if user is not None and not user.is_active:
            raise BusinessRuleError("cannot assign a plan to an inactive technician")

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
            estimated_hours=schedule.estimated_hours,
            remind_days_before=schedule.remind_days_before,
            next_due_at=schedule.next_due_at,
            last_reminded_at=schedule.last_reminded_at,
            is_active=schedule.is_active,
            created_at=schedule.created_at,
        )
