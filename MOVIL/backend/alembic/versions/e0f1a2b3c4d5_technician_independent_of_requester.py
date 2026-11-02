"""The technician no longer inherits from the requester, so it cannot create tickets; it can export its own.

The supervisor keeps creating requests (it now holds those permissions itself).

Revision ID: e0f1a2b3c4d5
Revises: d9e0f1a2b3c4
"""

from alembic import op
import sqlalchemy as sa

revision: str = "e0f1a2b3c4d5"
down_revision: str | None = "d9e0f1a2b3c4"
branch_labels = None
depends_on = None

TECHNICIAN_GAINS = (
    "dashboard:ver",
    "perfil:ver",
    "perfil:editar",
    "tickets:ver",
    "tickets:adjuntar",
    "equipos:ver",
    "tickets:exportar",
)
SUPERVISOR_GAINS = ("solicitudes:ver", "solicitudes:crear")

_GRANT = (
    "INSERT INTO role_permissions (role_id, permission_id) "
    "SELECT r.id, p.id FROM roles r, permissions p WHERE r.code = :role AND p.code = :code "
    "AND NOT EXISTS (SELECT 1 FROM role_permissions rp WHERE rp.role_id = r.id AND rp.permission_id = p.id)"
)
_REVOKE = (
    "DELETE FROM role_permissions WHERE role_id = (SELECT id FROM roles WHERE code = :role) "
    "AND permission_id = (SELECT id FROM permissions WHERE code = :code)"
)
_PARENT = (
    "UPDATE roles SET parent_role_id = (SELECT id FROM roles WHERE code = :parent) WHERE code = 'TECHNICIAN'"
)


def upgrade() -> None:
    bind = op.get_bind()
    for code in TECHNICIAN_GAINS:
        bind.execute(sa.text(_GRANT), {"role": "TECHNICIAN", "code": code})
    for code in SUPERVISOR_GAINS:
        bind.execute(sa.text(_GRANT), {"role": "SUPERVISOR", "code": code})
    bind.execute(sa.text("UPDATE roles SET parent_role_id = NULL WHERE code = 'TECHNICIAN'"))


def downgrade() -> None:
    bind = op.get_bind()
    bind.execute(sa.text(_PARENT), {"parent": "EMPLOYEE"})
    for code in TECHNICIAN_GAINS:
        bind.execute(sa.text(_REVOKE), {"role": "TECHNICIAN", "code": code})
    for code in SUPERVISOR_GAINS:
        bind.execute(sa.text(_REVOKE), {"role": "SUPERVISOR", "code": code})
