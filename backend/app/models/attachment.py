from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Identity,
    String,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.auth import User
    from app.models.equipment import Equipment
    from app.models.maintenance import MaintenanceRecord, MaintenanceRequest


class Attachment(Base):
    __tablename__ = "attachments"
    __table_args__ = (
        CheckConstraint(
            "file_size >= 0",
            name="file_size_positive",
        ),
        CheckConstraint(
            "(CASE WHEN equipment_id IS NOT NULL THEN 1 ELSE 0 END + "
            "CASE WHEN request_id IS NOT NULL THEN 1 ELSE 0 END + "
            "CASE WHEN maintenance_record_id IS NOT NULL THEN 1 ELSE 0 END) = 1",
            name="exactly_one_parent",
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    equipment_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("equipment.id", ondelete="CASCADE"),
        index=True,
        nullable=True,
    )
    request_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("maintenance_requests.id", ondelete="CASCADE"),
        index=True,
        nullable=True,
    )
    maintenance_record_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("maintenance_records.id", ondelete="CASCADE"),
        index=True,
        nullable=True,
    )
    file_name: Mapped[str] = mapped_column(String(255), nullable=False)
    file_path: Mapped[str] = mapped_column(String(500), nullable=False)
    file_size: Mapped[int] = mapped_column(BigInteger, nullable=False)
    mime_type: Mapped[str] = mapped_column(String(100), nullable=False)
    uploaded_by_user_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    equipment: Mapped["Equipment | None"] = relationship(
        "Equipment", back_populates="attachments"
    )
    request: Mapped["MaintenanceRequest | None"] = relationship(
        "MaintenanceRequest", back_populates="attachments"
    )
    maintenance_record: Mapped["MaintenanceRecord | None"] = relationship(
        "MaintenanceRecord", back_populates="attachments"
    )
    uploaded_by_user: Mapped["User | None"] = relationship(
        "User", foreign_keys=[uploaded_by_user_id]
    )
