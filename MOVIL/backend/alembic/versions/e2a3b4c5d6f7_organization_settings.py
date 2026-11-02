"""organization settings

The company name, legal name and tax id (NIT) that report headers show. A single row
that the Settings screen edits; reports fall back to "Mantix" while it is empty.

Revision ID: e2a3b4c5d6f7
Revises: d1f2a3b4c5e6
Create Date: 2026-10-15 09:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "e2a3b4c5d6f7"
down_revision: Union[str, None] = "d1f2a3b4c5e6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "organization_settings",
        sa.Column("id", sa.BigInteger(), nullable=False),
        sa.Column("company_name", sa.String(length=150), nullable=False),
        sa.Column("legal_name", sa.String(length=200), nullable=True),
        sa.Column("tax_id", sa.String(length=30), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_by_user_id", sa.BigInteger(), nullable=True),
        sa.CheckConstraint("id = 1", name=op.f("ck_organization_settings_single_row")),
        sa.ForeignKeyConstraint(
            ["updated_by_user_id"],
            ["users.id"],
            name=op.f("fk_organization_settings_updated_by_user_id_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_organization_settings")),
    )


def downgrade() -> None:
    op.drop_table("organization_settings")
