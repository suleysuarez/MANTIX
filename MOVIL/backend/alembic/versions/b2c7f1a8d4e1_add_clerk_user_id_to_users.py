"""add clerk user id to users

Revision ID: b2c7f1a8d4e1
Revises: a31347ed99e6
Create Date: 2026-09-23
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "b2c7f1a8d4e1"
down_revision: Union[str, None] = "a31347ed99e6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("clerk_user_id", sa.String(length=255), nullable=True),
    )
    op.create_index(
        op.f("ix_users_clerk_user_id"),
        "users",
        ["clerk_user_id"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_users_clerk_user_id"), table_name="users")
    op.drop_column("users", "clerk_user_id")
