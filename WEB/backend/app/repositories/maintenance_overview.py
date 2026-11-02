"""Aggregates behind the Maintenance screen: work mix, plan compliance, costs, calendar."""

from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import and_, func, select

from app.models.auth import User
from app.models.equipment import Equipment
from app.models.maintenance import MaintenanceRecord
from app.models.schedule import MaintenanceSchedule, ScheduleReschedule, ScheduleRun
from app.models.technician import Technician
from app.repositories.base import BaseRepository


@dataclass(frozen=True, slots=True)
class MixRow:
    preventive: int
    corrective: int
    other: int


@dataclass(frozen=True, slots=True)
class CostRow:
    total: Decimal
    with_cost: int


@dataclass(frozen=True, slots=True)
class WeekRow:
    week_start: datetime
    planned: int
    on_time: int


@dataclass(frozen=True, slots=True)
class DurationRow:
    avg_actual: float | None
    avg_estimated: float | None
    count: int


@dataclass(frozen=True, slots=True)
class UpcomingRow:
    overdue: int
    next_7: int
    next_30: int


@dataclass(frozen=True, slots=True)
class PlanRow:
    schedule_id: int
    title: str
    equipment_id: int
    asset_tag: str
    technician: str | None
    next_due_at: datetime
    interval_days: int


@dataclass(frozen=True, slots=True)
class DoneRow:
    schedule_id: int
    title: str
    equipment_id: int
    asset_tag: str
    technician: str | None
    due_at: datetime
    completed_at: datetime


def _float(value: Any) -> float | None:
    return float(value) if value is not None else None


def _mine(column: Any, technician_id: int | None) -> list[Any]:
    """Restrict to one technician's work; no technician means no restriction."""
    return [] if technician_id is None else [column == technician_id]


