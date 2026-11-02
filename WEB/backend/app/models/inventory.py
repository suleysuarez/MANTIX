from datetime import datetime
from decimal import Decimal
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
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.auth import User

#: The categories every installation starts with; more can be added from the item form.
BUILT_IN_CATEGORIES = (
    ("spare_part", "Repuesto"),
    ("consumable", "Consumible"),
    ("accessory", "Accesorio"),
    ("tool", "Herramienta"),
    ("other", "Otro"),
)
OPTION_KINDS = ("category", "unit", "location", "supplier")
MOVEMENT_KINDS = ("in", "out", "adjust")


class InventoryItem(Base):
    """A stocked spare part, consumable or tool. `stock` only changes through movements."""

    __tablename__ = "inventory_items"
    __table_args__ = (
        CheckConstraint("stock >= 0", name="stock_non_negative"),
        CheckConstraint("min_stock >= 0", name="min_stock_non_negative"),
        CheckConstraint(
            "max_stock IS NULL OR max_stock >= min_stock", name="max_not_below_min"
        ),
        CheckConstraint("unit_cost >= 0", name="unit_cost_non_negative"),
        # Codes are stored in capitals, so the unique index on `sku` is also case-insensitive.
        CheckConstraint("sku = upper(sku)", name="sku_upper_case"),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    sku: Mapped[str] = mapped_column(
        String(40), unique=True, index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    category: Mapped[str] = mapped_column(
        String(30), default="spare_part", nullable=False
    )
    unit: Mapped[str] = mapped_column(String(20), default="unidad", nullable=False)
    unit_cost: Mapped[Decimal] = mapped_column(
        Numeric(12, 2), default=Decimal("0.00"), nullable=False
    )
    stock: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    min_stock: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    max_stock: Mapped[int | None] = mapped_column(Integer, nullable=True)
    location: Mapped[str | None] = mapped_column(String(100), nullable=True)
    supplier: Mapped[str | None] = mapped_column(String(150), nullable=True)
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

    movements: Mapped[list["InventoryMovement"]] = relationship(
        "InventoryMovement", back_populates="item"
    )


class InventoryOption(Base):
    """A value of one of the item drop-downs (category, unit, location, supplier).

    `value` is what items store (for a category, its code); `label` is what people read;
    `key` is the folded label, so «Bodega A» and «bodega  a» cannot both exist.
    """

    __tablename__ = "inventory_options"
    __table_args__ = (
        UniqueConstraint("kind", "key", name="uq_inventory_options_kind_key"),
        CheckConstraint(
            "kind IN ('category', 'unit', 'location', 'supplier')", name="kind_allowed"
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    kind: Mapped[str] = mapped_column(String(12), nullable=False)
    value: Mapped[str] = mapped_column(String(150), nullable=False)
    label: Mapped[str] = mapped_column(String(150), nullable=False)
    key: Mapped[str] = mapped_column(String(150), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class InventoryMovement(Base):
    """Append-only stock ledger. `quantity` is signed: entries > 0, consumption < 0."""

    __tablename__ = "inventory_movements"
    __table_args__ = (
        CheckConstraint("quantity <> 0", name="quantity_non_zero"),
        CheckConstraint("stock_after >= 0", name="stock_after_non_negative"),
        CheckConstraint("kind IN ('in', 'out', 'adjust')", name="kind_allowed"),
        Index("ix_inventory_movements_item_created", "item_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    item_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("inventory_items.id", ondelete="RESTRICT"),
        nullable=False,
    )
    kind: Mapped[str] = mapped_column(String(12), nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    stock_after: Mapped[int] = mapped_column(Integer, nullable=False)
    unit_cost: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    notes: Mapped[str | None] = mapped_column(String(300), nullable=True)
    record_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("maintenance_records.id", ondelete="SET NULL"),
        index=True,
        nullable=True,
    )
    request_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("maintenance_requests.id", ondelete="SET NULL"),
        index=True,
        nullable=True,
    )
    created_by_user_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), index=True, server_default=func.now(), nullable=False
    )

    item: Mapped["InventoryItem"] = relationship(
        "InventoryItem", back_populates="movements"
    )
    created_by: Mapped["User | None"] = relationship(
        "User", foreign_keys=[created_by_user_id]
    )
