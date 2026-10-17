from fastapi import APIRouter, Depends, Query, status

from app.api.dependencies import require_session
from app.api.providers import get_notification_inbox_service
from app.models.auth import User
from app.schemas.notification import NotificationListResponse, NotificationResponse
from app.services.notification_inbox import NotificationInboxService

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=NotificationListResponse)
async def list_notifications(
    unread_only: bool = Query(default=False),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    actor: User = Depends(require_session()),  # noqa: B008
    service: NotificationInboxService = Depends(get_notification_inbox_service),  # noqa: B008
) -> NotificationListResponse:
    return await service.list(
        actor, unread_only=unread_only, limit=limit, offset=offset
    )


@router.post("/read-all", status_code=status.HTTP_204_NO_CONTENT)
async def mark_all_notifications_read(
    actor: User = Depends(require_session()),  # noqa: B008
    service: NotificationInboxService = Depends(get_notification_inbox_service),  # noqa: B008
) -> None:
    await service.mark_all_read(actor)


@router.post("/{notification_id}/read", response_model=NotificationResponse)
async def mark_notification_read(
    notification_id: int,
    actor: User = Depends(require_session()),  # noqa: B008
    service: NotificationInboxService = Depends(get_notification_inbox_service),  # noqa: B008
) -> NotificationResponse:
    return await service.mark_read(actor, notification_id)
