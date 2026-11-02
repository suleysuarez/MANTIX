"""schedule runs, reschedules and estimated hours

Preventive plans only kept `next_due_at`: completing one overwrote the date and
left no trace, so plan compliance, real vs estimated duration and reschedules
could not be measured. This adds:

* `maintenance_schedules.estimated_hours` (nullable, > 0)
* `schedule_runs`: one row per completion (due date, when it was done, real hours)
* `schedule_reschedules`: one row per change of a plan's due date

Revision ID: b9d0e1f2a3c4
Revises: a8c9d0e1f2b3
Create Date: 2026-10-14 16:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "b9d0e1f2a3c4"
down_revision: Union[str, None] = "a8c9d0e1f2b3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "maintenance_schedules",
        sa.Column("estimated_hours", sa.Numeric(6, 2), nullable=True),
    )
    op.create_check_constraint(
        op.f("ck_maintenance_schedules_estimated_hours_positive"),
        "maintenance_schedules",
        "estimated_hours IS NULL OR (estimated_hours > 0 AND estimated_hours <= 999)",
    )
    op.create_table(
        "schedule_runs",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("schedule_id", sa.BigInteger(), nullable=False),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("actual_hours", sa.Numeric(6, 2), nullable=True),
        sa.Column("completed_by_user_id", sa.BigInteger(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "actual_hours IS NULL OR (actual_hours > 0 AND actual_hours <= 999)",
            name=op.f("ck_schedule_runs_actual_hours_positive"),
        ),
        sa.ForeignKeyConstraint(
            ["schedule_id"],
            ["maintenance_schedules.id"],
            name=op.f("fk_schedule_runs_schedule_id_maintenance_schedules"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["completed_by_user_id"],
            ["users.id"],
            name=op.f("fk_schedule_runs_completed_by_user_id_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_schedule_runs")),
    )
    op.create_index(op.f("ix_schedule_runs_schedule_id"), "schedule_runs", ["schedule_id"])
    op.create_index(op.f("ix_schedule_runs_due_at"), "schedule_runs", ["due_at"])
    op.create_table(
        "schedule_reschedules",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("schedule_id", sa.BigInteger(), nullable=False),
        sa.Column("old_due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("new_due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("changed_by_user_id", sa.BigInteger(), nullable=True),
        sa.Column(
            "changed_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["schedule_id"],
            ["maintenance_schedules.id"],
            name=op.f("fk_schedule_reschedules_schedule_id_maintenance_schedules"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["changed_by_user_id"],
            ["users.id"],
            name=op.f("fk_schedule_reschedules_changed_by_user_id_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_schedule_reschedules")),
    )
    op.create_index(
        op.f("ix_schedule_reschedules_schedule_id"), "schedule_reschedules", ["schedule_id"]
    )
    op.create_index(
        op.f("ix_schedule_reschedules_changed_at"), "schedule_reschedules", ["changed_at"]
    )


def downgrade() -> None:
    op.drop_table("schedule_reschedules")
    op.drop_table("schedule_runs")
    op.drop_constraint(
        op.f("ck_maintenance_schedules_estimated_hours_positive"),
        "maintenance_schedules",
        type_="check",
    )
    op.drop_column("maintenance_schedules", "estimated_hours")
