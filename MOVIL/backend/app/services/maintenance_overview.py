from datetime import UTC, datetime, timedelta
from decimal import Decimal

from app.core.authz import AuthContext
from app.core.exceptions import UnprocessableError
from app.core.scope import ScopeKind
from app.repositories.maintenance_overview import (
    DurationRow,
    MaintenanceOverviewRepository,
    MixRow,
    WeekRow,
)
from app.schemas.dashboard import Period
from app.schemas.maintenance_overview import (
    CalendarEvent,
    CalendarResponse,
    CostSummary,
    DurationComparison,
    MaintenanceOverview,
    PlanCompliance,
    Reschedules,
    Upcoming,
    WeekCompliance,
    WorkMix,
)
from app.services.dashboard_kpis import (
    MIN_SAMPLE,
    change_pct,
    period_window,
    previous_window,
)

#: Longest calendar range one request may ask for, and the cap on its events.
MAX_CALENDAR_DAYS = 62
MAX_CALENDAR_EVENTS = 1500
_PLAN_LIMIT = 500
#: Matches no technician: a person who sees only assigned work but has no technician profile.
_NO_TECHNICIAN = -1
_MAX_OCCURRENCES_PER_PLAN = 100


def _pct(part: int, whole: int) -> float | None:
    return round(part / whole * 100, 1) if whole else None


def _round(value: float | None) -> float | None:
    return round(value, 2) if value is not None else None


def _low(n: int) -> bool:
    return 0 < n < MIN_SAMPLE


def _variance(row: DurationRow) -> float | None:
    if row.avg_actual is None or not row.avg_estimated:
        return None
    return round((row.avg_actual - row.avg_estimated) / row.avg_estimated * 100, 1)


