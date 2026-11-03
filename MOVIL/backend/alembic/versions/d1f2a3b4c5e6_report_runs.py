"""report runs

Every generated report (the file a user downloaded) leaves a row here, so the
Reports screen can show how many were generated, which ones are used most and the
last export, and so each export is traceable to who made it and with which filters.

Revision ID: d1f2a3b4c5e6
Revises: c0e1f2a3b4d5
Create Date: 2026-10-14 22:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "d1f2a3b4c5e6"
down_revision: Union[str, None] = "c0e1f2a3b4d5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "report_runs",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("report_key", sa.String(length=40), nullable=False),
        sa.Column("export_format", sa.String(length=10), nullable=False),
        sa.Column("filters", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("row_count", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("row_count >= 0", name=op.f("ck_report_runs_row_count_non_negative")),
        sa.CheckConstraint(
            "export_format IN ('csv', 'xlsx', 'pdf')", name=op.f("ck_report_runs_format_allowed")
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_report_runs_user_id_users"), ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_report_runs")),
    )
    op.create_index(op.f("ix_report_runs_report_key"), "report_runs", ["report_key"])
    op.create_index(op.f("ix_report_runs_created_at"), "report_runs", ["created_at"])


def downgrade() -> None:
    op.drop_table("report_runs")
