"""Add credentials and one-time email codes for mobile authentication.

Revision ID: f5b6c7d8e9a0
Revises: f4a5b6c7d8e9
Create Date: 2026-11-05
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "f5b6c7d8e9a0"
down_revision: Union[str, None] = "f4a5b6c7d8e9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("password_hash", sa.String(length=255), nullable=True))
    op.add_column("users", sa.Column("email_verified_at", sa.DateTime(timezone=True), nullable=True))
    op.create_table(
        "auth_email_codes",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("purpose", sa.String(length=10), nullable=False),
        sa.Column("code_hash", sa.String(length=255), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("purpose IN ('verify', 'reset')", name=op.f("ck_auth_email_codes_purpose_allowed")),
        sa.CheckConstraint("attempts >= 0", name=op.f("ck_auth_email_codes_attempts_non_negative")),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_auth_email_codes")),
        sa.UniqueConstraint("user_id", "purpose", name="uq_auth_email_codes_user_purpose"),
    )
    op.create_index(op.f("ix_auth_email_codes_user_id"), "auth_email_codes", ["user_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_auth_email_codes_user_id"), table_name="auth_email_codes")
    op.drop_table("auth_email_codes")
    op.drop_column("users", "email_verified_at")
    op.drop_column("users", "password_hash")
