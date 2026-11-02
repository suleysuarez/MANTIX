from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class AuditActor(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    full_name: str
    email: str


class AuditLogResponse(BaseModel):
    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "example": {
                "id": 301,
                "user": {"id": 2, "full_name": "Ana Ruiz", "email": "ana@example.com"},
                "action": "maintenance.status_changed",
                "entity_type": "maintenance_request",
                "entity_id": 42,
                "old_values": {"status": "in_progress"},
                "new_values": {"status": "resolved"},
                "ip_address": "203.0.113.7",
                "created_at": "2026-10-11T15:00:00Z",
            }
        },
    )

    id: int
    user: AuditActor | None = Field(description="Null for system actions")
    action: str = Field(examples=["equipment.updated"])
    entity_type: str = Field(examples=["equipment"])
    entity_id: int | None
    old_values: dict[str, Any] | None = Field(description="Values before the change")
    new_values: dict[str, Any] | None = Field(description="Values after the change")
    ip_address: str | None
    created_at: datetime
