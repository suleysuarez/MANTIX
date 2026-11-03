"""inventory items, stock movements and permissions

Adds the stock ledger behind the Inventory screen:

* `inventory_items`: SKU, category, unit, cost, stock and min/max levels
* `inventory_movements`: append-only entries, consumption and adjustments,
  optionally linked to a maintenance record or ticket
* permissions `inventory.read`, `inventory.manage`, `inventory.consume`

Revision ID: c0e1f2a3b4d5
Revises: b9d0e1f2a3c4
Create Date: 2026-10-14 20:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "c0e1f2a3b4d5"
down_revision: Union[str, None] = "b9d0e1f2a3c4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

NEW_PERMISSIONS = [
    ("inventory.read", "View inventory", "View stock items, movements and metrics", "inventory"),
    ("inventory.manage", "Manage inventory", "Create and edit items; register entries and adjustments", "inventory"),
    ("inventory.consume", "Consume stock", "Register stock consumed in maintenance work", "inventory"),
]

GRANTS = {
    "ADMIN": [p[0] for p in NEW_PERMISSIONS],
    "SUPERVISOR": ["inventory.read", "inventory.manage", "inventory.consume"],
    "TECHNICIAN": ["inventory.read", "inventory.consume"],
}


def _codes_param() -> sa.BindParameter:
    return sa.bindparam("codes", type_=sa.ARRAY(sa.String))


def upgrade() -> None:
    op.create_table(
        "inventory_items",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("sku", sa.String(length=40), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("category", sa.String(length=30), nullable=False),
        sa.Column("unit", sa.String(length=20), nullable=False),
        sa.Column("unit_cost", sa.Numeric(12, 2), nullable=False),
        sa.Column("stock", sa.Integer(), nullable=False),
        sa.Column("min_stock", sa.Integer(), nullable=False),
        sa.Column("max_stock", sa.Integer(), nullable=True),
        sa.Column("location", sa.String(length=100), nullable=True),
        sa.Column("supplier", sa.String(length=150), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("stock >= 0", name=op.f("ck_inventory_items_stock_non_negative")),
        sa.CheckConstraint("min_stock >= 0", name=op.f("ck_inventory_items_min_stock_non_negative")),
        sa.CheckConstraint("max_stock IS NULL OR max_stock >= min_stock", name=op.f("ck_inventory_items_max_not_below_min")),
        sa.CheckConstraint("unit_cost >= 0", name=op.f("ck_inventory_items_unit_cost_non_negative")),
        sa.CheckConstraint(
            "category IN ('spare_part', 'consumable', 'accessory', 'tool', 'other')",
            name=op.f("ck_inventory_items_category_allowed"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_inventory_items")),
    )
    op.create_index(op.f("ix_inventory_items_sku"), "inventory_items", ["sku"], unique=True)

    op.create_table(
        "inventory_movements",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("item_id", sa.BigInteger(), nullable=False),
        sa.Column("kind", sa.String(length=12), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("stock_after", sa.Integer(), nullable=False),
        sa.Column("unit_cost", sa.Numeric(12, 2), nullable=True),
        sa.Column("notes", sa.String(length=300), nullable=True),
        sa.Column("record_id", sa.BigInteger(), nullable=True),
        sa.Column("request_id", sa.BigInteger(), nullable=True),
        sa.Column("created_by_user_id", sa.BigInteger(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("quantity <> 0", name=op.f("ck_inventory_movements_quantity_non_zero")),
        sa.CheckConstraint("stock_after >= 0", name=op.f("ck_inventory_movements_stock_after_non_negative")),
        sa.CheckConstraint("kind IN ('in', 'out', 'adjust')", name=op.f("ck_inventory_movements_kind_allowed")),
        sa.ForeignKeyConstraint(["item_id"], ["inventory_items.id"], name=op.f("fk_inventory_movements_item_id_inventory_items"), ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["record_id"], ["maintenance_records.id"], name=op.f("fk_inventory_movements_record_id_maintenance_records"), ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["request_id"], ["maintenance_requests.id"], name=op.f("fk_inventory_movements_request_id_maintenance_requests"), ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], name=op.f("fk_inventory_movements_created_by_user_id_users"), ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_inventory_movements")),
    )
    op.create_index("ix_inventory_movements_item_created", "inventory_movements", ["item_id", "created_at"])
    op.create_index(op.f("ix_inventory_movements_record_id"), "inventory_movements", ["record_id"])
    op.create_index(op.f("ix_inventory_movements_request_id"), "inventory_movements", ["request_id"])
    op.create_index(op.f("ix_inventory_movements_created_at"), "inventory_movements", ["created_at"])

    for code, name, description, module in NEW_PERMISSIONS:
        op.execute(
            sa.text(
                "INSERT INTO permissions (code, name, description, module) "
                "VALUES (:c, :n, :d, :m) ON CONFLICT (code) DO NOTHING"
            ).bindparams(c=code, n=name, d=description, m=module)
        )
    for role, codes in GRANTS.items():
        op.execute(
            sa.text(
                "INSERT INTO role_permissions (role_id, permission_id) "
                "SELECT roles.id, permissions.id FROM roles CROSS JOIN permissions "
                "WHERE roles.code = :r AND permissions.code = ANY(:codes) "
                "ON CONFLICT (role_id, permission_id) DO NOTHING"
            ).bindparams(_codes_param(), r=role).bindparams(codes=codes)
        )


def downgrade() -> None:
    codes = [p[0] for p in NEW_PERMISSIONS]
    op.execute(
        sa.text(
            "DELETE FROM role_permissions WHERE permission_id IN "
            "(SELECT id FROM permissions WHERE code = ANY(:codes))"
        ).bindparams(_codes_param()).bindparams(codes=codes)
    )
    op.execute(
        sa.text("DELETE FROM permissions WHERE code = ANY(:codes)")
        .bindparams(_codes_param())
        .bindparams(codes=codes)
    )
    op.drop_table("inventory_movements")
    op.drop_table("inventory_items")
