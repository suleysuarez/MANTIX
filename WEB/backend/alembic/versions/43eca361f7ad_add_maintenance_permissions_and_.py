"""add maintenance permissions and constraints

Revision ID: 43eca361f7ad
Revises: aa87786e021b
Create Date: 2026-09-28 22:43:37.092172
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '43eca361f7ad'
down_revision: Union[str, None] = 'aa87786e021b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        sa.text(
            """
            INSERT INTO permissions (code, name, description, module)
            VALUES
                ('maintenance.read', 'View maintenance requests',
                 'View maintenance tickets and their history', 'maintenance'),
                ('maintenance.create', 'Create maintenance requests',
                 'Submit a new maintenance request', 'maintenance'),
                ('maintenance.manage', 'Manage maintenance requests',
                 'Transition status, assign technicians and log work',
                 'maintenance'),
                ('technicians.manage', 'Manage technicians',
                 'Create and update technician profiles', 'technicians')
            ON CONFLICT (code) DO NOTHING
            """
        )
    )

    # RBAC matrix:
    #   ADMIN / SUPERVISOR: maintenance.read, .create, .manage, technicians.manage
    #   TECHNICIAN:         maintenance.read, .manage (own ticket only, enforced
    #                       in app/services/maintenance.py, not by this grant)
    #   EMPLOYEE:           maintenance.read, .create
    op.execute(
        sa.text(
            """
            INSERT INTO role_permissions (role_id, permission_id)
            SELECT roles.id, permissions.id
            FROM roles
            CROSS JOIN permissions
            WHERE roles.code IN ('ADMIN', 'SUPERVISOR')
              AND permissions.code IN (
                  'maintenance.read', 'maintenance.create',
                  'maintenance.manage', 'technicians.manage'
              )
            ON CONFLICT (role_id, permission_id) DO NOTHING
            """
        )
    )
    # TECHNICIAN and EMPLOYEE also get equipment.read: both need to browse
    # the equipment catalog (to pick which asset a ticket is about, or to
    # see what they're working on) without being able to manage it.
    op.execute(
        sa.text(
            """
            INSERT INTO role_permissions (role_id, permission_id)
            SELECT roles.id, permissions.id
            FROM roles
            CROSS JOIN permissions
            WHERE roles.code = 'TECHNICIAN'
              AND permissions.code IN (
                  'maintenance.read', 'maintenance.manage', 'equipment.read'
              )
            ON CONFLICT (role_id, permission_id) DO NOTHING
            """
        )
    )
    op.execute(
        sa.text(
            """
            INSERT INTO role_permissions (role_id, permission_id)
            SELECT roles.id, permissions.id
            FROM roles
            CROSS JOIN permissions
            WHERE roles.code = 'EMPLOYEE'
              AND permissions.code IN (
                  'maintenance.read', 'maintenance.create', 'equipment.read'
              )
            ON CONFLICT (role_id, permission_id) DO NOTHING
            """
        )
    )

    # No prior generator existed for ticket_number; the service formats
    # this as TCK-{year}-{nextval:06d}.
    op.execute("CREATE SEQUENCE maintenance_ticket_number_seq")

    op.create_check_constraint(
        op.f("ck_maintenance_requests_priority_allowed"),
        "maintenance_requests",
        "priority IN ('low', 'medium', 'high', 'critical')",
    )
    op.create_check_constraint(
        op.f("ck_maintenance_requests_status_allowed"),
        "maintenance_requests",
        "status IN ('submitted', 'triaged', 'assigned', 'in_progress', "
        "'waiting', 'resolved', 'closed', 'cancelled')",
    )
    op.create_check_constraint(
        op.f("ck_ticket_status_history_to_status_allowed"),
        "ticket_status_history",
        "to_status IN ('submitted', 'triaged', 'assigned', 'in_progress', "
        "'waiting', 'resolved', 'closed', 'cancelled')",
    )
    op.create_check_constraint(
        op.f("ck_maintenance_records_work_type_allowed"),
        "maintenance_records",
        "work_type IN ('corrective', 'preventive', 'inspection', "
        "'installation', 'recovery', 'other')",
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("ck_maintenance_records_work_type_allowed"),
        "maintenance_records",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_ticket_status_history_to_status_allowed"),
        "ticket_status_history",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_maintenance_requests_status_allowed"),
        "maintenance_requests",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_maintenance_requests_priority_allowed"),
        "maintenance_requests",
        type_="check",
    )
    op.execute("DROP SEQUENCE maintenance_ticket_number_seq")
    # equipment.read is an earlier permission, not deleted below - only drop
    # the TECHNICIAN/EMPLOYEE grants this migration added for it.
    op.execute(
        sa.text(
            """
            DELETE FROM role_permissions
            WHERE role_id IN (
                SELECT id FROM roles WHERE code IN ('TECHNICIAN', 'EMPLOYEE')
            )
              AND permission_id IN (
                  SELECT id FROM permissions WHERE code = 'equipment.read'
              )
            """
        )
    )
    op.execute(
        sa.text(
            """
            DELETE FROM role_permissions
            WHERE permission_id IN (
                SELECT id FROM permissions
                WHERE code IN (
                    'maintenance.read', 'maintenance.create',
                    'maintenance.manage', 'technicians.manage'
                )
            )
            """
        )
    )
    op.execute(
        sa.text(
            """
            DELETE FROM permissions
            WHERE code IN (
                'maintenance.read', 'maintenance.create',
                'maintenance.manage', 'technicians.manage'
            )
            """
        )
    )
