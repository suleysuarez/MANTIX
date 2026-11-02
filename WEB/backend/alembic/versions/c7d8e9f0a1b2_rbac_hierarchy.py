"""rbac: role inheritance, `recurso:accion` permissions and the AUDITOR role

Expand step of expand-and-contract: the new permissions are added next to the legacy dotted
ones (which keep working) and the roles get a parent. A later migration retires the legacy
permissions once every endpoint and screen uses the new ones.

* roles.parent_role_id (inheritance), roles.is_system (the five base roles)
* permissions.resource / permissions.action
* idempotent seed: permissions, the AUDITOR role, parents and each role's own grants.
  Re-running it never removes or edits what an administrator changed.

Revision ID: c7d8e9f0a1b2
Revises: b6c7d8e9f0a1
Create Date: 2026-10-15 20:00:00.000000

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "c7d8e9f0a1b2"
down_revision: str | None = "b6c7d8e9f0a1"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Snapshot of app/core/permissions.py at the time of this migration.
PERMISSIONS = [
    ("dashboard:ver", "Dashboard: Ver lo propio", "dashboard", "ver"),
    ("dashboard:ver_todos", "Dashboard: Ver todo", "dashboard", "ver_todos"),
    ("equipos:ver", "Equipos: Ver", "equipos", "ver"),
    ("equipos:crear", "Equipos: Crear", "equipos", "crear"),
    ("equipos:editar", "Equipos: Editar", "equipos", "editar"),
    ("equipos:asignar", "Equipos: Asignar", "equipos", "asignar"),
    ("equipos:adjuntar", "Equipos: Adjuntar archivos", "equipos", "adjuntar"),
    ("equipos:exportar", "Equipos: Exportar", "equipos", "exportar"),
    ("equipos:importar", "Equipos: Importar", "equipos", "importar"),
    ("solicitudes:ver", "Solicitudes: Ver lo propio", "solicitudes", "ver"),
    ("solicitudes:ver_todos", "Solicitudes: Ver todo", "solicitudes", "ver_todos"),
    ("solicitudes:crear", "Solicitudes: Crear", "solicitudes", "crear"),
    ("solicitudes:editar", "Solicitudes: Editar", "solicitudes", "editar"),
    (
        "solicitudes:aprobar",
        "Solicitudes: Aprobar o rechazar",
        "solicitudes",
        "aprobar",
    ),
    ("tickets:ver", "Tickets: Ver lo propio", "tickets", "ver"),
    ("tickets:ver_asignados", "Tickets: Ver lo asignado", "tickets", "ver_asignados"),
    ("tickets:ver_todos", "Tickets: Ver todo", "tickets", "ver_todos"),
    ("tickets:editar", "Tickets: Editar", "tickets", "editar"),
    ("tickets:asignar", "Tickets: Asignar", "tickets", "asignar"),
    ("tickets:cambiar_estado", "Tickets: Cambiar estado", "tickets", "cambiar_estado"),
    ("tickets:adjuntar", "Tickets: Adjuntar archivos", "tickets", "adjuntar"),
    ("tickets:exportar", "Tickets: Exportar", "tickets", "exportar"),
    ("tecnicos:ver", "Técnicos: Ver", "tecnicos", "ver"),
    ("tecnicos:crear", "Técnicos: Crear", "tecnicos", "crear"),
    ("tecnicos:editar", "Técnicos: Editar", "tecnicos", "editar"),
    ("tecnicos:exportar", "Técnicos: Exportar", "tecnicos", "exportar"),
    ("mantenimiento:ver", "Mantenimiento: Ver", "mantenimiento", "ver"),
    ("mantenimiento:crear", "Mantenimiento: Crear", "mantenimiento", "crear"),
    ("mantenimiento:editar", "Mantenimiento: Editar", "mantenimiento", "editar"),
    ("inventario:ver", "Inventario: Ver", "inventario", "ver"),
    ("inventario:crear", "Inventario: Crear", "inventario", "crear"),
    ("inventario:editar", "Inventario: Editar", "inventario", "editar"),
    ("inventario:eliminar", "Inventario: Eliminar", "inventario", "eliminar"),
    ("inventario:consumir", "Inventario: Consumir", "inventario", "consumir"),
    ("inventario:importar", "Inventario: Importar", "inventario", "importar"),
    ("inventario:exportar", "Inventario: Exportar", "inventario", "exportar"),
    ("reportes:ver", "Reportes: Ver", "reportes", "ver"),
    ("reportes:exportar", "Reportes: Exportar", "reportes", "exportar"),
    ("usuarios:ver", "Usuarios: Ver", "usuarios", "ver"),
    ("usuarios:crear", "Usuarios: Crear", "usuarios", "crear"),
    ("usuarios:editar", "Usuarios: Editar", "usuarios", "editar"),
    (
        "usuarios:cambiar_estado",
        "Usuarios: Cambiar estado",
        "usuarios",
        "cambiar_estado",
    ),
    ("usuarios:asignar", "Usuarios: Asignar", "usuarios", "asignar"),
    ("perfil:ver", "Perfil: Ver", "perfil", "ver"),
    ("perfil:editar", "Perfil: Editar", "perfil", "editar"),
    ("configuracion:ver", "Configuración: Ver", "configuracion", "ver"),
    ("configuracion:editar", "Configuración: Editar", "configuracion", "editar"),
    ("auditoria:ver", "Auditoría: Ver", "auditoria", "ver"),
]

ROLES = [
    (
        "EMPLOYEE",
        "Solicitante",
        "Crea y ve solo sus solicitudes y tickets; edita su perfil",
    ),
    ("TECHNICIAN", "Técnico", "Trabaja los tickets y mantenimientos asignados a él"),
    (
        "SUPERVISOR",
        "Supervisor",
        "Ve y gestiona toda la operación: asigna, aprueba y reporta",
    ),
    ("ADMIN", "Administrador", "Gestiona usuarios, roles, configuración y auditoría"),
    ("AUDITOR", "Auditor", "Solo lectura de reportes y auditoría"),
]

PARENTS = {
    "ADMIN": "SUPERVISOR",
    "AUDITOR": None,
    "EMPLOYEE": None,
    "SUPERVISOR": "TECHNICIAN",
    "TECHNICIAN": "EMPLOYEE",
}

OWN = {
    "ADMIN": [
        "auditoria:ver",
        "configuracion:editar",
        "configuracion:ver",
        "equipos:importar",
        "inventario:eliminar",
        "inventario:importar",
        "usuarios:asignar",
        "usuarios:cambiar_estado",
        "usuarios:crear",
        "usuarios:editar",
        "usuarios:ver",
    ],
    "AUDITOR": [
        "auditoria:ver",
        "dashboard:ver",
        "dashboard:ver_todos",
        "perfil:editar",
        "perfil:ver",
        "reportes:exportar",
        "reportes:ver",
    ],
    "EMPLOYEE": [
        "dashboard:ver",
        "equipos:ver",
        "perfil:editar",
        "perfil:ver",
        "solicitudes:crear",
        "solicitudes:ver",
        "tickets:adjuntar",
        "tickets:ver",
    ],
    "SUPERVISOR": [
        "dashboard:ver_todos",
        "equipos:adjuntar",
        "equipos:asignar",
        "equipos:crear",
        "equipos:editar",
        "equipos:exportar",
        "inventario:crear",
        "inventario:editar",
        "inventario:exportar",
        "mantenimiento:crear",
        "mantenimiento:editar",
        "reportes:exportar",
        "reportes:ver",
        "solicitudes:aprobar",
        "solicitudes:editar",
        "solicitudes:ver_todos",
        "tecnicos:crear",
        "tecnicos:editar",
        "tecnicos:exportar",
        "tickets:asignar",
        "tickets:exportar",
        "tickets:ver_todos",
    ],
    "TECHNICIAN": [
        "inventario:consumir",
        "inventario:ver",
        "mantenimiento:ver",
        "tecnicos:ver",
        "tickets:cambiar_estado",
        "tickets:editar",
        "tickets:ver_asignados",
    ],
}

# English names given by the first seed; translated only while nobody renamed them.
ENGLISH_NAMES = {
    "ADMIN": "Administrator",
    "SUPERVISOR": "Supervisor",
    "TECHNICIAN": "Technician",
    "EMPLOYEE": "Employee",
}


def upgrade() -> None:
    op.add_column(
        "roles",
        sa.Column(
            "is_system", sa.Boolean(), server_default=sa.text("false"), nullable=False
        ),
    )
    op.add_column("roles", sa.Column("parent_role_id", sa.BigInteger(), nullable=True))
    op.create_foreign_key(
        op.f("fk_roles_parent_role_id_roles"),
        "roles",
        "roles",
        ["parent_role_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_index(op.f("ix_roles_parent_role_id"), "roles", ["parent_role_id"])
    op.create_check_constraint(
        op.f("ck_roles_no_self_parent"),
        "roles",
        "parent_role_id IS NULL OR parent_role_id <> id",
    )
    op.add_column("permissions", sa.Column("resource", sa.String(50), nullable=True))
    op.add_column("permissions", sa.Column("action", sa.String(50), nullable=True))

    bind = op.get_bind()
    bind.execute(
        sa.text(
            "INSERT INTO permissions (code, name, module, resource, action, is_active) "
            "VALUES (:code, :name, :resource, :resource, :action, true) "
            "ON CONFLICT (code) DO NOTHING"
        ),
        [
            {"code": c, "name": n, "resource": r, "action": a}
            for c, n, r, a in PERMISSIONS
        ],
    )
    for code, name, description in ROLES:
        bind.execute(
            sa.text(
                "INSERT INTO roles (code, name, description, is_active, is_system) "
                "VALUES (:code, :name, :description, true, true) ON CONFLICT (code) DO NOTHING"
            ),
            {"code": code, "name": name, "description": description},
        )
        # Spanish display names, only where the first seed's English one is still in place.
        if code in ENGLISH_NAMES:
            bind.execute(
                sa.text(
                    "UPDATE roles SET name = :name, description = :description "
                    "WHERE code = :code AND name = :english"
                ),
                {
                    "code": code,
                    "name": name,
                    "description": description,
                    "english": ENGLISH_NAMES[code],
                },
            )
    bind.execute(
        sa.text("UPDATE roles SET is_system = true WHERE code = ANY(:codes)"),
        {"codes": [code for code, _, _ in ROLES]},
    )
    for code, parent in PARENTS.items():
        if parent is not None:
            bind.execute(
                sa.text(
                    "UPDATE roles child SET parent_role_id = parent.id FROM roles parent "
                    "WHERE child.code = :child AND parent.code = :parent "
                    "AND child.parent_role_id IS NULL"
                ),
                {"child": code, "parent": parent},
            )
    for role, codes in OWN.items():
        bind.execute(
            sa.text(
                "INSERT INTO role_permissions (role_id, permission_id) "
                "SELECT r.id, p.id FROM roles r JOIN permissions p ON p.code = :permission "
                "WHERE r.code = :role ON CONFLICT (role_id, permission_id) DO NOTHING"
            ),
            [{"role": role, "permission": code} for code in codes],
        )


def downgrade() -> None:
    bind = op.get_bind()
    bind.execute(
        sa.text("DELETE FROM permissions WHERE code = ANY(:codes)"),
        {"codes": [c for c, _, _, _ in PERMISSIONS]},
    )
    bind.execute(sa.text("DELETE FROM roles WHERE code = 'AUDITOR'"))
    op.drop_column("permissions", "action")
    op.drop_column("permissions", "resource")
    op.drop_constraint(op.f("ck_roles_no_self_parent"), "roles", type_="check")
    op.drop_index(op.f("ix_roles_parent_role_id"), table_name="roles")
    op.drop_constraint(
        op.f("fk_roles_parent_role_id_roles"), "roles", type_="foreignkey"
    )
    op.drop_column("roles", "parent_role_id")
    op.drop_column("roles", "is_system")
