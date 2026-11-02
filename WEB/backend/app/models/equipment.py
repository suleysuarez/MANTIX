from datetime import date, datetime
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Identity,
    Index,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.attachment import Attachment
    from app.models.auth import User
    from app.models.maintenance import MaintenanceRecord, MaintenanceRequest


class EquipmentType(Base):
    __tablename__ = "equipment_types"

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    code: Mapped[str] = mapped_column(
        String(50), unique=True, index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    equipment: Mapped[list["Equipment"]] = relationship(
        "Equipment", back_populates="equipment_type"
    )


class Location(Base):
    __tablename__ = "locations"
    __table_args__ = (
        CheckConstraint(
            "parent_id IS NULL OR id != parent_id",
            name="parent_not_self",
        ),
        UniqueConstraint("parent_id", "name", name="uq_locations_parent_id_name"),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    parent_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("locations.id", ondelete="RESTRICT"),
        index=True,
        nullable=True,
    )
    code: Mapped[str] = mapped_column(
        String(50), unique=True, index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    kind: Mapped[str] = mapped_column(
        String(50), nullable=False
    )  # building, floor, room, office, laboratory, warehouse, etc.
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    parent: Mapped["Location | None"] = relationship(
        "Location", remote_side=[id], back_populates="children"
    )
    children: Mapped[list["Location"]] = relationship(
        "Location", back_populates="parent"
    )
    equipment_location_history: Mapped[list["EquipmentLocationHistory"]] = relationship(
        "EquipmentLocationHistory", back_populates="location"
    )


class Equipment(Base):
    __tablename__ = "equipment"
    __table_args__ = (
        CheckConstraint(
            "purchase_cost IS NULL OR purchase_cost >= 0",
            name="purchase_cost_non_negative",
        ),
        CheckConstraint(
            "warranty_end_date IS NULL OR warranty_start_date IS NULL OR warranty_end_date >= warranty_start_date",
            name="warranty_dates",
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    asset_tag: Mapped[str] = mapped_column(
        String(50), unique=True, index=True, nullable=False
    )
    serial_number: Mapped[str | None] = mapped_column(
        String(100), unique=True, index=True, nullable=True
    )
    equipment_type_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("equipment_types.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    brand: Mapped[str] = mapped_column(String(100), nullable=False)
    model: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(
        String(50), default="in_storage", nullable=False
    )
    purchase_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    purchase_cost: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    warranty_start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    warranty_end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    equipment_type: Mapped["EquipmentType"] = relationship(
        "EquipmentType", back_populates="equipment"
    )
    location_history: Mapped[list["EquipmentLocationHistory"]] = relationship(
        "EquipmentLocationHistory",
        back_populates="equipment",
        cascade="all, delete-orphan",
    )
    custody_history: Mapped[list["EquipmentCustodyHistory"]] = relationship(
        "EquipmentCustodyHistory",
        back_populates="equipment",
        cascade="all, delete-orphan",
    )
    status_history: Mapped[list["EquipmentStatusHistory"]] = relationship(
        "EquipmentStatusHistory",
        back_populates="equipment",
        cascade="all, delete-orphan",
    )
    maintenance_requests: Mapped[list["MaintenanceRequest"]] = relationship(
        "MaintenanceRequest", back_populates="equipment"
    )
    maintenance_records: Mapped[list["MaintenanceRecord"]] = relationship(
        "MaintenanceRecord", back_populates="equipment"
    )
    attachments: Mapped[list["Attachment"]] = relationship(
        "Attachment", back_populates="equipment"
    )


class EquipmentLocationHistory(Base):
    __tablename__ = "equipment_location_history"
    __table_args__ = (
        CheckConstraint(
            "ended_at IS NULL OR ended_at >= started_at",
            name="dates",
        ),
        Index(
            "ix_equipment_location_history_one_active",
            "equipment_id",
            unique=True,
            postgresql_where=text("ended_at IS NULL"),
        ),
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
    location_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("locations.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    ended_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    moved_by_user_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    equipment: Mapped["Equipment"] = relationship(
        "Equipment", back_populates="location_history"
    )
    location: Mapped["Location"] = relationship(
        "Location", back_populates="equipment_location_history"
    )
    moved_by_user: Mapped["User | None"] = relationship(
        "User", foreign_keys=[moved_by_user_id]
    )


class EquipmentCustodyHistory(Base):
    __tablename__ = "equipment_custody_history"
    __table_args__ = (
        CheckConstraint(
            "returned_at IS NULL OR returned_at >= assigned_at",
            name="dates",
        ),
        Index(
            "ix_equipment_custody_history_one_active",
            "equipment_id",
            unique=True,
            postgresql_where=text("returned_at IS NULL"),
        ),
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
    assigned_to_user_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("users.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    assigned_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    returned_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    assigned_by_user_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    equipment: Mapped["Equipment"] = relationship(
        "Equipment", back_populates="custody_history"
    )
    assigned_to_user: Mapped["User"] = relationship(
        "User",
        foreign_keys=[assigned_to_user_id],
        back_populates="custody_assignments",
    )
    assigned_by_user: Mapped["User | None"] = relationship(
        "User", foreign_keys=[assigned_by_user_id]
    )


class EquipmentStatusHistory(Base):
    __tablename__ = "equipment_status_history"

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    equipment_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("equipment.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    from_status: Mapped[str | None] = mapped_column(String(50), nullable=True)
    to_status: Mapped[str] = mapped_column(String(50), nullable=False)
    changed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    changed_by_user_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)

    equipment: Mapped["Equipment"] = relationship(
        "Equipment", back_populates="status_history"
    )
    changed_by_user: Mapped["User | None"] = relationship(
        "User", foreign_keys=[changed_by_user_id]
    )
