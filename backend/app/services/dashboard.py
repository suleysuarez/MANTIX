from datetime import UTC, datetime, timedelta

from app.core.authz import AuthContext
from app.repositories.dashboard import (
    OPEN_STATUSES,
    CountRow,
    DashboardRepository,
    ResolutionStats,
)
from app.schemas.dashboard import (
    CountItem,
    DashboardSummary,
    FailingEquipment,
    FailingEquipmentResponse,
    ResolutionTime,
    ResolutionTimesResponse,
    Scope,
    TechnicianWorkload,
    TicketMetrics,
    WorkloadResponse,
)

#: Technician id that matches nothing, for a non-elevated user with no profile.
_NO_TECHNICIAN = 0


class DashboardService:
    """Operational metrics.

    Admins and supervisors see the whole operation; anyone else holding
    `dashboard.read` (technicians) sees only the tickets assigned to them.
    """

    def __init__(self, repository: DashboardRepository):
        self.repository = repository

    async def _scope(self, actor: AuthContext) -> tuple[int | None, Scope]:
        if actor.is_elevated:
            return None, "all"
        technician_id = await self.repository.get_technician_id_for_user(actor.id)
        return (technician_id if technician_id is not None else _NO_TECHNICIAN), "own"

    @staticmethod
    def _window(days: int, now: datetime) -> datetime:
        return now - timedelta(days=days)

    async def summary(
        self, actor: AuthContext, *, days: int, now: datetime | None = None
    ) -> DashboardSummary:
        now = now or datetime.now(UTC)
        technician_id, scope = await self._scope(actor)
        by_status = await self.repository.tickets_by_status(technician_id=technician_id)
        overall = (
            await self.repository.resolution_stats(
                date_from=self._window(days, now), technician_id=technician_id
            )
        )[0]
        return DashboardSummary(
            generated_at=now,
            scope=scope,
            window_days=days,
            tickets=TicketMetrics(
                total=sum(row.count for row in by_status),
                open=sum(row.count for row in by_status if row.key in OPEN_STATUSES),
                overdue=await self.repository.count_overdue(
                    now, technician_id=technician_id
                ),
                by_status=self._items(by_status),
                open_by_priority=self._items(
                    await self.repository.tickets_by_priority(
                        technician_id=technician_id
                    )
                ),
            ),
            equipment_by_status=self._items(
                await self.repository.equipment_by_status()
            ),
            resolution=self._resolution(overall),
        )

    async def workload(
        self, actor: AuthContext, *, days: int, now: datetime | None = None
    ) -> WorkloadResponse:
        now = now or datetime.now(UTC)
        technician_id, scope = await self._scope(actor)
        rows = await self.repository.technician_workload(
            date_from=self._window(days, now), technician_id=technician_id
        )
        return WorkloadResponse(
            window_days=days,
            scope=scope,
            technicians=[
                TechnicianWorkload(
                    technician_id=row.technician_id,
                    full_name=row.full_name,
                    is_available=row.is_available,
                    open_tickets=row.open_tickets,
                    resolved_in_window=row.resolved_in_window,
                )
                for row in rows
            ],
        )

    async def resolution_times(
        self, actor: AuthContext, *, days: int, now: datetime | None = None
    ) -> ResolutionTimesResponse:
        now = now or datetime.now(UTC)
        technician_id, scope = await self._scope(actor)
        date_from = self._window(days, now)
        overall = (
            await self.repository.resolution_stats(
                date_from=date_from, technician_id=technician_id
            )
        )[0]
        per_priority = await self.repository.resolution_stats(
            date_from=date_from, by_priority=True, technician_id=technician_id
        )
        return ResolutionTimesResponse(
            window_days=days,
            scope=scope,
            overall=self._resolution(overall),
            by_priority=[self._resolution(item) for item in per_priority],
        )

    async def top_failing_equipment(
        self, *, days: int, limit: int, now: datetime | None = None
    ) -> FailingEquipmentResponse:
        now = now or datetime.now(UTC)
        rows = await self.repository.top_failing_equipment(
            date_from=self._window(days, now), limit=limit
        )
        return FailingEquipmentResponse(
            window_days=days,
            equipment=[
                FailingEquipment(
                    equipment_id=row.equipment_id,
                    asset_tag=row.asset_tag,
                    brand=row.brand,
                    model=row.model,
                    tickets=row.tickets,
                    last_ticket_at=row.last_ticket_at,
                )
                for row in rows
            ],
        )

    @staticmethod
    def _items(rows: list[CountRow]) -> list[CountItem]:
        return [CountItem(key=row.key, count=row.count) for row in rows]

    @staticmethod
    def _resolution(stats: ResolutionStats) -> ResolutionTime:
        return ResolutionTime(
            priority=stats.key,
            resolved_count=stats.resolved_count,
            avg_hours=(
                round(stats.avg_hours, 2) if stats.avg_hours is not None else None
            ),
            median_hours=(
                round(stats.median_hours, 2) if stats.median_hours is not None else None
            ),
        )
