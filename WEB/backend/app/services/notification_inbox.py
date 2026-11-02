from app.core.exceptions import NotFoundError
from app.models.auth import User
from app.repositories.notification import NotificationRepository
from app.schemas.notification import NotificationListResponse, NotificationResponse


class NotificationInboxService:
    """Reads and marks the signed-in user's own notifications.

    Complements `NotificationService`, which only creates rows inside the
    caller's transaction. Every query is scoped to `actor.id`, so a user can
    never read or modify somebody else's notifications.
    """

    def __init__(self, repository: NotificationRepository):
        self.repository = repository

    async def list(
        self, actor: User, *, unread_only: bool, limit: int, offset: int
    ) -> NotificationListResponse:
        items = await self.repository.list_for_user(
            actor.id, unread_only=unread_only, limit=limit, offset=offset
        )
        return NotificationListResponse(
            unread_count=await self.repository.count_unread(actor.id),
            items=[NotificationResponse.model_validate(item) for item in items],
        )

    async def mark_read(
        self, actor: User, notification_id: int
    ) -> NotificationResponse:
        notification = await self.repository.get_for_user(notification_id, actor.id)
        if notification is None:
            raise NotFoundError("notification not found")
        await self.repository.mark_read(notification)
        await self.repository.commit()
        return NotificationResponse.model_validate(notification)

    async def mark_all_read(self, actor: User) -> None:
        await self.repository.mark_all_read(actor.id)
        await self.repository.commit()
