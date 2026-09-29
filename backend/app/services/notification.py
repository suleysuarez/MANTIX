from sqlalchemy.ext.asyncio import AsyncSession

from app.models.notification import Notification


class NotificationService:
    """Creates in-app notification rows as part of the caller's transaction.

    Same pattern as `AuditService`: no independent commit, so a notification
    is only ever persisted alongside the domain event that triggered it.
    Delivery (email/push) is out of scope; the frontend lists/polls these.
    """

    def __init__(self, session: AsyncSession):
        self.session = session

    def notify(
        self,
        *,
        user_id: int,
        title: str,
        message: str,
        notification_type: str,
        link_url: str | None = None,
    ) -> None:
        self.session.add(
            Notification(
                user_id=user_id,
                title=title,
                message=message,
                notification_type=notification_type,
                link_url=link_url,
            )
        )
