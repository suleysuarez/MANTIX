from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

MaintenancePriority = Literal["low", "medium", "high", "critical"]
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
    equipment_id: int
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1)
    priority: MaintenancePriority = "medium"


class MaintenanceStatusTransitionRequest(BaseModel):
    status: MaintenanceRequestStatus
    notes: str | None = None
    resolution_summary: str | None = None


class TicketAssignmentCreateRequest(BaseModel):
    technician_id: int
    notes: str | None = None


class MaintenanceRecordCreate(BaseModel):
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
