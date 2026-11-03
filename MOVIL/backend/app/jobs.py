"""Background jobs (APScheduler) and the composition of their dependencies.

Jobs run outside a request, so they build their own session and wire the same
repositories/services the API uses. APScheduler runs inside the API process:
simple, no broker to operate. With several API replicas every instance runs the
job, which is safe because `ReminderService` takes a PostgreSQL advisory lock.
"""

import logging
from collections.abc import Callable
from contextlib import AbstractAsyncContextManager
from dataclasses import dataclass
from datetime import UTC, datetime

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.repositories.audit import AuditRepository
from app.repositories.notification import NotificationRepository
from app.repositories.schedule import ScheduleRepository
from app.schemas.schedule import ReminderRunResponse
from app.services.audit import AuditService
from app.services.notification import NotificationService
from app.services.reminders import ReminderService

logger = logging.getLogger("mantix.jobs")

SessionFactory = Callable[[], AbstractAsyncContextManager[AsyncSession]]
REMINDER_JOB_ID = "schedule-reminders"


@dataclass(slots=True)
class JobStatus:
    """Outcome of a job's last run since the server started (kept in memory)."""

    last_run_at: datetime | None = None
    last_ok: bool | None = None
    last_detail: str | None = None


JOB_STATUS: dict[str, JobStatus] = {REMINDER_JOB_ID: JobStatus()}


@dataclass(frozen=True, slots=True)
class JobSnapshot:
    id: str
    name: str
    running: bool
    interval_minutes: int | None
    next_run_at: datetime | None
    last_run_at: datetime | None
    last_ok: bool | None
    last_detail: str | None


def job_snapshots(scheduler: AsyncIOScheduler | None) -> list[JobSnapshot]:
    """What the health panel shows for each known job, scheduler up or not."""
    snapshots: list[JobSnapshot] = []
    for job_id, status in JOB_STATUS.items():
        job = scheduler.get_job(job_id) if scheduler is not None else None
        interval = getattr(getattr(job, "trigger", None), "interval", None)
        snapshots.append(
            JobSnapshot(
                id=job_id,
                name=job.name
                if job is not None
                else "Preventive maintenance reminders",
                running=job is not None and scheduler is not None and scheduler.running,
                interval_minutes=int(interval.total_seconds() // 60)
                if interval
                else None,
                next_run_at=getattr(job, "next_run_time", None),
                last_run_at=status.last_run_at,
                last_ok=status.last_ok,
                last_detail=status.last_detail,
            )
        )
    return snapshots


def build_reminder_service(session: AsyncSession) -> ReminderService:
    return ReminderService(
        ScheduleRepository(session),
        NotificationService(NotificationRepository(session)),
        AuditService(AuditRepository(session)),
    )


async def run_reminder_job(
    session_factory: SessionFactory,
) -> ReminderRunResponse | None:
    """One scheduled execution; never raises (the scheduler would only log it)."""
    status = JOB_STATUS[REMINDER_JOB_ID]
    status.last_run_at = datetime.now(UTC)
    try:
        async with session_factory() as session:
            result = await build_reminder_service(session).run()
    except Exception as error:
        logger.exception("reminder job failed")
        status.last_ok, status.last_detail = False, type(error).__name__
        return None
    status.last_ok = True
    status.last_detail = (
        "another instance held the lock"
        if result.locked_by_another_worker
        else f"{result.reminders_sent} reminders sent"
    )
    return result


def build_scheduler(
    settings: Settings, session_factory: SessionFactory
) -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler(timezone="UTC")
    scheduler.add_job(
        run_reminder_job,
        IntervalTrigger(minutes=settings.reminder_interval_minutes),
        args=[session_factory],
        id=REMINDER_JOB_ID,
        name="Preventive maintenance reminders",
        max_instances=1,  # never overlap with itself
        coalesce=True,  # collapse missed runs into one
        misfire_grace_time=300,
        replace_existing=True,
    )
    return scheduler