class MaintenanceOverviewService:
    """Metrics and calendar for the Maintenance screen."""

    def __init__(self, repository: MaintenanceOverviewRepository):
        self.repository = repository

    async def technician_scope(self, actor: AuthContext) -> int | None:
        """`None` for whoever sees all the work; otherwise the technician whose work it is
        (an id that matches nothing when the person has no technician profile)."""
        if actor.scope_kind("tickets") is not ScopeKind.ASSIGNED:
            return None
        found = await self.repository.technician_id_for_user(actor.id)
        return found if found is not None else _NO_TECHNICIAN

    async def overview(
        self,
        *,
        period: Period,
        now: datetime | None = None,
        technician_id: int | None = None,
    ) -> MaintenanceOverview:
        now = now or datetime.now(UTC)
        start, end = period_window(period, now)
        prev_start, prev_end = previous_window(period, start, end)
        repo = self.repository
        upcoming = await repo.upcoming(now, technician_id)
        return MaintenanceOverview(
            generated_at=now,
            period=period,
            window_start=start,
            window_end=end,
            mix=self._mix(
                await repo.work_mix(start=start, end=end, technician_id=technician_id),
                await repo.work_mix(
                    start=prev_start, end=prev_end, technician_id=technician_id
                ),
            ),
            upcoming=Upcoming(
                overdue=upcoming.overdue,
                next_7_days=upcoming.next_7,
                next_30_days=upcoming.next_30,
            ),
            compliance=self._compliance(
                await repo.compliance_weeks(
                    start=start, end=end, now=now, technician_id=technician_id
                ),
                await repo.compliance_weeks(
                    start=prev_start, end=prev_end, now=now, technician_id=technician_id
                ),
            ),
            duration=self._duration(
                await repo.durations(start=start, end=end, technician_id=technician_id),
                await repo.durations(
                    start=prev_start, end=prev_end, technician_id=technician_id
                ),
            ),
            cost=await self._cost(start, end, prev_start, prev_end, technician_id),
            reschedules=await self._reschedules(
                start, end, prev_start, prev_end, technician_id
            ),
        )

    @staticmethod
    def _mix(current: MixRow, previous: MixRow) -> WorkMix:
        total = current.preventive + current.corrective + current.other
        before = previous.preventive + previous.corrective + previous.other
        share = _pct(current.preventive, total)
        previous_share = _pct(previous.preventive, before)
        return WorkMix(
            preventive=current.preventive,
            corrective=current.corrective,
            other=current.other,
            sample_size=total,
            low_sample=_low(total),
            preventive_pct=share,
            previous_preventive_pct=previous_share,
            change_pct=change_pct(share, previous_share),
        )

    @staticmethod
    def _compliance(current: list[WeekRow], previous: list[WeekRow]) -> PlanCompliance:
        planned = sum(w.planned for w in current)
        on_time = sum(w.on_time for w in current)
        rate = _pct(on_time, planned)
        previous_rate = _pct(
            sum(w.on_time for w in previous), sum(w.planned for w in previous)
        )
        return PlanCompliance(
            weeks=[
                WeekCompliance(
                    week_start=w.week_start,
                    planned=w.planned,
                    on_time=w.on_time,
                    compliance_pct=_pct(w.on_time, w.planned),
                )
                for w in current
            ],
            planned=planned,
            on_time=on_time,
            sample_size=planned,
            low_sample=_low(planned),
            compliance_pct=rate,
            previous_compliance_pct=previous_rate,
            change_pct=change_pct(rate, previous_rate),
        )

    @staticmethod
    def _duration(current: DurationRow, previous: DurationRow) -> DurationComparison:
        return DurationComparison(
            average_actual_hours=_round(current.avg_actual),
            average_estimated_hours=_round(current.avg_estimated),
            variance_pct=_variance(current),
            previous_variance_pct=_variance(previous),
            sample_size=current.count,
            low_sample=_low(current.count),
        )

    async def _cost(
        self,
        start: datetime,
        end: datetime,
        prev_start: datetime,
        prev_end: datetime,
        technician_id: int | None,
    ) -> CostSummary:
        current = await self.repository.costs(
            start=start, end=end, technician_id=technician_id
        )
        previous = await self.repository.costs(
            start=prev_start, end=prev_end, technician_id=technician_id
        )
        average = (
            (current.total / current.with_cost).quantize(Decimal("0.01"))
            if current.with_cost
            else None
        )
        return CostSummary(
            total=current.total.quantize(Decimal("0.01")),
            previous_total=previous.total.quantize(Decimal("0.01")),
            change_pct=change_pct(float(current.total), float(previous.total)),
            records_with_cost=current.with_cost,
            average_per_record=average,
            low_sample=_low(current.with_cost),
        )

    async def _reschedules(
        self,
        start: datetime,
        end: datetime,
        prev_start: datetime,
        prev_end: datetime,
        technician_id: int | None,
    ) -> Reschedules:
        count = await self.repository.reschedules(
            start=start, end=end, technician_id=technician_id
        )
        before = await self.repository.reschedules(
            start=prev_start, end=prev_end, technician_id=technician_id
        )
        return Reschedules(
            count=count,
            previous=before,
            change_pct=change_pct(float(count), float(before)),
        )

    async def calendar(
        self,
        *,
        start: datetime,
        end: datetime,
        now: datetime | None = None,
        technician_id: int | None = None,
    ) -> CalendarResponse:
        """Occurrences of the active plans in `[start, end)` plus the services already done.

        Plans only store their next date, so later occurrences are projected one
        interval apart. A plan that is already overdue shows its overdue date and
        then continues from today, as completing it would.
        """
        now = now or datetime.now(UTC)
        if end <= start:
            raise UnprocessableError("the end of the range must be after its start")
        if end - start > timedelta(days=MAX_CALENDAR_DAYS):
            raise UnprocessableError(
                f"the range cannot exceed {MAX_CALENDAR_DAYS} days"
            )
        events: list[CalendarEvent] = []
        for plan in await self.repository.plans_due_before(
            end, limit=_PLAN_LIMIT, technician_id=technician_id
        ):
            due = plan.next_due_at
            first = True
            for _ in range(_MAX_OCCURRENCES_PER_PLAN):
                if due >= end:
                    break
                if due >= start:
                    events.append(
                        CalendarEvent(
                            kind="overdue" if first and due < now else "planned",
                            schedule_id=plan.schedule_id,
                            title=plan.title,
                            equipment_id=plan.equipment_id,
                            asset_tag=plan.asset_tag,
                            technician=plan.technician,
                            at=due,
                            completed_at=None,
                            on_time=None,
                        )
                    )
                base = max(now, due) if first else due
                due = base + timedelta(days=plan.interval_days)
                first = False
        for run in await self.repository.runs_between(
            start, end, limit=MAX_CALENDAR_EVENTS, technician_id=technician_id
        ):
            events.append(
                CalendarEvent(
                    kind="done",
                    schedule_id=run.schedule_id,
                    title=run.title,
                    equipment_id=run.equipment_id,
                    asset_tag=run.asset_tag,
                    technician=run.technician,
                    at=run.due_at,
                    completed_at=run.completed_at,
                    on_time=run.completed_at <= run.due_at,
                )
            )
        events.sort(key=lambda event: (event.at, event.schedule_id))
        return CalendarResponse(
            generated_at=now,
            start=start,
            end=end,
            truncated=len(events) > MAX_CALENDAR_EVENTS,
            events=events[:MAX_CALENDAR_EVENTS],
        )
