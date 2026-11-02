"""seed roles and equipment types

Revision ID: aa87786e021b
Revises: 846e77ea3dc7
Create Date: 2026-09-28 22:43:35.756876
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'aa87786e021b'
down_revision: Union[str, None] = '846e77ea3dc7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # No prior migration ever inserted a role. `ClerkAuthService.
    # _assign_bootstrap_admin` (app/services/auth.py) 500s on a fresh
    # database because it looks up `roles.code = 'ADMIN'` and finds nothing.
    op.execute(
        sa.text(
            """
            INSERT INTO roles (code, name, description, is_active)
            VALUES
                ('ADMIN', 'Administrator',
                 'Full access to all MANTIX modules', true),
                ('SUPERVISOR', 'Supervisor',
                 'Manages equipment and the maintenance workflow', true),
                ('TECHNICIAN', 'Technician',
                 'Performs assigned maintenance work', true),
                ('EMPLOYEE', 'Employee',
                 'Requests maintenance and views own tickets', true)
            ON CONFLICT (code) DO NOTHING
            """
        )
    )

    # d6e7f8a9b0c1 and e7f8a9b0c1d2 already tried to link these permissions
    # to ADMIN, but silently inserted nothing because ADMIN did not exist
    # yet at that point. Re-run the same link now that it does.
    op.execute(
        sa.text(
            """
            INSERT INTO role_permissions (role_id, permission_id)
            SELECT roles.id, permissions.id
            FROM roles
            CROSS JOIN permissions
            WHERE roles.code = 'ADMIN'
              AND permissions.code IN
                  ('users.manage', 'equipment.read', 'equipment.manage')
            ON CONFLICT (role_id, permission_id) DO NOTHING
            """
        )
    )
    # SUPERVISOR also manages equipment day-to-day (RBAC matrix in
    # docs/authentication.md / the architecture plan for this migration set).
    op.execute(
        sa.text(
            """
            INSERT INTO role_permissions (role_id, permission_id)
            SELECT roles.id, permissions.id
            FROM roles
            CROSS JOIN permissions
            WHERE roles.code = 'SUPERVISOR'
              AND permissions.code IN ('equipment.read', 'equipment.manage')
            ON CONFLICT (role_id, permission_id) DO NOTHING
            """
        )
    )

    # POST /equipment is otherwise unusable out of the box: the create form
    # needs at least one equipment type to reference.
    op.execute(
        sa.text(
            """
            INSERT INTO equipment_types (code, name, description, is_active)
            VALUES
                ('LAPTOP', 'Laptop', 'Portable computer', true),
                ('DESKTOP', 'Desktop', 'Desktop workstation', true),
                ('MONITOR', 'Monitor', 'Display device', true),
                ('PRINTER', 'Printer', 'Printer or multifunction device', true),
                ('SERVER', 'Server', 'Server hardware', true),
                ('NETWORK_EQUIPMENT', 'Network Equipment',
                 'Switches, routers and access points', true),
                ('MOBILE_DEVICE', 'Mobile Device', 'Phones and tablets', true),
                ('PERIPHERAL', 'Peripheral',
                 'Keyboards, mice and other peripherals', true),
                ('OTHER', 'Other',
                 'Equipment that does not fit another category', true)
            ON CONFLICT (code) DO NOTHING
            """
        )
    )


def downgrade() -> None:
    op.execute(
        sa.text(
            """
            DELETE FROM equipment_types
            WHERE code IN (
                'LAPTOP', 'DESKTOP', 'MONITOR', 'PRINTER', 'SERVER',
                'NETWORK_EQUIPMENT', 'MOBILE_DEVICE', 'PERIPHERAL', 'OTHER'
            )
            AND NOT EXISTS (
                SELECT 1 FROM equipment
                WHERE equipment.equipment_type_id = equipment_types.id
            )
            """
        )
    )
    op.execute(
        sa.text(
            """
            DELETE FROM role_permissions
            WHERE role_id IN (
                SELECT id FROM roles WHERE code IN ('ADMIN', 'SUPERVISOR')
            )
              AND permission_id IN (
                  SELECT id FROM permissions
                  WHERE code IN
                      ('users.manage', 'equipment.read', 'equipment.manage')
              )
            """
        )
    )
    op.execute(
        sa.text(
            """
            DELETE FROM roles
            WHERE code IN ('ADMIN', 'SUPERVISOR', 'TECHNICIAN', 'EMPLOYEE')
              AND NOT EXISTS (
                  SELECT 1 FROM user_roles WHERE user_roles.role_id = roles.id
              )
            """
        )
    )
