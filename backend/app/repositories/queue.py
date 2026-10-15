"""Aggregates behind the pending-requests queue (one grouped query each)."""

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, func, literal, select

from app.models.category import RequestCategory
from app.models.maintenance import MaintenanceRequest, TicketStatusHistory
from app.models.priority import Priority
from app.repositories.base import BaseRepository
from app.repositories.dashboard import CountRow

#: A request is pending until work starts on it.
PENDING_STATUSES = ("submitted", "triaged", "assigned")
#: Pending requests that no technician has picked up yet.
UNASSIGNED_STATUSES = ("submitted", "triaged")
UNCATEGORIZED = "uncategorized"


@dataclass(frozen=True, slots=True)
class WaitStats:
    pending: int
    unassigned: int
    oldest_hours: float | None
    median_hours: float | None


@dataclass(frozen=True, slots=True)
class DecisionStats:
    decisions: int
    rejected: int
    avg_triage_hours: float | None
    median_triage_hours: float | None


def _hours(value: Any) -> float | None:
    return float(value) if value is not None else None


class QueueRepository(BaseRepository[MaintenanceRequest]):
    model = MaintenanceRequest

    async def wait_stats(self, now: datetime) -> WaitStats:
        """Time in queue of the pending requests, measured at `now`."""
        mr = MaintenanceRequest
        waited = func.extract(
            "epoch", literal(now, DateTime(timezone=True)) - mr.created_at
        )
        row = (
            await self.session.execute(
                select(
                    func.count(),
                    func.count().filter(mr.status.in_(UNASSIGNED_STATUSES)),
                    func.max(waited) / 3600,
                    func.percentile_cont(0.5).within_group(waited) / 3600,
                ).where(mr.status.in_(PENDING_STATUSES))
            )
        ).one()
        return WaitStats(
            pending=row[0],
            unassigned=row[1],
            oldest_hours=_hours(row[2]),
            median_hours=_hours(row[3]),
        )

    async def pending_by_priority(self) -> list[CountRow]:
        mr = MaintenanceRequest
        rows = (
            await self.session.execute(
                select(mr.priority, func.count())
                .join(Priority, Priority.code == mr.priority)
                .where(mr.status.in_(PENDING_STATUSES))
                .group_by(mr.priority, Priority.level)
                .order_by(Priority.level.desc())
            )
        ).all()
        return [CountRow(key=row[0], count=row[1]) for row in rows]

    async def pending_by_category(self) -> list[CountRow]:
        mr = MaintenanceRequest
        category = func.coalesce(mr.category, UNCATEGORIZED)
        count = func.count()
        rows = (
            await self.session.execute(
                select(category, count)
                .where(mr.status.in_(PENDING_STATUSES))
                .group_by(category)
                .order_by(count.desc(), category)
            )
        ).all()
        return [CountRow(key=row[0], count=row[1]) for row in rows]

    async def decision_stats(self, *, start: datetime, end: datetime) -> DecisionStats:
        """Requests whose first exit from `submitted` happened in `[start, end)`.

        Each request is decided once: a later cancellation after triage is not a
        second decision. Time to triage is creation to that first exit.
        """
        history = TicketStatusHistory
        ranked = (
            select(
                history.request_id.label("request_id"),
                history.to_status.label("to_status"),
                history.changed_at.label("changed_at"),
                func.row_number()
                .over(
                    partition_by=history.request_id,
                    order_by=(history.changed_at, history.id),
                )
                .label("rn"),
            )
            .where(history.from_status == "submitted")
            .subquery("first_exit")
        )
        waited = func.extract(
            "epoch", ranked.c.changed_at - MaintenanceRequest.created_at
        )
        row = (
            await self.session.execute(
                select(
                    func.count(),
                    func.count().filter(ranked.c.to_status == "cancelled"),
                    func.avg(waited) / 3600,
                    func.percentile_cont(0.5).within_group(waited) / 3600,
                )
                .select_from(ranked)
                .join(MaintenanceRequest, MaintenanceRequest.id == ranked.c.request_id)
                .where(
                    ranked.c.rn == 1,
                    ranked.c.changed_at >= start,
                    ranked.c.changed_at < end,
                )
            )
        ).one()
        return DecisionStats(
            decisions=row[0],
            rejected=row[1],
            avg_triage_hours=_hours(row[2]),
            median_triage_hours=_hours(row[3]),
        )

    async def active_categories(self) -> list[RequestCategory]:
        result = await self.session.execute(
            select(RequestCategory)
            .where(RequestCategory.is_active.is_(True))
            .order_by(RequestCategory.name)
        )
        return list(result.scalars().all())
