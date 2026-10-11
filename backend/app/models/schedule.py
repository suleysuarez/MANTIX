from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Identity,
    Index,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.auth import User
    from app.models.equipment import Equipment
    from app.models.technician import Technician


class MaintenanceSchedule(Base):
    """Recurring preventive-maintenance plan for one piece of equipment."""

    __tablename__ = "maintenance_schedules"
    __table_args__ = (
        CheckConstraint("interval_days > 0", name="interval_positive"),
        CheckConstraint("remind_days_before >= 0", name="remind_non_negative"),
        Index("ix_maintenance_schedules_active_due", "is_active", "next_due_at"),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    equipment_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("equipment.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    technician_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("technicians.id", ondelete="SET NULL"),
        nullable=True,
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    interval_days: Mapped[int] = mapped_column(Integer, nullable=False)
    remind_days_before: Mapped[int] = mapped_column(
        Integer, default=3, server_default="3", nullable=False
    )
    next_due_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    last_reminded_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_by_user_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
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

    equipment: Mapped["Equipment"] = relationship("Equipment")
    technician: Mapped["Technician | None"] = relationship("Technician")
    created_by_user: Mapped["User | None"] = relationship(
        "User", foreign_keys=[created_by_user_id]
    )
