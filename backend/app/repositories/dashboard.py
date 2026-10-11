"""Read-only aggregate queries behind the operational dashboard.

Every method takes an optional `technician_id`: when set, ticket aggregates
only consider tickets that technician has ever been assigned to (used to give
technicians a view scoped to their own work).
"""

from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import Select, and_, case, func, null, select

from app.models.auth import User
from app.models.equipment import Equipment
from app.models.maintenance import MaintenanceRequest, TicketAssignment
from app.models.priority import Priority
from app.models.technician import Technician
from app.repositories.base import BaseRepository

#: Statuses in which a ticket still needs work.
OPEN_STATUSES = ("submitted", "triaged", "assigned", "in_progress", "waiting")

_RESOLUTION_SECONDS = func.extract(
    "epoch", MaintenanceRequest.resolved_at - MaintenanceRequest.created_at
)


@dataclass(frozen=True, slots=True)
class CountRow:
    key: str
    count: int


@dataclass(frozen=True, slots=True)
class ResolutionStats:
    key: str | None
    resolved_count: int
    avg_hours: float | None
    median_hours: float | None


@dataclass(frozen=True, slots=True)
class WorkloadRow:
    technician_id: int
    full_name: str
    is_available: bool
    open_tickets: int
    resolved_in_window: int


@dataclass(frozen=True, slots=True)
class FailingEquipmentRow:
    equipment_id: int
    asset_tag: str
    brand: str
    model: str
    tickets: int
    last_ticket_at: datetime | None


