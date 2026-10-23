"""organization: company name only

Reports no longer show the legal name or the NIT, so the Settings screen stops
asking for them and the columns are dropped.

Revision ID: e3b4c5d6e7f8
Revises: e2a3b4c5d6f7
Create Date: 2026-10-15 12:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "e3b4c5d6e7f8"
down_revision: Union[str, None] = "e2a3b4c5d6f7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_column("organization_settings", "legal_name")
    op.drop_column("organization_settings", "tax_id")


def downgrade() -> None:
    op.add_column("organization_settings", sa.Column("tax_id", sa.String(length=30), nullable=True))
    op.add_column("organization_settings", sa.Column("legal_name", sa.String(length=200), nullable=True))
