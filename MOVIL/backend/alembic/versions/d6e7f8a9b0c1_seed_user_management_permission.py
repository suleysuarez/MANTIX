"""seed user management permission

Revision ID: d6e7f8a9b0c1
Revises: c4d8e2f1a9b7
Create Date: 2026-09-26
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "d6e7f8a9b0c1"
down_revision: Union[str, None] = "c4d8e2f1a9b7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        sa.text(
            """
            INSERT INTO permissions (code, name, description, module)
            VALUES (
                'users.manage',
                'Manage users',
                'List pending users and assign local application roles',
                'users'
            )
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
              AND permissions.code = 'users.manage'
            ON CONFLICT (role_id, permission_id) DO NOTHING
            """
        )
    )


def downgrade() -> None:
    op.execute(
        sa.text(
            """
            DELETE FROM role_permissions
            WHERE permission_id = (
                SELECT id FROM permissions WHERE code = 'users.manage'
            )
            AND role_id IN (SELECT id FROM roles WHERE code = 'ADMIN')
            """
        )
    )
    op.execute(sa.text("DELETE FROM permissions WHERE code = 'users.manage'"))
