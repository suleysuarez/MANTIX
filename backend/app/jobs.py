"""Background jobs (APScheduler) and the composition of their dependencies.

Jobs run outside a request, so they build their own session and wire the same
repositories/services the API uses. APScheduler runs inside the API process:
simple, no broker to operate. With several API replicas every instance runs the
job, which is safe because `ReminderService` takes a PostgreSQL advisory lock.
"""

import logging
from collections.abc import Callable
from contextlib import AbstractAsyncContextManager

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
    try:
        async with session_factory() as session:
            return await build_reminder_service(session).run()
    except Exception:
        logger.exception("reminder job failed")
        return None


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
