from datetime import UTC, datetime

from app.core.authz import AuthContext
from app.repositories.queue import DecisionStats, QueueRepository
from app.schemas.dashboard import CountItem, KpiValue, Period
from app.schemas.queue import (
    DecisionKpi,
    QueueSummary,
    RequestCategoryResponse,
    TriageTimeKpi,
)
from app.services.dashboard_kpis import (
    MIN_SAMPLE,
    change_pct,
    period_window,
    previous_window,
)


def _round(value: float | None) -> float | None:
    return round(value, 2) if value is not None else None


def _rate(part: int, whole: int) -> float | None:
    return round(part / whole * 100, 1) if whole else None


class QueueService:
    """Metrics of the pending-requests queue. Only ADMIN and SUPERVISOR triage."""

    def __init__(self, repository: QueueRepository):
        self.repository = repository

    @staticmethod
    def _require_elevated(actor: AuthContext) -> None:
        actor.require(
            "solicitudes:ver_todos",
            "Solo quien gestiona solicitudes puede ver la cola.",
        )

    async def categories(self) -> list[RequestCategoryResponse]:
        return [
            RequestCategoryResponse(code=c.code, name=c.name)
            for c in await self.repository.active_categories()
        ]

    async def summary(
        self, actor: AuthContext, *, period: Period, now: datetime | None = None
    ) -> QueueSummary:
        self._require_elevated(actor)
        now = now or datetime.now(UTC)
        start, end = period_window(period, now)
        prev_start, prev_end = previous_window(period, start, end)
        waits = await self.repository.wait_stats(now)
        current = await self.repository.decision_stats(start=start, end=end)
        previous = await self.repository.decision_stats(start=prev_start, end=prev_end)
        return QueueSummary(
            generated_at=now,
            period=period,
            window_start=start,
            window_end=end,
            pending_total=waits.pending,
            unassigned=waits.unassigned,
            oldest_wait_hours=_round(waits.oldest_hours),
            median_wait_hours=_round(waits.median_hours),
            by_priority=[
                CountItem(key=r.key, count=r.count)
                for r in await self.repository.pending_by_priority()
            ],
            by_category=[
                CountItem(key=r.key, count=r.count)
                for r in await self.repository.pending_by_category()
            ],
            triage_time=self._triage(current, previous),
            decisions=self._decisions(current, previous),
        )

    @staticmethod
    def _triage(current: DecisionStats, previous: DecisionStats) -> TriageTimeKpi:
        n = current.decisions
        value = current.avg_triage_hours
        base = KpiValue(
            value=_round(value) if n else None,
            previous=_round(previous.avg_triage_hours),
            change_pct=change_pct(value if n else None, previous.avg_triage_hours),
            sample_size=n,
            low_sample=0 < n < MIN_SAMPLE,
        )
        return TriageTimeKpi(
            **base.model_dump(),
            median_hours=_round(current.median_triage_hours) if n else None,
        )

    @staticmethod
    def _decisions(current: DecisionStats, previous: DecisionStats) -> DecisionKpi:
        n = current.decisions
        approved = n - current.rejected
        rate = _rate(approved, n)
        previous_rate = _rate(
            previous.decisions - previous.rejected, previous.decisions
        )
        return DecisionKpi(
            approved=approved,
            rejected=current.rejected,
            sample_size=n,
            low_sample=0 < n < MIN_SAMPLE,
            approval_rate_pct=rate,
            rejection_rate_pct=_rate(current.rejected, n),
            previous_approval_rate_pct=previous_rate,
            change_pct=change_pct(rate, previous_rate),
        )
