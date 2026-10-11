from app.repositories.notification import NotificationRepository


class NotificationService:
    """Creates in-app notification rows as part of the caller's transaction.

    Same pattern as `AuditService`: no independent commit, so a notification
    is only ever persisted alongside the domain event that triggered it.
    Delivery (email/push) is out of scope; the frontend lists/polls these.
    """

    def __init__(self, repository: NotificationRepository):
        self.repository = repository

    def notify(
        self,
        *,
        user_id: int,
        title: str,
        message: str,
        notification_type: str,
        link_url: str | None = None,
    ) -> None:
        self.repository.stage(
            user_id=user_id,
            title=title,
            message=message,
            notification_type=notification_type,
            link_url=link_url,
        )
