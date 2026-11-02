from datetime import datetime
from typing import TYPE_CHECKING, Any

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Identity,
    Integer,
    String,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.auth import User


class ReportRun(Base):
    """One generated report file: who, which report, with which filters, how many rows."""

    __tablename__ = "report_runs"
    __table_args__ = (
        CheckConstraint("row_count >= 0", name="row_count_non_negative"),
        CheckConstraint(
            "export_format IN ('csv', 'xlsx', 'pdf')", name="format_allowed"
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    report_key: Mapped[str] = mapped_column(String(40), index=True, nullable=False)
    export_format: Mapped[str] = mapped_column(String(10), nullable=False)
    filters: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    row_count: Mapped[int] = mapped_column(Integer, nullable=False)
    user_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), index=True, server_default=func.now(), nullable=False
    )

    user: Mapped["User | None"] = relationship("User", foreign_keys=[user_id])
