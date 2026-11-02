from datetime import datetime

from pydantic import BaseModel, ConfigDict


class NotificationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    message: str
    notification_type: str
    is_read: bool
    read_at: datetime | None
    link_url: str | None
    created_at: datetime


class NotificationListResponse(BaseModel):
    unread_count: int
    items: list[NotificationResponse]
