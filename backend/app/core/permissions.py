"""Canonical role -> permission matrix.

The database is the runtime source of truth (roles and permissions are rows
seeded by migrations and editable by administrators). This module records the
*intended* default matrix so that:

* tests can assert the seeded rows match it (`MIGRATED_DATABASE_URL`),
* tests can assert every endpoint enforces what the matrix says,
* the README/docs matrix has one place to be generated from.

Changing a default grant means: new migration + update this file.
"""

from types import MappingProxyType

from app.core.authz import ADMIN, AUDITOR, EMPLOYEE, SUPERVISOR, TECHNICIAN

# Permission codes (the strings stored in `permissions.code`).
EQUIPMENT_READ = "equipment.read"
EQUIPMENT_MANAGE = "equipment.manage"
MAINTENANCE_READ = "maintenance.read"
MAINTENANCE_CREATE = "maintenance.create"
MAINTENANCE_MANAGE = "maintenance.manage"
TECHNICIANS_MANAGE = "technicians.manage"
USERS_MANAGE = "users.manage"
PRIORITIES_MANAGE = "priorities.manage"
DASHBOARD_READ = "dashboard.read"
REPORTS_READ = "reports.read"
AUDIT_READ = "audit.read"
ATTACHMENTS_WRITE = "attachments.write"
SCHEDULES_MANAGE = "schedules.manage"
INVENTORY_READ = "inventory.read"
INVENTORY_MANAGE = "inventory.manage"
INVENTORY_CONSUME = "inventory.consume"

ALL_PERMISSIONS = frozenset(
    {
        EQUIPMENT_READ,
        EQUIPMENT_MANAGE,
        MAINTENANCE_READ,
        MAINTENANCE_CREATE,
        MAINTENANCE_MANAGE,
        TECHNICIANS_MANAGE,
        USERS_MANAGE,
        PRIORITIES_MANAGE,
        DASHBOARD_READ,
        REPORTS_READ,
        AUDIT_READ,
        ATTACHMENTS_WRITE,
        SCHEDULES_MANAGE,
        INVENTORY_READ,
        INVENTORY_MANAGE,
        INVENTORY_CONSUME,
    }
)

#: `maintenance.manage` for a TECHNICIAN only applies to tickets assigned to
#: them; that scoping is enforced in `MaintenanceService`, not by this grant.
ROLE_PERMISSIONS = MappingProxyType(
    {
        ADMIN: ALL_PERMISSIONS,
        SUPERVISOR: frozenset(
            {
                EQUIPMENT_READ,
                EQUIPMENT_MANAGE,
                MAINTENANCE_READ,
                MAINTENANCE_CREATE,
                MAINTENANCE_MANAGE,
                TECHNICIANS_MANAGE,
                DASHBOARD_READ,
                REPORTS_READ,
                AUDIT_READ,
                ATTACHMENTS_WRITE,
                SCHEDULES_MANAGE,
                INVENTORY_READ,
                INVENTORY_MANAGE,
                INVENTORY_CONSUME,
            }
        ),
        TECHNICIAN: frozenset(
            {
                EQUIPMENT_READ,
                MAINTENANCE_READ,
                MAINTENANCE_MANAGE,
                DASHBOARD_READ,
                ATTACHMENTS_WRITE,
                INVENTORY_READ,
                INVENTORY_CONSUME,
            }
        ),
        EMPLOYEE: frozenset(
            {
                EQUIPMENT_READ,
                MAINTENANCE_READ,
                MAINTENANCE_CREATE,
                ATTACHMENTS_WRITE,
            }
        ),
    }
)


# -- RBAC with inheritance: `recurso:accion` catalogue ---------------------------------------
#
# The legacy dotted codes above stay valid while endpoints move to the codes below
# ("expand and contract"): both sets are seeded and both are resolved. A final migration
# retires the legacy ones once every endpoint and screen uses the new ones.

RESOURCE_LABELS = {
    "dashboard": "Dashboard",
    "equipos": "Equipos",
    "solicitudes": "Solicitudes",
    "tickets": "Tickets",
    "tecnicos": "Técnicos",
    "mantenimiento": "Mantenimiento",
    "inventario": "Inventario",
    "reportes": "Reportes",
    "usuarios": "Usuarios",
    "perfil": "Perfil",
    "configuracion": "Configuración",
    "auditoria": "Auditoría",
}

ACTION_LABELS = {
    "ver": "Ver",
    "ver_asignados": "Ver lo asignado",
    "ver_todos": "Ver todo",
    "crear": "Crear",
    "editar": "Editar",
    "eliminar": "Eliminar",
    "exportar": "Exportar",
    "importar": "Importar",
    "asignar": "Asignar",
    "cambiar_estado": "Cambiar estado",
    "aprobar": "Aprobar o rechazar",
    "adjuntar": "Adjuntar archivos",
    "consumir": "Consumir",
}

