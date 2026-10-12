from datetime import datetime, timedelta

from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import selectinload

from app.models.schedule import MaintenanceSchedule
from app.repositories.base import BaseRepository, Page

SORTABLE = {
    "next_due_at": MaintenanceSchedule.next_due_at,
    "title": MaintenanceSchedule.title,
    "created_at": MaintenanceSchedule.created_at,
    "id": MaintenanceSchedule.id,
}


class ScheduleRepository(BaseRepository[MaintenanceSchedule]):
    model = MaintenanceSchedule

    @staticmethod
    def _query():
        return select(MaintenanceSchedule).options(
            selectinload(MaintenanceSchedule.equipment),
            selectinload(MaintenanceSchedule.technician),
        )

    async def get(self, entity_id: int) -> MaintenanceSchedule | None:
        result = await self.session.execute(
            self._query().where(MaintenanceSchedule.id == entity_id)
        )
        return result.scalar_one_or_none()

    async def search(
        self,
        *,
        equipment_id: int | None = None,
        is_active: bool | None = None,
        search: str | None = None,
        sort: str | None = None,
        page: int = 1,
        size: int = 20,
    ) -> Page[MaintenanceSchedule]:
        query = self._query()
        if equipment_id is not None:
            query = query.where(MaintenanceSchedule.equipment_id == equipment_id)
        if is_active is not None:
            query = query.where(MaintenanceSchedule.is_active.is_(is_active))
        query = self.apply_search(query, search, [MaintenanceSchedule.title])
        query = self.apply_ordering(
            query,
            sort,
            SORTABLE,
            default=(MaintenanceSchedule.next_due_at.asc(), MaintenanceSchedule.id),
        )
        return await self.paginate(query, page=page, size=size)

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
