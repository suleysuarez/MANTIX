"""add permission is active

Revision ID: 846e77ea3dc7
Revises: e7f8a9b0c1d2
Create Date: 2026-09-28 22:43:34.529343
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '846e77ea3dc7'
down_revision: Union[str, None] = 'e7f8a9b0c1d2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # `require_permission` and `user_response` already read
    # `permission.is_active` (app/api/dependencies.py, app/services/auth.py);
    # the column was simply never added. server_default backfills existing
    # rows so every current permission stays active.
    op.add_column(
        "permissions",
        sa.Column(
            "is_active",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
    )


def downgrade() -> None:
    op.drop_column("permissions", "is_active")
