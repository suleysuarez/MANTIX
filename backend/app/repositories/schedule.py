from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import Select, and_, func, or_, select, text
from sqlalchemy.orm import selectinload

from app.core.pagination import DEFAULT_PAGE, PageParams
from app.models.schedule import MaintenanceSchedule
from app.models.technician import Technician
from app.repositories.base import BaseRepository, Page

#: Arbitrary application-wide id for the reminder job's advisory lock.
REMINDER_LOCK_KEY = 85219402

SORTABLE = {
    "next_due_at": MaintenanceSchedule.next_due_at,
    "title": MaintenanceSchedule.title,
    "created_at": MaintenanceSchedule.created_at,
    "id": MaintenanceSchedule.id,
}


class ScheduleRepository(BaseRepository[MaintenanceSchedule]):
    model = MaintenanceSchedule

    @staticmethod
    def _query() -> Select[Any]:
        return select(MaintenanceSchedule).options(
            selectinload(MaintenanceSchedule.equipment),
            selectinload(MaintenanceSchedule.technician).selectinload(Technician.user),
        )

    async def get(self, entity_id: int) -> MaintenanceSchedule | None:
        result = await self.session.execute(
            self._query().where(MaintenanceSchedule.id == entity_id)
        )
        schedule: MaintenanceSchedule | None = result.scalar_one_or_none()
        return schedule

    async def try_acquire_reminder_lock(self) -> bool:
        """Transaction-scoped advisory lock: only one worker runs the job at a time.

        Released automatically on commit/rollback of the current transaction.
        """
        result = await self.session.execute(
            text("SELECT pg_try_advisory_xact_lock(:key)"), {"key": REMINDER_LOCK_KEY}
        )
        return bool(result.scalar_one())

    async def search(
        self,
        *,
        equipment_id: int | None = None,
        is_active: bool | None = None,
        search: str | None = None,
        params: PageParams = DEFAULT_PAGE,
    ) -> Page[MaintenanceSchedule]:
        query = self._query()
        if equipment_id is not None:
            query = query.where(MaintenanceSchedule.equipment_id == equipment_id)
        if is_active is not None:
            query = query.where(MaintenanceSchedule.is_active.is_(is_active))
        query = self.apply_search(query, search, [MaintenanceSchedule.title])
        query = self.apply_ordering(
            query,
            params.sort,
            SORTABLE,
            default=(MaintenanceSchedule.next_due_at.asc(), MaintenanceSchedule.id),
        )
        return await self.paginate(
            query, page=params.page, size=params.size, offset=params.offset
        )

    async def list_due_for_reminder(self, now: datetime) -> list[MaintenanceSchedule]:
        """Active plans whose reminder window has opened and not yet been sent.

        A reminder is due once `now >= next_due_at - remind_days_before days`.
        `last_reminded_at` is compared with the window start so each cycle is
        reminded once, and a rescheduled plan (new `next_due_at`) is reminded again.
        """
        window_start = MaintenanceSchedule.next_due_at - (
            func.make_interval(0, 0, 0, MaintenanceSchedule.remind_days_before)
        )
        result = await self.session.execute(
            self._query()
            .where(
                MaintenanceSchedule.is_active.is_(True),
                window_start <= now,
                or_(
                    MaintenanceSchedule.last_reminded_at.is_(None),
                    and_(MaintenanceSchedule.last_reminded_at < window_start),
                ),
            )
            .order_by(MaintenanceSchedule.next_due_at)
        )
        return list(result.scalars().all())

    @staticmethod
    def next_due_after(base: datetime, interval_days: int) -> datetime:
        return base + timedelta(days=interval_days)
