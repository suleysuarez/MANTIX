"""KPI, trend and alert aggregates behind the operational dashboard.

Extends `DashboardRepository`: every figure is one grouped query, computed in
the database. All ticket figures accept `technician_id` with the same scoping
rule as the base class, and cancelled tickets never count.
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import and_, case, func, literal, or_, select

from app.models.equipment import Equipment, EquipmentStatusHistory
from app.models.maintenance import (
    MaintenanceRequest,
    TicketAssignment,
    TicketStatusHistory,
)
from app.models.priority import Priority
from app.models.schedule import MaintenanceSchedule
from app.repositories.dashboard import OPEN_STATUSES, DashboardRepository

#: A ticket is "at risk" once this share of its SLA time is left.
SLA_AT_RISK_SHARE = 0.2
#: Statuses that mean a piece of equipment is down (not just retired on purpose).
DOWN_STATUSES = ("in_repair", "lost")
#: Equipment counted as operational for the fleet availability figure.
OPERATIONAL_STATUSES = ("assigned", "in_storage")

_RESOLUTION_SECONDS = func.extract(
    "epoch", MaintenanceRequest.resolved_at - MaintenanceRequest.created_at
)


@dataclass(frozen=True, slots=True)
class WindowStats:
    """Ticket aggregates for one `[start, end)` window.

    Created tickets (`created`, `resolved_of_created`, first assignment) are
    counted by creation date; everything else by resolution date.
    """

    created: int
    resolved_of_created: int
    resolved: int
    avg_resolution_hours: float | None
    median_resolution_hours: float | None
    p90_resolution_hours: float | None
    min_resolution_hours: float | None
    max_resolution_hours: float | None
    stddev_resolution_hours: float | None
    sla_met: int
    sla_missed: int
    sla_excluded: int
    avg_first_assignment_hours: float | None
    first_assignment_count: int


@dataclass(frozen=True, slots=True)
class BacklogRow:
    open: int
    age_0_2: int
    age_3_7: int
    age_over_7: int


@dataclass(frozen=True, slots=True)
class BucketRow:
    bucket: datetime
    created: int
    resolved: int
    avg_resolution_hours: float | None
    sla_met: int
    sla_missed: int


@dataclass(frozen=True, slots=True)
class TicketAlertRow:
    id: int
    ticket_number: str
    title: str
    equipment_id: int
    asset_tag: str
    priority: str
    status: str
    assigned: bool
    sla_deadline: datetime | None


@dataclass(frozen=True, slots=True)
class DownEquipmentRow:
    equipment_id: int
    asset_tag: str
    brand: str
    model: str
    status: str
    down_since: datetime | None


@dataclass(frozen=True, slots=True)
class ScheduleAlertRow:
    id: int
    equipment_id: int
    asset_tag: str
    title: str
    next_due_at: datetime


def _resolved_in(start: datetime, end: datetime) -> Any:
    mr = MaintenanceRequest
    return and_(
        mr.resolved_at.is_not(None),
        mr.resolved_at >= start,
        mr.resolved_at < end,
        mr.status != "cancelled",
    )


def _sla_outcomes(start: datetime, end: datetime) -> tuple[Any, Any, Any]:
    """SLA met / missed / excluded among tickets resolved in the window.

    A priority without `sla_hours` is neither met nor missed: it is excluded.
    """
    resolved = _resolved_in(start, end)
    allowed = Priority.sla_hours * 3600
    has_sla = Priority.sla_hours.is_not(None)
    return (
        and_(resolved, has_sla, _RESOLUTION_SECONDS <= allowed),
        and_(resolved, has_sla, _RESOLUTION_SECONDS > allowed),
        and_(resolved, Priority.sla_hours.is_(None)),
    )


def _hours(value: Any) -> float | None:
    return float(value) if value is not None else None


class DashboardKpiRepository(DashboardRepository):
    async def window_stats(
        self, *, start: datetime, end: datetime, technician_id: int | None = None
    ) -> WindowStats:
        mr = MaintenanceRequest
        first = (
            select(
                TicketAssignment.request_id.label("request_id"),
                func.min(TicketAssignment.assigned_at).label("first_at"),
            )
            .group_by(TicketAssignment.request_id)
            .subquery("first_assignment")
        )
        resolved = _resolved_in(start, end)
        met, missed, excluded = _sla_outcomes(start, end)
        created = and_(
            mr.created_at >= start, mr.created_at < end, mr.status != "cancelled"
        )
        assigned = and_(created, first.c.first_at.is_not(None))
        first_seconds = func.extract("epoch", first.c.first_at - mr.created_at)
        query = (
            select(
                func.count().filter(created),
                func.count().filter(and_(created, mr.resolved_at.is_not(None))),
                func.count().filter(resolved),
                func.avg(_RESOLUTION_SECONDS).filter(resolved) / 3600,
                func.percentile_cont(0.5)
                .within_group(_RESOLUTION_SECONDS)
                .filter(resolved)
                / 3600,
                func.percentile_cont(0.9)
                .within_group(_RESOLUTION_SECONDS)
                .filter(resolved)
                / 3600,
                func.min(_RESOLUTION_SECONDS).filter(resolved) / 3600,
                func.max(_RESOLUTION_SECONDS).filter(resolved) / 3600,
                func.stddev_samp(_RESOLUTION_SECONDS).filter(resolved) / 3600,
                func.count().filter(met),
                func.count().filter(missed),
                func.count().filter(excluded),
                func.avg(first_seconds).filter(assigned) / 3600,
                func.count().filter(assigned),
            )
            .select_from(mr)
            .join(Priority, Priority.code == mr.priority)
            .outerjoin(first, first.c.request_id == mr.id)
            .where(or_(created, resolved))
        )
        row = (await self.session.execute(self._scope(query, technician_id))).one()
        return WindowStats(
            created=row[0],
            resolved_of_created=row[1],
            resolved=row[2],
            avg_resolution_hours=_hours(row[3]),
            median_resolution_hours=_hours(row[4]),
            p90_resolution_hours=_hours(row[5]),
            min_resolution_hours=_hours(row[6]),
            max_resolution_hours=_hours(row[7]),
            stddev_resolution_hours=_hours(row[8]),
            sla_met=row[9],
            sla_missed=row[10],
            sla_excluded=row[11],
            avg_first_assignment_hours=_hours(row[12]),
            first_assignment_count=row[13],
        )

    async def open_tickets_at(
        self, at: datetime, *, technician_id: int | None = None
    ) -> int:
        """Tickets that were open at `at`: created by then, not yet resolved and not
        cancelled (a cancellation is read from the status history)."""
        mr = MaintenanceRequest
        cancelled = (
            select(literal(1))
            .where(
                TicketStatusHistory.request_id == mr.id,
                TicketStatusHistory.to_status == "cancelled",
                TicketStatusHistory.changed_at <= at,
            )
            .exists()
        )
        query = (
            select(func.count())
            .select_from(mr)
            .where(
                mr.created_at <= at,
                or_(mr.resolved_at.is_(None), mr.resolved_at > at),
                mr.status != "cancelled",
                ~cancelled,
            )
        )
        return int(
            (await self.session.execute(self._scope(query, technician_id))).scalar_one()
        )

    async def availability_at(self, at: datetime) -> tuple[int, int]:
        """(operational, total) equipment as of `at`, rebuilt from the status history.

        Status at `at` is the last change at or before it; with none, the status the
        first later change moved away from; with no history at all, the current one.
        Equipment created after `at` is left out.
        """
        history = EquipmentStatusHistory
        before = (
            select(history.to_status)
            .where(history.equipment_id == Equipment.id, history.changed_at <= at)
            .order_by(history.changed_at.desc(), history.id.desc())
            .limit(1)
            .scalar_subquery()
        )
        after = (
            select(history.from_status)
            .where(history.equipment_id == Equipment.id, history.changed_at > at)
            .order_by(history.changed_at.asc(), history.id.asc())
            .limit(1)
            .scalar_subquery()
        )
        status = func.coalesce(before, after, Equipment.status)
        row = (
            await self.session.execute(
                select(
                    func.count().filter(status.in_(OPERATIONAL_STATUSES)),
                    func.count(),
                ).where(Equipment.created_at <= at)
            )
        ).one()
        return int(row[0]), int(row[1])

    async def backlog(
        self, now: datetime, *, technician_id: int | None = None
    ) -> BacklogRow:
        """Open tickets by age: 0-2 days, 3-7 days and more than 7 days."""
        mr = MaintenanceRequest
        open_ = mr.status.in_(OPEN_STATUSES)
        query = select(
            func.count().filter(open_),
            func.count().filter(and_(open_, mr.created_at > now - timedelta(days=3))),
            func.count().filter(
                and_(
                    open_,
                    mr.created_at <= now - timedelta(days=3),
                    mr.created_at > now - timedelta(days=8),
                )
            ),
            func.count().filter(and_(open_, mr.created_at <= now - timedelta(days=8))),
        ).select_from(mr)
        row = (await self.session.execute(self._scope(query, technician_id))).one()
        return BacklogRow(
            open=row[0], age_0_2=row[1], age_3_7=row[2], age_over_7=row[3]
        )

    async def trend_buckets(
        self,
        *,
        start: datetime,
        end: datetime,
        unit: str,
        technician_id: int | None = None,
    ) -> list[BucketRow]:
        """Created tickets per bucket of creation date plus resolution figures per
        bucket of resolution date, merged into one row per bucket with activity."""
        mr = MaintenanceRequest
        met, missed, _ = _sla_outcomes(start, end)
        created_bucket = func.date_trunc(unit, mr.created_at, "UTC")
        resolved_bucket = func.date_trunc(unit, mr.resolved_at, "UTC")
        created_query = self._scope(
            select(created_bucket, func.count())
            .where(
                mr.created_at >= start, mr.created_at < end, mr.status != "cancelled"
            )
            .group_by(created_bucket),
            technician_id,
        )
        resolved_query = self._scope(
            select(
                resolved_bucket,
                func.count(),
                func.avg(_RESOLUTION_SECONDS) / 3600,
                func.count().filter(met),
                func.count().filter(missed),
            )
            .select_from(mr)
            .join(Priority, Priority.code == mr.priority)
            .where(_resolved_in(start, end))
            .group_by(resolved_bucket),
            technician_id,
        )
        created = {
            r[0]: r[1] for r in (await self.session.execute(created_query)).all()
        }
        done = {r[0]: r for r in (await self.session.execute(resolved_query)).all()}
        return [
            BucketRow(
                bucket=bucket,
                created=created.get(bucket, 0),
                resolved=done[bucket][1] if bucket in done else 0,
                avg_resolution_hours=_hours(done[bucket][2])
                if bucket in done
                else None,
                sla_met=done[bucket][3] if bucket in done else 0,
                sla_missed=done[bucket][4] if bucket in done else 0,
            )
            for bucket in sorted(created.keys() | done.keys())
        ]

    async def ticket_alerts(
        self, now: datetime, *, limit: int = 10, technician_id: int | None = None
    ) -> list[TicketAlertRow]:
        """Open tickets that are critical and unassigned, or whose SLA is breached or
        has `SLA_AT_RISK_SHARE` of its time left. Earliest deadline first."""
        mr = MaintenanceRequest
        deadline = mr.created_at + func.make_interval(0, 0, 0, 0, Priority.sla_hours)
        one_hour = func.make_interval(0, 0, 0, 0, 1)
        at_risk_from = (
            mr.created_at + (Priority.sla_hours * (1 - SLA_AT_RISK_SHARE)) * one_hour
        )
        assigned = (
            select(literal(1))
            .where(
                TicketAssignment.request_id == mr.id,
                TicketAssignment.unassigned_at.is_(None),
            )
            .exists()
        )
        query = (
            select(
                mr.id,
                mr.ticket_number,
                mr.title,
                Equipment.id,
                Equipment.asset_tag,
                mr.priority,
                mr.status,
                assigned,
                case((Priority.sla_hours.is_not(None), deadline), else_=None),
            )
            .join(Priority, Priority.code == mr.priority)
            .join(Equipment, Equipment.id == mr.equipment_id)
            .where(
                mr.status.in_(OPEN_STATUSES),
                or_(
                    and_(mr.priority == "critical", ~assigned),
                    and_(Priority.sla_hours.is_not(None), at_risk_from <= now),
                ),
            )
            .order_by(deadline.asc().nulls_last(), mr.created_at)
            .limit(limit)
        )
        rows = (await self.session.execute(self._scope(query, technician_id))).all()
        return [
            TicketAlertRow(
                id=r[0],
                ticket_number=r[1],
                title=r[2],
                equipment_id=r[3],
                asset_tag=r[4],
                priority=r[5],
                status=r[6],
                assigned=bool(r[7]),
                sla_deadline=r[8],
            )
            for r in rows
        ]

    async def down_equipment(self, *, limit: int = 10) -> list[DownEquipmentRow]:
        """Equipment that is down, with when it entered its current status."""
        history = EquipmentStatusHistory
        since = (
            select(func.max(history.changed_at))
            .where(
                history.equipment_id == Equipment.id,
                history.to_status == Equipment.status,
            )
            .scalar_subquery()
        )
        rows = (
            await self.session.execute(
                select(
                    Equipment.id,
                    Equipment.asset_tag,
                    Equipment.brand,
                    Equipment.model,
                    Equipment.status,
                    since,
                )
                .where(Equipment.status.in_(DOWN_STATUSES))
                .order_by(since.asc().nulls_last(), Equipment.asset_tag)
                .limit(limit)
            )
        ).all()
        return [DownEquipmentRow(*row) for row in rows]

    async def schedule_alerts(
        self,
        now: datetime,
        *,
        within_days: int = 7,
        limit: int = 10,
        technician_id: int | None = None,
    ) -> list[ScheduleAlertRow]:
        """Active preventive plans already overdue or due within `within_days`."""
        query = (
            select(
                MaintenanceSchedule.id,
                Equipment.id,
                Equipment.asset_tag,
                MaintenanceSchedule.title,
                MaintenanceSchedule.next_due_at,
            )
            .join(Equipment, Equipment.id == MaintenanceSchedule.equipment_id)
            .where(
                MaintenanceSchedule.is_active.is_(True),
                MaintenanceSchedule.next_due_at <= now + timedelta(days=within_days),
            )
            .order_by(MaintenanceSchedule.next_due_at)
            .limit(limit)
        )
        if technician_id is not None:
            query = query.where(MaintenanceSchedule.technician_id == technician_id)
        rows = (await self.session.execute(query)).all()
        return [ScheduleAlertRow(*row) for row in rows]