class DashboardRepository(BaseRepository[MaintenanceRequest]):
    model = MaintenanceRequest

    @staticmethod
    def _scope(query: Select, technician_id: int | None) -> Select:
        if technician_id is None:
            return query
        return query.where(
            MaintenanceRequest.ticket_assignments.any(
                TicketAssignment.technician_id == technician_id
            )
        )

    async def tickets_by_status(
        self, *, technician_id: int | None = None
    ) -> list[CountRow]:
        query = self._scope(
            select(MaintenanceRequest.status, func.count()).group_by(
                MaintenanceRequest.status
            ),
            technician_id,
        ).order_by(MaintenanceRequest.status)
        rows = (await self.session.execute(query)).all()
        return [CountRow(key=row[0], count=row[1]) for row in rows]

    async def tickets_by_priority(
        self, *, technician_id: int | None = None
    ) -> list[CountRow]:
        """Open tickets per priority, most urgent first."""
        query = self._scope(
            select(MaintenanceRequest.priority, func.count())
            .join(Priority, Priority.code == MaintenanceRequest.priority)
            .where(MaintenanceRequest.status.in_(OPEN_STATUSES))
            .group_by(MaintenanceRequest.priority, Priority.level)
            .order_by(Priority.level.desc()),
            technician_id,
        )
        rows = (await self.session.execute(query)).all()
        return [CountRow(key=row[0], count=row[1]) for row in rows]

    async def count_overdue(
        self, now: datetime, *, technician_id: int | None = None
    ) -> int:
        """Open tickets older than their priority's SLA."""
        deadline = MaintenanceRequest.created_at + (
            func.make_interval(0, 0, 0, 0, Priority.sla_hours)
        )
        query = self._scope(
            select(func.count())
            .select_from(MaintenanceRequest)
            .join(Priority, Priority.code == MaintenanceRequest.priority)
            .where(
                MaintenanceRequest.status.in_(OPEN_STATUSES),
                Priority.sla_hours.is_not(None),
                deadline < now,
            ),
            technician_id,
        )
        return int((await self.session.execute(query)).scalar_one())

    async def equipment_by_status(self) -> list[CountRow]:
        rows = (
            await self.session.execute(
                select(Equipment.status, func.count())
                .group_by(Equipment.status)
                .order_by(Equipment.status)
            )
        ).all()
        return [CountRow(key=row[0], count=row[1]) for row in rows]

    async def resolution_stats(
        self,
        *,
        date_from: datetime,
        by_priority: bool = False,
        technician_id: int | None = None,
    ) -> list[ResolutionStats]:
        """Mean and median hours from creation to resolution, for tickets resolved
        since `date_from`. One overall row, or one row per priority."""
        key = MaintenanceRequest.priority if by_priority else null()
        query = select(
            key,
            func.count(),
            func.avg(_RESOLUTION_SECONDS) / 3600,
            func.percentile_cont(0.5).within_group(_RESOLUTION_SECONDS) / 3600,
        ).where(
            MaintenanceRequest.resolved_at.is_not(None),
            MaintenanceRequest.resolved_at >= date_from,
        )
        if by_priority:
            query = query.join(
                Priority, Priority.code == MaintenanceRequest.priority
            ).group_by(MaintenanceRequest.priority, Priority.level)
            query = query.order_by(Priority.level.desc())
        query = self._scope(query, technician_id)
        rows = (await self.session.execute(query)).all()
        stats = [
            ResolutionStats(
                key=row[0],
                resolved_count=row[1],
                avg_hours=float(row[2]) if row[2] is not None else None,
                median_hours=float(row[3]) if row[3] is not None else None,
            )
            for row in rows
        ]
        return [item for item in stats if item.resolved_count > 0] or (
            [] if by_priority else [ResolutionStats(None, 0, None, None)]
        )

    async def technician_workload(
        self, *, date_from: datetime, technician_id: int | None = None
    ) -> list[WorkloadRow]:
        open_count = func.count(
            func.distinct(
                case(
                    (
                        and_(
                            TicketAssignment.unassigned_at.is_(None),
                            MaintenanceRequest.status.in_(OPEN_STATUSES),
                        ),
                        MaintenanceRequest.id,
                    )
                )
            )
        )
        resolved_count = func.count(
            func.distinct(
                case(
                    (
                        and_(
                            MaintenanceRequest.resolved_at.is_not(None),
                            MaintenanceRequest.resolved_at >= date_from,
                        ),
                        MaintenanceRequest.id,
                    )
                )
            )
        )
        query = (
            select(
                Technician.id,
                User.full_name,
                Technician.is_available,
                open_count,
                resolved_count,
            )
            .join(User, User.id == Technician.user_id)
            .outerjoin(
                TicketAssignment, TicketAssignment.technician_id == Technician.id
            )
            .outerjoin(
                MaintenanceRequest, MaintenanceRequest.id == TicketAssignment.request_id
            )
            .group_by(Technician.id, User.full_name, Technician.is_available)
            .order_by(open_count.desc(), User.full_name)
        )
        if technician_id is not None:
            query = query.where(Technician.id == technician_id)
        rows = (await self.session.execute(query)).all()
        return [
            WorkloadRow(
                technician_id=row[0],
                full_name=row[1],
                is_available=row[2],
                open_tickets=row[3],
                resolved_in_window=row[4],
            )
            for row in rows
        ]

    async def top_failing_equipment(
        self, *, date_from: datetime, limit: int
    ) -> list[FailingEquipmentRow]:
        tickets = func.count(MaintenanceRequest.id)
        rows = (
            await self.session.execute(
                select(
                    Equipment.id,
                    Equipment.asset_tag,
                    Equipment.brand,
                    Equipment.model,
                    tickets,
                    func.max(MaintenanceRequest.created_at),
                )
                .join(
                    MaintenanceRequest, MaintenanceRequest.equipment_id == Equipment.id
                )
                .where(MaintenanceRequest.created_at >= date_from)
                .group_by(Equipment.id)
                .order_by(tickets.desc(), Equipment.asset_tag)
                .limit(limit)
            )
        ).all()
        return [
            FailingEquipmentRow(
                equipment_id=row[0],
                asset_tag=row[1],
                brand=row[2],
                model=row[3],
                tickets=row[4],
                last_ticket_at=row[5],
            )
            for row in rows
        ]

    async def get_technician_id_for_user(self, user_id: int) -> int | None:
        result = await self.session.execute(
            select(Technician.id).where(Technician.user_id == user_id)
        )
        return result.scalar_one_or_none()
