import logging
from datetime import UTC, datetime

from app.repositories.schedule import ScheduleRepository
from app.schemas.schedule import ReminderRunResponse
from app.services.audit import AuditService
from app.services.notification import NotificationService

logger = logging.getLogger("mantix.reminders")


class ReminderService:
    """Sends in-app reminders for preventive-maintenance plans that are about to
    fall due (or already are).

    Runs from the background scheduler and from an admin endpoint, so it is safe
    to call at any time: each plan is reminded once per due date
    (`last_reminded_at`), and a database advisory lock keeps several API
    instances from sending the same reminder twice.
    """

    def __init__(
        self,
        repository: ScheduleRepository,
        notifications: NotificationService,
        audit: AuditService,
    ):
        self.repository = repository
        self.notifications = notifications
        self.audit = audit

    async def run(self, now: datetime | None = None) -> ReminderRunResponse:
        now = now or datetime.now(UTC)
        if not await self.repository.try_acquire_reminder_lock():
            await self.repository.rollback()
            return ReminderRunResponse(
                locked_by_another_worker=True,
                reminders_sent=0,
                skipped_without_recipient=0,
            )

        sent = skipped = 0
        for schedule in await self.repository.list_due_for_reminder(now):
            recipient_id = (
                schedule.technician.user_id
                if schedule.technician is not None
                else schedule.created_by_user_id
            )
            if recipient_id is None:
                skipped += 1
                logger.warning("schedule %s has nobody to remind", schedule.id)
                continue
            overdue = schedule.next_due_at <= now
            when = schedule.next_due_at.strftime("%Y-%m-%d")
            self.notifications.notify(
                user_id=recipient_id,
                title=(
                    f"Preventive maintenance overdue: {schedule.title}"
                    if overdue
                    else f"Preventive maintenance due soon: {schedule.title}"
                ),
                message=(
                    f"{schedule.equipment.asset_tag} ({schedule.equipment.brand} "
                    f"{schedule.equipment.model}) is due on {when}."
                ),
                notification_type="maintenance_reminder",
                link_url=f"/equipment/{schedule.equipment_id}",
            )
            schedule.last_reminded_at = now
            self.audit.record(
                user_id=None,
                action="schedule.reminder_sent",
                entity_type="maintenance_schedule",
                entity_id=schedule.id,
                new_values={"recipient_user_id": recipient_id, "due": when},
            )
            sent += 1
        await self.repository.commit()
        logger.info("reminder run finished sent=%s skipped=%s", sent, skipped)
        return ReminderRunResponse(
            locked_by_another_worker=False,
            reminders_sent=sent,
            skipped_without_recipient=skipped,
        )
