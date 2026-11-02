from datetime import UTC, datetime, timedelta
from typing import Literal

from app.core.authz import AuthContext
from app.repositories.dashboard_kpis import (
    DashboardKpiRepository,
    TicketAlertRow,
    WindowStats,
)
from app.schemas.dashboard import (
    AlertReason,
    AlertsResponse,
    AvailabilityKpi,
    BacklogKpi,
    DownEquipmentAlert,
    KpisResponse,
    KpiValue,
    Period,
    ResolutionTimeKpi,
    ScheduleAlert,
    SlaKpi,
    TechnicianPerformance,
    TechniciansPerformanceResponse,
    TicketAlert,
    TrendPoint,
    TrendsResponse,
)
from app.services.dashboard import DashboardService

#: Equipment counted as operational for the fleet availability figure.
_OPERATIONAL = ("assigned", "in_storage")
#: Below this many tickets a figure is shown with a "few data" note.
MIN_SAMPLE = 5


def _day_start(moment: datetime) -> datetime:
    return moment.astimezone(UTC).replace(hour=0, minute=0, second=0, microsecond=0)


def _shift_months(moment: datetime, months: int) -> datetime:
    index = moment.year * 12 + (moment.month - 1) + months
    return moment.replace(year=index // 12, month=index % 12 + 1)


def period_window(period: Period, now: datetime) -> tuple[datetime, datetime]:
    """Whole UTC days (7d, 30d) or whole months (12m) ending with the current one."""
    if period == "12m":
        this_month = _day_start(now).replace(day=1)
        return _shift_months(this_month, -11), _shift_months(this_month, 1)
    days = 7 if period == "7d" else 30
    today = _day_start(now)
    return today - timedelta(days=days - 1), today + timedelta(days=1)


def previous_window(
    period: Period, start: datetime, end: datetime
) -> tuple[datetime, datetime]:
    if period == "12m":
        return _shift_months(start, -12), start
    return start - (end - start), start


def change_pct(current: float | None, previous: float | None) -> float | None:
    if current is None or previous is None or previous == 0:
        return None
    return round((current - previous) / previous * 100, 1)


def _pct(part: int, whole: int) -> float | None:
    return round(part / whole * 100, 1) if whole else None


def _round(value: float | None) -> float | None:
    return round(value, 2) if value is not None else None


def _kpi(current: float | None, previous: float | None, sample_size: int) -> KpiValue:
    return KpiValue(
        value=_round(current) if sample_size else None,
        previous=_round(previous),
        change_pct=change_pct(current if sample_size else None, previous),
        sample_size=sample_size,
        low_sample=0 < sample_size < MIN_SAMPLE,
    )


def _mttr(current: WindowStats, previous: WindowStats) -> ResolutionTimeKpi:
    base = _kpi(
        current.median_resolution_hours,
        previous.median_resolution_hours,
        current.resolved,
    )
    has = current.resolved > 0
    return ResolutionTimeKpi(
        **base.model_dump(),
        average_hours=_round(current.avg_resolution_hours) if has else None,
        p90_hours=_round(current.p90_resolution_hours) if has else None,
        min_hours=_round(current.min_resolution_hours) if has else None,
        max_hours=_round(current.max_resolution_hours) if has else None,
        stddev_hours=_round(current.stddev_resolution_hours) if has else None,
    )


def _sla_pct(stats: WindowStats) -> float | None:
    return _pct(stats.sla_met, stats.sla_met + stats.sla_missed)


def _ticket_reason(row: TicketAlertRow, now: datetime) -> AlertReason:
    if row.sla_deadline is not None and row.sla_deadline < now:
        return "sla_breached"
    if row.priority == "critical" and not row.assigned:
        return "unassigned_critical"
    return "sla_at_risk"


class DashboardKpiService(DashboardService):
    """Headline KPIs, trend series and the actionable alert list.

    Same scoping as the base service: technicians only see their own tickets.
    """

    repository: DashboardKpiRepository

    async def kpis(
        self, actor: AuthContext, *, period: Period, now: datetime | None = None
    ) -> KpisResponse:
        now = now or datetime.now(UTC)
        technician_id, scope = await self._scope(actor)
        start, end = period_window(period, now)
        prev_start, prev_end = previous_window(period, start, end)
        current = await self.repository.window_stats(
            start=start, end=end, technician_id=technician_id
        )
        previous = await self.repository.window_stats(
            start=prev_start, end=prev_end, technician_id=technician_id
        )
        backlog = await self.repository.backlog(now, technician_id=technician_id)
        backlog_before = await self.repository.open_tickets_at(
            start, technician_id=technician_id
        )
        equipment = await self.repository.equipment_by_status()
        operational_before, total_before = await self.repository.availability_at(start)

        total = sum(row.count for row in equipment)
        operational = sum(row.count for row in equipment if row.key in _OPERATIONAL)
        availability = _pct(operational, total)
        availability_before = _pct(operational_before, total_before)
        sla_current, sla_previous = _sla_pct(current), _sla_pct(previous)
        return KpisResponse(
            generated_at=now,
            scope=scope,
            period=period,
            window_start=start,
            window_end=end,
            mttr_hours=_mttr(current, previous),
            first_assignment_hours=_kpi(
                current.avg_first_assignment_hours,
                previous.avg_first_assignment_hours,
                current.first_assignment_count,
            ),
            sla_compliance_pct=SlaKpi(
                value=sla_current,
                previous=sla_previous,
                change_pct=change_pct(sla_current, sla_previous),
                sample_size=current.sla_met + current.sla_missed,
                low_sample=0 < current.sla_met + current.sla_missed < MIN_SAMPLE,
                met=current.sla_met,
                missed=current.sla_missed,
                excluded_no_sla=current.sla_excluded,
            ),
            resolution_rate_pct=_kpi(
                _pct(current.resolved_of_created, current.created),
                _pct(previous.resolved_of_created, previous.created),
                current.created,
            ),
            backlog=BacklogKpi(
                open=backlog.open,
                previous_open=backlog_before,
                change_pct=change_pct(float(backlog.open), float(backlog_before)),
                age_0_2_days=backlog.age_0_2,
                age_3_7_days=backlog.age_3_7,
                age_over_7_days=backlog.age_over_7,
            ),
            availability=AvailabilityKpi(
                value=availability,
                previous=availability_before,
                change_pct=change_pct(availability, availability_before),
                operational=operational,
                total=total,
            ),
        )

    async def trends(
        self, actor: AuthContext, *, period: Period, now: datetime | None = None
    ) -> TrendsResponse:
        now = now or datetime.now(UTC)
        technician_id, scope = await self._scope(actor)
        start, end = period_window(period, now)
        unit: Literal["day", "month"] = "month" if period == "12m" else "day"
        rows = {
            row.bucket.astimezone(UTC): row
            for row in await self.repository.trend_buckets(
                start=start, end=end, unit=unit, technician_id=technician_id
            )
        }
        points: list[TrendPoint] = []
        bucket = start
        while bucket < end:
            row = rows.get(bucket)
            points.append(
                TrendPoint(
                    bucket=bucket,
                    created=row.created if row else 0,
                    resolved=row.resolved if row else 0,
                    mttr_hours=_round(row.avg_resolution_hours) if row else None,
                    sla_compliance_pct=(
                        _pct(row.sla_met, row.sla_met + row.sla_missed) if row else None
                    ),
                )
            )
            bucket = (
                _shift_months(bucket, 1)
                if unit == "month"
                else bucket + timedelta(days=1)
            )
        return TrendsResponse(
            generated_at=now,
            scope=scope,
            period=period,
            granularity=unit,
            points=points,
        )

    async def alerts(
        self, actor: AuthContext, *, now: datetime | None = None
    ) -> AlertsResponse:
        now = now or datetime.now(UTC)
        technician_id, scope = await self._scope(actor)
        tickets = await self.repository.ticket_alerts(now, technician_id=technician_id)
        down = await self.repository.down_equipment()
        schedules = await self.repository.schedule_alerts(
            now, technician_id=technician_id
        )
        return AlertsResponse(
            generated_at=now,
            scope=scope,
            tickets=[
                TicketAlert(
                    id=t.id,
                    ticket_number=t.ticket_number,
                    title=t.title,
                    equipment_id=t.equipment_id,
                    asset_tag=t.asset_tag,
                    priority=t.priority,
                    status=t.status,
                    assigned=t.assigned,
                    sla_deadline=t.sla_deadline,
                    reason=_ticket_reason(t, now),
                )
                for t in tickets
            ],
            down_equipment=[
                DownEquipmentAlert(
                    equipment_id=e.equipment_id,
                    asset_tag=e.asset_tag,
                    brand=e.brand,
                    model=e.model,
                    status=e.status,
                    down_since=e.down_since,
                    down_hours=(
                        round((now - e.down_since).total_seconds() / 3600, 1)
                        if e.down_since
                        else None
                    ),
                )
                for e in down
            ],
            schedules=[
                ScheduleAlert(
                    id=s.id,
                    equipment_id=s.equipment_id,
                    asset_tag=s.asset_tag,
                    title=s.title,
                    next_due_at=s.next_due_at,
                    overdue=s.next_due_at < now,
                )
                for s in schedules
            ],
        )

    async def technicians(
        self, actor: AuthContext, *, period: Period, now: datetime | None = None
    ) -> TechniciansPerformanceResponse:
        now = now or datetime.now(UTC)
        technician_id, scope = await self._scope(actor)
        start, end = period_window(period, now)
        rows = await self.repository.technician_performance(
            start=start, end=end, technician_id=technician_id
        )
        return TechniciansPerformanceResponse(
            generated_at=now,
            scope=scope,
            period=period,
            window_start=start,
            window_end=end,
            technicians=[
                TechnicianPerformance(
                    technician_id=row.technician_id,
                    full_name=row.full_name,
                    specialization=row.specialization,
                    is_available=row.is_available,
                    open_tickets=row.open_tickets,
                    resolved=row.resolved,
                    mttr_median_hours=_round(row.median_resolution_hours),
                    sample_size=row.resolved,
                    low_sample=0 < row.resolved < MIN_SAMPLE,
                    sla_compliance_pct=_pct(row.sla_met, row.sla_met + row.sla_missed),
                    sla_sample_size=row.sla_met + row.sla_missed,
                    sla_low_sample=0 < row.sla_met + row.sla_missed < MIN_SAMPLE,
                    sla_excluded_no_sla=row.sla_excluded,
                    reopened=row.reopened,
                )
                for row in rows
            ],
        )