#: resource -> actions that exist for it (nothing is created without a use).
RESOURCE_ACTIONS = MappingProxyType(
    {
        "dashboard": ("ver", "ver_todos"),
        "equipos": (
            "ver",
            "crear",
            "editar",
            "asignar",
            "adjuntar",
            "exportar",
            "importar",
        ),
        "solicitudes": ("ver", "ver_todos", "crear", "editar", "aprobar"),
        "tickets": (
            "ver",
            "ver_asignados",
            "ver_todos",
            "editar",
            "asignar",
            "cambiar_estado",
            "adjuntar",
            "exportar",
        ),
        "tecnicos": ("ver", "crear", "editar", "exportar"),
        "mantenimiento": ("ver", "crear", "editar"),
        "inventario": (
            "ver",
            "crear",
            "editar",
            "eliminar",
            "consumir",
            "importar",
            "exportar",
        ),
        "reportes": ("ver", "exportar"),
        "usuarios": ("ver", "crear", "editar", "cambiar_estado", "asignar"),
        "perfil": ("ver", "editar"),
        "configuracion": ("ver", "editar"),
        "auditoria": ("ver",),
    }
)


def permission_code(resource: str, action: str) -> str:
    return f"{resource}:{action}"


#: Resources whose `ver` means "only what is mine"; the wider scopes are `ver_asignados`/`ver_todos`.
SCOPED_RESOURCES = frozenset({"dashboard", "solicitudes", "tickets"})


def permission_name(resource: str, action: str) -> str:
    label = ACTION_LABELS[action]
    if action == "ver" and resource in SCOPED_RESOURCES:
        label = "Ver lo propio"
    return f"{RESOURCE_LABELS[resource]}: {label}"


#: Every `recurso:accion` code, in catalogue order.
CATALOG = tuple(
    permission_code(resource, action)
    for resource, actions in RESOURCE_ACTIONS.items()
    for action in actions
)
CATALOG_SET = frozenset(CATALOG)

#: Role -> parent. A role inherits everything its ancestors have.
ROLE_PARENTS = MappingProxyType(
    {
        EMPLOYEE: None,
        TECHNICIAN: EMPLOYEE,
        SUPERVISOR: TECHNICIAN,
        ADMIN: SUPERVISOR,
        AUDITOR: None,
    }
)

#: Display name and description of the system roles.
ROLE_LABELS = MappingProxyType(
    {
        EMPLOYEE: (
            "Solicitante",
            "Crea y ve solo sus solicitudes y tickets; edita su perfil",
        ),
        TECHNICIAN: ("Técnico", "Trabaja los tickets y mantenimientos asignados a él"),
        SUPERVISOR: (
            "Supervisor",
            "Ve y gestiona toda la operación: asigna, aprueba y reporta",
        ),
        ADMIN: ("Administrador", "Gestiona usuarios, roles, configuración y auditoría"),
        AUDITOR: ("Auditor", "Solo lectura de reportes y auditoría"),
    }
)

#: What each role grants *by itself*; the rest comes from its ancestors.
ROLE_OWN_PERMISSIONS = MappingProxyType(
    {
        EMPLOYEE: frozenset(
            {
                "dashboard:ver",
                "perfil:ver",
                "perfil:editar",
                "solicitudes:ver",
                "solicitudes:crear",
                "tickets:ver",
                "tickets:adjuntar",
                "equipos:ver",
            }
        ),
        TECHNICIAN: frozenset(
            {
                "tickets:ver_asignados",
                "tickets:editar",
                "tickets:cambiar_estado",
                "mantenimiento:ver",
                "inventario:ver",
                "inventario:consumir",
                "tecnicos:ver",
            }
        ),
        SUPERVISOR: frozenset(
            {
                "dashboard:ver_todos",
                "solicitudes:ver_todos",
                "solicitudes:editar",
                "solicitudes:aprobar",
                "tickets:ver_todos",
                "tickets:asignar",
                "tickets:exportar",
                "tecnicos:crear",
                "tecnicos:editar",
                "tecnicos:exportar",
                "mantenimiento:crear",
                "mantenimiento:editar",
                "inventario:crear",
                "inventario:editar",
                "inventario:exportar",
                "equipos:crear",
                "equipos:editar",
                "equipos:asignar",
                "equipos:adjuntar",
                "equipos:exportar",
                "reportes:ver",
                "reportes:exportar",
            }
        ),
        ADMIN: frozenset(
            {
                "usuarios:ver",
                "usuarios:crear",
                "usuarios:editar",
                "usuarios:cambiar_estado",
                "usuarios:asignar",
                "configuracion:ver",
                "configuracion:editar",
                "auditoria:ver",
                "equipos:importar",
                "inventario:importar",
                "inventario:eliminar",
            }
        ),
        AUDITOR: frozenset(
            {
                "dashboard:ver",
                "dashboard:ver_todos",
                "perfil:ver",
                "perfil:editar",
                "reportes:ver",
                "reportes:exportar",
                "auditoria:ver",
            }
        ),
    }
)


def effective_for_system_roles(*role_codes: str) -> frozenset[str]:
    """Permissions (new catalogue) of the given system roles, ancestors included."""
    from app.core.rbac import effective

    own = {role: frozenset(codes) for role, codes in ROLE_OWN_PERMISSIONS.items()}
    parents = dict(ROLE_PARENTS)
    result: frozenset[str] = frozenset()
    for code in role_codes:
        result |= effective(code, parents, own)
    return result
