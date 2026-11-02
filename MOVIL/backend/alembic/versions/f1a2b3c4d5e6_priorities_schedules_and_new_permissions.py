"""priorities catalog, preventive schedules, indexes and new permissions

Revision ID: f1a2b3c4d5e6
Revises: 43eca361f7ad
Create Date: 2026-10-11
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "f1a2b3c4d5e6"
down_revision: Union[str, None] = "43eca361f7ad"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

NEW_PERMISSIONS = [
    ("priorities.manage", "Manage priorities", "Create and update ticket priorities", "priorities"),
    ("dashboard.read", "View dashboard", "View aggregated operational metrics", "dashboard"),
    ("reports.read", "View reports", "Generate and export reports and data", "reports"),
    ("audit.read", "View audit log", "Query the audit trail", "audit"),
    ("attachments.write", "Manage attachments", "Upload and delete attachments", "attachments"),
    ("schedules.manage", "Manage maintenance schedules", "Manage preventive maintenance plans", "schedules"),
]

GRANTS = {
    "ADMIN": [p[0] for p in NEW_PERMISSIONS],
    "SUPERVISOR": [
        "dashboard.read",
        "reports.read",
        "audit.read",
        "attachments.write",
        "schedules.manage",
    ],
    "TECHNICIAN": ["dashboard.read", "attachments.write"],
    "EMPLOYEE": ["attachments.write"],
}


def _codes_param() -> sa.BindParameter:
    return sa.bindparam("codes", type_=sa.ARRAY(sa.String))


def upgrade() -> None:
    op.create_table(
        "priorities",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("code", sa.String(length=20), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("level", sa.Integer(), nullable=False),
        sa.Column("sla_hours", sa.Integer(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("level >= 1", name=op.f("ck_priorities_level_positive")),
        sa.CheckConstraint("sla_hours IS NULL OR sla_hours > 0", name=op.f("ck_priorities_sla_positive")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_priorities")),
        sa.UniqueConstraint("code", name=op.f("uq_priorities_code")),
    )
    op.execute(
        """
        INSERT INTO priorities (code, name, description, level, sla_hours, is_active) VALUES
            ('low', 'Low', 'Minor issue, no operational impact', 1, 120, true),
            ('medium', 'Medium', 'Degraded service with a workaround', 2, 72, true),
            ('high', 'High', 'Significant impact on daily work', 3, 24, true),
            ('critical', 'Critical', 'Outage or blocked critical operation', 4, 4, true)
        """
    )
    op.drop_constraint(op.f("ck_maintenance_requests_priority_allowed"), "maintenance_requests", type_="check")
    op.create_foreign_key(
        op.f("fk_maintenance_requests_priority_priorities"),
        "maintenance_requests",
        "priorities",
        ["priority"],
        ["code"],
        onupdate="CASCADE",
        ondelete="RESTRICT",
    )
    op.create_index(
        "ix_maintenance_requests_status_priority_created",
        "maintenance_requests",
        ["status", "priority", "created_at"],
    )
    op.create_index(
        "ix_maintenance_requests_equipment_created",
        "maintenance_requests",
        ["equipment_id", "created_at"],
    )
    op.create_index("ix_audit_logs_entity", "audit_logs", ["entity_type", "entity_id"])
    op.create_index("ix_audit_logs_created_at", "audit_logs", ["created_at"])

    op.create_table(
        "maintenance_schedules",
        sa.Column("id", sa.BigInteger(), sa.Identity(always=False), nullable=False),
        sa.Column("equipment_id", sa.BigInteger(), nullable=False),
        sa.Column("technician_id", sa.BigInteger(), nullable=True),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("interval_days", sa.Integer(), nullable=False),
        sa.Column("remind_days_before", sa.Integer(), server_default="3", nullable=False),
        sa.Column("next_due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_reminded_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        sa.Column("created_by_user_id", sa.BigInteger(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("interval_days > 0", name=op.f("ck_maintenance_schedules_interval_positive")),
        sa.CheckConstraint("remind_days_before >= 0", name=op.f("ck_maintenance_schedules_remind_non_negative")),
        sa.ForeignKeyConstraint(["equipment_id"], ["equipment.id"], name=op.f("fk_maintenance_schedules_equipment_id_equipment"), ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["technician_id"], ["technicians.id"], name=op.f("fk_maintenance_schedules_technician_id_technicians"), ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], name=op.f("fk_maintenance_schedules_created_by_user_id_users"), ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_maintenance_schedules")),
    )
    op.create_index("ix_maintenance_schedules_equipment_id", "maintenance_schedules", ["equipment_id"])
    op.create_index("ix_maintenance_schedules_active_due", "maintenance_schedules", ["is_active", "next_due_at"])

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
    op.drop_table("maintenance_schedules")
    op.drop_index("ix_audit_logs_created_at", table_name="audit_logs")
    op.drop_index("ix_audit_logs_entity", table_name="audit_logs")
    op.drop_index("ix_maintenance_requests_equipment_created", table_name="maintenance_requests")
    op.drop_index("ix_maintenance_requests_status_priority_created", table_name="maintenance_requests")
    op.drop_constraint(op.f("fk_maintenance_requests_priority_priorities"), "maintenance_requests", type_="foreignkey")
    op.create_check_constraint(
        op.f("ck_maintenance_requests_priority_allowed"),
        "maintenance_requests",
        "priority IN ('low', 'medium', 'high', 'critical')",
    )
    op.drop_table("priorities")
