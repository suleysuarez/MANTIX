from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, Identity, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class RequestCategory(Base):
    """Managed catalog of maintenance-request categories (referenced by `code`)."""

    __tablename__ = "request_categories"

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    code: Mapped[str] = mapped_column(String(30), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
