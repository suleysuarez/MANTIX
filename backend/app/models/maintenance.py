from datetime import datetime
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Identity,
    Index,
    Numeric,
    String,
    Text,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.attachment import Attachment
    from app.models.auth import User
    from app.models.equipment import Equipment
    from app.models.technician import Technician


class MaintenanceRequest(Base):
    __tablename__ = "maintenance_requests"
    __table_args__ = (
        CheckConstraint(
            "closed_at IS NULL OR resolved_at IS NULL OR closed_at >= resolved_at",
            name="closed_after_resolved",
        ),
        CheckConstraint(
            "status IN ('submitted', 'triaged', 'assigned', 'in_progress', "
            "'waiting', 'resolved', 'closed', 'cancelled')",
            name="status_allowed",
        ),
        Index(
            "ix_maintenance_requests_status_priority_created",
            "status",
            "priority",
            "created_at",
        ),
        Index(
            "ix_maintenance_requests_equipment_created",
            "equipment_id",
            "created_at",
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    ticket_number: Mapped[str] = mapped_column(
        String(50), unique=True, index=True, nullable=False
    )
    equipment_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("equipment.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    requested_by_user_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("users.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    priority: Mapped[str] = mapped_column(
        String(20),
        ForeignKey("priorities.code", onupdate="CASCADE", ondelete="RESTRICT"),
        default="medium",
        nullable=False,
    )
    status: Mapped[str] = mapped_column(String(30), default="submitted", nullable=False)
    resolution_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    resolved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    closed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    equipment: Mapped["Equipment"] = relationship(
        "Equipment", back_populates="maintenance_requests"
    )
    requested_by_user: Mapped["User"] = relationship(
        "User",
        foreign_keys=[requested_by_user_id],
        back_populates="maintenance_requests",
    )
    ticket_assignments: Mapped[list["TicketAssignment"]] = relationship(
        "TicketAssignment",
        back_populates="request",
        cascade="all, delete-orphan",
    )
    status_history: Mapped[list["TicketStatusHistory"]] = relationship(
        "TicketStatusHistory",
        back_populates="request",
        cascade="all, delete-orphan",
    )
    maintenance_records: Mapped[list["MaintenanceRecord"]] = relationship(
        "MaintenanceRecord", back_populates="request"
    )
    attachments: Mapped[list["Attachment"]] = relationship(
        "Attachment", back_populates="request"
    )


class TicketAssignment(Base):
    __tablename__ = "ticket_assignments"
    __table_args__ = (
        CheckConstraint(
            "unassigned_at IS NULL OR unassigned_at >= assigned_at",
            name="dates",
        ),
        Index(
            "ix_ticket_assignments_one_active",
            "request_id",
            unique=True,
            postgresql_where=text("unassigned_at IS NULL"),
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    request_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("maintenance_requests.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    technician_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("technicians.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    assigned_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    unassigned_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    assigned_by_user_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    request: Mapped["MaintenanceRequest"] = relationship(
        "MaintenanceRequest", back_populates="ticket_assignments"
    )
    technician: Mapped["Technician"] = relationship(
        "Technician", back_populates="ticket_assignments"
    )
    assigned_by_user: Mapped["User | None"] = relationship(
        "User", foreign_keys=[assigned_by_user_id]
    )


class TicketStatusHistory(Base):
    __tablename__ = "ticket_status_history"
    __table_args__ = (
        CheckConstraint(
            "to_status IN ('submitted', 'triaged', 'assigned', 'in_progress', "
            "'waiting', 'resolved', 'closed', 'cancelled')",
            name="to_status_allowed",
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    request_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("maintenance_requests.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    from_status: Mapped[str | None] = mapped_column(String(30), nullable=True)
    to_status: Mapped[str] = mapped_column(String(30), nullable=False)
    changed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    changed_by_user_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    request: Mapped["MaintenanceRequest"] = relationship(
        "MaintenanceRequest", back_populates="status_history"
    )
    changed_by_user: Mapped["User | None"] = relationship(
        "User", foreign_keys=[changed_by_user_id]
    )


class MaintenanceRecord(Base):
    __tablename__ = "maintenance_records"
    __table_args__ = (
        CheckConstraint(
            "completed_at IS NULL OR completed_at >= started_at",
            name="dates",
        ),
        CheckConstraint(
            "labor_cost IS NULL OR labor_cost >= 0",
            name="labor_cost_positive",
        ),
        CheckConstraint(
            "parts_cost IS NULL OR parts_cost >= 0",
            name="parts_cost_positive",
        ),
        CheckConstraint(
            "total_cost IS NULL OR total_cost >= 0",
            name="total_cost_positive",
        ),
        CheckConstraint(
            "work_type IN ('corrective', 'preventive', 'inspection', "
            "'installation', 'recovery', 'other')",
            name="work_type_allowed",
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    equipment_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("equipment.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    # request_id is explicitly nullable
    request_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("maintenance_requests.id", ondelete="SET NULL"),
        index=True,
        nullable=True,
    )
    technician_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("technicians.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    work_type: Mapped[str] = mapped_column(String(50), nullable=False)
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    diagnosis: Mapped[str] = mapped_column(Text, nullable=False)
    actions_taken: Mapped[str] = mapped_column(Text, nullable=False)
    result: Mapped[str] = mapped_column(String(50), nullable=False)
    labor_cost: Mapped[Decimal | None] = mapped_column(
        Numeric(12, 2), default=Decimal("0.00"), nullable=True
    )
    parts_cost: Mapped[Decimal | None] = mapped_column(
        Numeric(12, 2), default=Decimal("0.00"), nullable=True
    )
    total_cost: Mapped[Decimal | None] = mapped_column(
        Numeric(12, 2), default=Decimal("0.00"), nullable=True
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    equipment: Mapped["Equipment"] = relationship(
        "Equipment", back_populates="maintenance_records"
    )
    request: Mapped["MaintenanceRequest | None"] = relationship(
        "MaintenanceRequest", back_populates="maintenance_records"
    )
    technician: Mapped["Technician"] = relationship(
        "Technician", back_populates="maintenance_records"
    )
    attachments: Mapped[list["Attachment"]] = relationship(
        "Attachment", back_populates="maintenance_record"
    )
