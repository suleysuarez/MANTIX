from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

#: A `priorities.code` from the managed catalog (validated by the service).
MaintenancePriority = Annotated[str, Field(pattern=r"^[a-z][a-z_]{1,19}$")]
MaintenanceRequestStatus = Literal[
    "submitted",
    "triaged",
    "assigned",
    "in_progress",
    "waiting",
    "resolved",
    "closed",
    "cancelled",
]
#: A `request_categories.code` from the managed catalog (validated by the service).
MaintenanceCategory = Annotated[str, Field(pattern=r"^[a-z][a-z_]{1,29}$")]
WorkType = Literal[
    "corrective",
    "preventive",
    "inspection",
    "installation",
    "recovery",
    "other",
]


class EquipmentSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    asset_tag: str
    brand: str
    model: str


class UserSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    full_name: str
    email: str


class TechnicianSummary(BaseModel):
    id: int
    user_id: int
    full_name: str


class TicketAssignmentResponse(BaseModel):
    id: int
    technician: TechnicianSummary
    assigned_at: datetime
    unassigned_at: datetime | None
    notes: str | None


class TicketStatusHistoryEntry(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    from_status: str | None
    to_status: str
    changed_at: datetime
    notes: str | None


class MaintenanceRequestCreate(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "equipment_id": 12,
                "title": "Laptop will not boot",
                "description": "Black screen after the Dell logo since this morning.",
                "priority": "high",
            }
        }
    )

    equipment_id: int
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1)
    priority: MaintenancePriority = "medium"
    category: MaintenanceCategory | None = None

    @field_validator("title", "description")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("must not be blank")
        return value


def _clean(value: str | None) -> str | None:
    """Trimmed text; a blank string means "not provided"."""
    if value is None:
        return None
    return value.strip() or None


class MaintenanceStatusTransitionRequest(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "status": "resolved",
                "notes": "Replaced the faulty SSD",
                "resolution_summary": "SSD replaced and OS reinstalled.",
            }
        }
    )

    status: MaintenanceRequestStatus
    notes: str | None = Field(default=None, max_length=500)
    resolution_summary: str | None = Field(default=None, max_length=1000)

    @field_validator("notes", "resolution_summary")
    @classmethod
    def _blank_is_none(cls, value: str | None) -> str | None:
        return _clean(value)


class WorkflowState(BaseModel):
    """One status of the ticket lifecycle, as the State pattern defines it."""

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "status": "triaged",
                "order": 2,
                "allowed_targets": ["assigned", "cancelled"],
                "requires": ["category", "priority"],
                "terminal": False,
            }
        }
    )

    status: str
    order: int
    allowed_targets: list[str]
    requires: list[str] = Field(
        description="Data to ask for before moving a ticket into this status"
    )
    terminal: bool


class MaintenanceClassifyRequest(BaseModel):
    """Triage: sets the category and priority, and moves a new request to `triaged`."""

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "category": "hardware",
                "priority": "high",
                "notes": "Needs an on-site visit",
            }
        }
    )

    category: MaintenanceCategory
    priority: MaintenancePriority
    notes: str | None = Field(default=None, max_length=500)

    @field_validator("notes")
    @classmethod
    def _blank_is_none(cls, value: str | None) -> str | None:
        return _clean(value)


class MaintenanceRejectRequest(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={"example": {"reason": "Duplicates ticket TCK-2026-000042"}}
    )

    reason: str = Field(min_length=5, max_length=500)

    @field_validator("reason")
    @classmethod
    def _reason_not_blank(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 5:
            raise ValueError("the reason must have at least 5 characters")
        return value


class TicketAssignmentCreateRequest(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={"example": {"technician_id": 4, "notes": "On-site visit"}}
    )

    technician_id: int = Field(gt=0)
    notes: str | None = Field(default=None, max_length=500)

    @field_validator("notes")
    @classmethod
    def _blank_is_none(cls, value: str | None) -> str | None:
        return _clean(value)


class MaintenanceRecordCreate(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "work_type": "corrective",
                "started_at": "2026-10-11T09:00:00Z",
                "completed_at": "2026-10-11T10:30:00Z",
                "diagnosis": "Failing SSD",
                "actions_taken": "Replaced SSD and reinstalled the OS",
                "result": "resolved",
                "labor_cost": "35.00",
                "parts_cost": "80.00",
            }
        }
    )

    work_type: WorkType
    started_at: datetime
    completed_at: datetime | None = None
    diagnosis: str = Field(min_length=1)
    actions_taken: str = Field(min_length=1)
    result: str = Field(min_length=1, max_length=50)
    labor_cost: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    parts_cost: Decimal | None = Field(default=None, ge=0, decimal_places=2)
    notes: str | None = None


class MaintenanceRecordResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    equipment_id: int
    request_id: int | None
    technician_id: int
    work_type: str
    started_at: datetime
    completed_at: datetime | None
    diagnosis: str
    actions_taken: str
    result: str
    labor_cost: Decimal | None
    parts_cost: Decimal | None
    total_cost: Decimal | None
    notes: str | None


class MaintenanceRequestListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    ticket_number: str
    equipment_id: int
    title: str
    priority: str
    category: str | None = None
    status: str
    created_at: datetime


class MaintenanceRequestResponse(BaseModel):
    id: int
    ticket_number: str
    equipment: EquipmentSummary
    requested_by: UserSummary
    title: str
    description: str
    priority: str
    category: str | None = None
    status: str
    resolution_summary: str | None
    resolved_at: datetime | None
    closed_at: datetime | None
    created_at: datetime
    updated_at: datetime
    current_assignment: TicketAssignmentResponse | None
    status_history: list[TicketStatusHistoryEntry]
    #: Estados a los que el ticket puede pasar desde el actual (regla del dominio).
    allowed_next_statuses: list[str] = []
