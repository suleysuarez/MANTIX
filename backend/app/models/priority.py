from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    Identity,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Priority(Base):
    """Managed catalog of ticket priorities (referenced by `code`)."""

    __tablename__ = "priorities"
    __table_args__ = (
        CheckConstraint("level >= 1", name="level_positive"),
        CheckConstraint("sla_hours IS NULL OR sla_hours > 0", name="sla_positive"),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    code: Mapped[str] = mapped_column(String(20), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    #: Ordering weight: higher means more urgent.
    level: Mapped[int] = mapped_column(Integer, nullable=False)
    sla_hours: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
