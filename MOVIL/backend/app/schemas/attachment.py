from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class AttachmentResponse(BaseModel):
    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "example": {
                "id": 15,
                "file_name": "screen-damage.jpg",
                "mime_type": "image/jpeg",
                "file_size": 234112,
                "equipment_id": None,
                "request_id": 42,
                "uploaded_by_user_id": 7,
                "created_at": "2026-10-11T15:00:00Z",
            }
        },
    )

    id: int
    file_name: str
    mime_type: str
    file_size: int = Field(description="Size in bytes")
    equipment_id: int | None
    request_id: int | None
    uploaded_by_user_id: int | None
    created_at: datetime
