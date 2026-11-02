"""request categories

Adds the managed `request_categories` catalog and a nullable
`maintenance_requests.category` that references it, so the pending-requests
queue can be broken down by request type.

Revision ID: a8c9d0e1f2b3
Revises: f1a2b3c4d5e6
Create Date: 2026-10-14 10:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a8c9d0e1f2b3"
down_revision: Union[str, None] = "f1a2b3c4d5e6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "request_categories",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("code", sa.String(length=30), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_request_categories")),
        sa.UniqueConstraint("code", name=op.f("uq_request_categories_code")),
    )
    op.execute(
        """
        INSERT INTO request_categories (code, name) VALUES
            ('hardware', 'Hardware'),
            ('software', 'Software'),
            ('network', 'Red y conectividad'),
            ('peripherals', 'Periféricos'),
            ('access', 'Accesos y cuentas'),
            ('other', 'Otro')
        """
    )
    op.add_column(
        "maintenance_requests",
        sa.Column("category", sa.String(length=30), nullable=True),
    )
    op.create_foreign_key(
        op.f("fk_maintenance_requests_category_request_categories"),
        "maintenance_requests",
        "request_categories",
        ["category"],
        ["code"],
        onupdate="CASCADE",
        ondelete="RESTRICT",
    )
    op.create_index(
        op.f("ix_maintenance_requests_category"), "maintenance_requests", ["category"]
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_maintenance_requests_category"), "maintenance_requests")
    op.drop_constraint(
        op.f("fk_maintenance_requests_category_request_categories"),
        "maintenance_requests",
        type_="foreignkey",
    )
    op.drop_column("maintenance_requests", "category")
    op.drop_table("request_categories")