class MaintenanceOverviewRepository(BaseRepository[MaintenanceRecord]):
    model = MaintenanceRecord

    async def technician_id_for_user(self, user_id: int) -> int | None:
        return (
            await self.session.execute(
                select(Technician.id).where(Technician.user_id == user_id)
            )
        ).scalar_one_or_none()

    async def work_mix(
        self, *, start: datetime, end: datetime, technician_id: int | None = None
    ) -> MixRow:
        """Records started in `[start, end)` split into preventive, corrective, other."""
        record = MaintenanceRecord
        in_window = and_(record.started_at >= start, record.started_at < end)
        row = (
            await self.session.execute(
                select(
                    func.count().filter(record.work_type == "preventive"),
                    func.count().filter(record.work_type == "corrective"),
                    func.count().filter(
                        record.work_type.not_in(("preventive", "corrective"))
                    ),
                ).where(in_window, *_mine(record.technician_id, technician_id))
            )
        ).one()
        return MixRow(preventive=row[0], corrective=row[1], other=row[2])

    async def costs(
        self, *, start: datetime, end: datetime, technician_id: int | None = None
    ) -> CostRow:
        record = MaintenanceRecord
        row = (
            await self.session.execute(
                select(
                    func.coalesce(func.sum(record.total_cost), 0),
                    func.count().filter(record.total_cost > 0),
                ).where(
                    record.started_at >= start,
                    record.started_at < end,
                    *_mine(record.technician_id, technician_id),
                )
            )
        ).one()
        return CostRow(total=Decimal(row[0] or 0), with_cost=row[1])

    async def compliance_weeks(
        self,
        *,
        start: datetime,
        end: datetime,
        now: datetime,
        technician_id: int | None = None,
    ) -> list[WeekRow]:
        """Services due per week in the window: those already done (on time or late)
        plus the active plans whose due date passed without being done."""
        done_week = func.date_trunc("week", ScheduleRun.due_at, "UTC")
        done = (
            await self.session.execute(
                select(
                    done_week,
                    func.count(),
                    func.count().filter(ScheduleRun.completed_at <= ScheduleRun.due_at),
                )
                .join(
                    MaintenanceSchedule,
                    MaintenanceSchedule.id == ScheduleRun.schedule_id,
                )
                .where(
                    ScheduleRun.due_at >= start,
                    ScheduleRun.due_at < end,
                    *_mine(MaintenanceSchedule.technician_id, technician_id),
                )
                .group_by(done_week)
            )
        ).all()
        overdue_week = func.date_trunc("week", MaintenanceSchedule.next_due_at, "UTC")
        overdue = (
            await self.session.execute(
                select(overdue_week, func.count())
                .where(
                    MaintenanceSchedule.is_active.is_(True),
                    MaintenanceSchedule.next_due_at >= start,
                    MaintenanceSchedule.next_due_at < end,
                    MaintenanceSchedule.next_due_at < now,
                    *_mine(MaintenanceSchedule.technician_id, technician_id),
                )
                .group_by(overdue_week)
            )
        ).all()
        planned: dict[datetime, int] = {}
        on_time: dict[datetime, int] = {}
        for row in done:
            week: datetime = row[0]
            planned[week] = planned.get(week, 0) + int(row[1])
            on_time[week] = on_time.get(week, 0) + int(row[2])
        for row in overdue:
            late_week: datetime = row[0]
            planned[late_week] = planned.get(late_week, 0) + int(row[1])
        weeks: list[datetime] = sorted(planned)
        return [
            WeekRow(week_start=w, planned=planned[w], on_time=on_time.get(w, 0))
            for w in weeks
        ]

    async def durations(
        self, *, start: datetime, end: datetime, technician_id: int | None = None
    ) -> DurationRow:
        """Real vs estimated hours of services completed in the window that have both."""
        row = (
            await self.session.execute(
                select(
                    func.avg(ScheduleRun.actual_hours),
                    func.avg(MaintenanceSchedule.estimated_hours),
                    func.count(),
                )
                .join(
                    MaintenanceSchedule,
                    MaintenanceSchedule.id == ScheduleRun.schedule_id,
                )
                .where(
                    ScheduleRun.completed_at >= start,
                    ScheduleRun.completed_at < end,
                    ScheduleRun.actual_hours.is_not(None),
                    MaintenanceSchedule.estimated_hours.is_not(None),
                    *_mine(MaintenanceSchedule.technician_id, technician_id),
                )
            )
        ).one()
        return DurationRow(
            avg_actual=_float(row[0]), avg_estimated=_float(row[1]), count=row[2]
        )

    async def reschedules(
        self, *, start: datetime, end: datetime, technician_id: int | None = None
    ) -> int:
        row = (
            await self.session.execute(
                select(func.count())
                .select_from(ScheduleReschedule)
                .join(
                    MaintenanceSchedule,
                    MaintenanceSchedule.id == ScheduleReschedule.schedule_id,
                )
                .where(
                    ScheduleReschedule.changed_at >= start,
                    ScheduleReschedule.changed_at < end,
                    *_mine(MaintenanceSchedule.technician_id, technician_id),
                )
            )
        ).scalar_one()
        return int(row)

    async def upcoming(
        self, now: datetime, technician_id: int | None = None
    ) -> UpcomingRow:
        plan = MaintenanceSchedule
        active = plan.is_active.is_(True)
        row = (
            await self.session.execute(
                select(
                    func.count().filter(plan.next_due_at < now),
                    func.count().filter(
                        and_(
                            plan.next_due_at >= now,
                            plan.next_due_at < now + timedelta(days=7),
                        )
                    ),
                    func.count().filter(
                        and_(
                            plan.next_due_at >= now,
                            plan.next_due_at < now + timedelta(days=30),
                        )
                    ),
                ).where(active, *_mine(plan.technician_id, technician_id))
            )
        ).one()
        return UpcomingRow(overdue=row[0], next_7=row[1], next_30=row[2])

    async def plans_due_before(
        self, end: datetime, *, limit: int, technician_id: int | None = None
    ) -> list[PlanRow]:
        """Active plans whose next service is at or before `end` (projected by the caller)."""
        plan = MaintenanceSchedule
        rows = (
            await self.session.execute(
                select(
                    plan.id,
                    plan.title,
                    Equipment.id,
                    Equipment.asset_tag,
                    User.full_name,
                    plan.next_due_at,
                    plan.interval_days,
                )
                .join(Equipment, Equipment.id == plan.equipment_id)
                .outerjoin(Technician, Technician.id == plan.technician_id)
                .outerjoin(User, User.id == Technician.user_id)
                .where(
                    plan.is_active.is_(True),
                    plan.next_due_at < end,
                    *_mine(plan.technician_id, technician_id),
                )
                .order_by(plan.next_due_at)
                .limit(limit)
            )
        ).all()
        return [PlanRow(*row) for row in rows]

    async def runs_between(
        self,
        start: datetime,
        end: datetime,
        *,
        limit: int,
        technician_id: int | None = None,
    ) -> list[DoneRow]:
        rows = (
            await self.session.execute(
                select(
                    MaintenanceSchedule.id,
                    MaintenanceSchedule.title,
                    Equipment.id,
                    Equipment.asset_tag,
                    User.full_name,
                    ScheduleRun.due_at,
                    ScheduleRun.completed_at,
                )
                .join(
                    MaintenanceSchedule,
                    MaintenanceSchedule.id == ScheduleRun.schedule_id,
                )
                .join(Equipment, Equipment.id == MaintenanceSchedule.equipment_id)
                .outerjoin(
                    Technician, Technician.id == MaintenanceSchedule.technician_id
                )
                .outerjoin(User, User.id == Technician.user_id)
                .where(
                    ScheduleRun.due_at >= start,
                    ScheduleRun.due_at < end,
                    *_mine(MaintenanceSchedule.technician_id, technician_id),
                )
                .order_by(ScheduleRun.due_at)
                .limit(limit)
            )
        ).all()
        return [DoneRow(*row) for row in rows]
