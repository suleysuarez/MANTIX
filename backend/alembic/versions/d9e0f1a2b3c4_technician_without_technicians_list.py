"""The technician role no longer sees the technicians list; the supervisor does.

Revision ID: d9e0f1a2b3c4
Revises: c7d8e9f0a1b2
"""

from alembic import op
import sqlalchemy as sa

revision: str = "d9e0f1a2b3c4"
down_revision: str | None = "c7d8e9f0a1b2"
branch_labels = None
depends_on = None

_GRANT = (
    "INSERT INTO role_permissions (role_id, permission_id) "
    "SELECT r.id, p.id FROM roles r, permissions p "
    "WHERE r.code = :role AND p.code = 'tecnicos:ver' "
    "AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id AND rp.permission_id = p.id)"
)
_REVOKE = (
    "DELETE FROM role_permissions WHERE role_id = (SELECT id FROM roles WHERE code = :role) "
    "AND permission_id = (SELECT id FROM permissions WHERE code = 'tecnicos:ver')"
)


def upgrade() -> None:
    bind = op.get_bind()
    bind.execute(sa.text(_GRANT), {"role": "SUPERVISOR"})
    bind.execute(sa.text(_REVOKE), {"role": "TECHNICIAN"})


def downgrade() -> None:
    bind = op.get_bind()
    bind.execute(sa.text(_GRANT), {"role": "TECHNICIAN"})
    bind.execute(sa.text(_REVOKE), {"role": "SUPERVISOR"})
