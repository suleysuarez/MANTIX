"""seed equipment permissions

Revision ID: e7f8a9b0c1d2
Revises: d6e7f8a9b0c1
Create Date: 2026-09-26
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "e7f8a9b0c1d2"
down_revision: Union[str, None] = "d6e7f8a9b0c1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        sa.text(
            """
            INSERT INTO permissions (code, name, description, module)
            VALUES
                ('equipment.read', 'View equipment', 'View the equipment catalog', 'equipment'),
                ('equipment.manage', 'Manage equipment', 'Create and update equipment records', 'equipment')
            ON CONFLICT (code) DO NOTHING
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
            WHERE roles.code = 'ADMIN'
              AND permissions.code IN ('equipment.read', 'equipment.manage')
            ON CONFLICT (role_id, permission_id) DO NOTHING
            """
        )
    )


def downgrade() -> None:
    op.execute(
        sa.text(
            """
            DELETE FROM role_permissions
            WHERE role_id IN (SELECT id FROM roles WHERE code = 'ADMIN')
              AND permission_id IN (
                  SELECT id FROM permissions
                  WHERE code IN ('equipment.read', 'equipment.manage')
              )
            """
        )
    )
    op.execute(
        sa.text(
            "DELETE FROM permissions WHERE code IN ('equipment.read', 'equipment.manage')")
    )
