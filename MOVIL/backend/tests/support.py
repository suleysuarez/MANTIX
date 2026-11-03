"""Helpers shared by tests: fake people that hold the permissions of the `recurso:accion` catalogue.

Many older tests still say what they need with the legacy dotted codes (`inventory.manage`);
`expand` turns them into the catalogue codes that now guard the endpoints, so each test keeps
saying what it means without repeating the mapping.
"""

from types import SimpleNamespace

#: legacy code -> the catalogue permissions that cover what it used to allow.
LEGACY = {
    "equipment.read": {"equipos:ver"},
    "equipment.manage": {
        "equipos:crear",
        "equipos:editar",
        "equipos:asignar",
        "equipos:adjuntar",
        "equipos:importar",
        "equipos:exportar",
    },
    "maintenance.read": {"tickets:ver", "mantenimiento:ver", "tecnicos:ver"},
    "maintenance.create": {"solicitudes:crear"},
    "maintenance.manage": {
        "tickets:asignar",
        "tickets:cambiar_estado",
        "tickets:editar",
        "solicitudes:editar",
        "solicitudes:aprobar",
    },
    "technicians.manage": {"tecnicos:crear", "tecnicos:editar", "tecnicos:exportar"},
    "users.manage": {
        "usuarios:ver",
        "usuarios:crear",
        "usuarios:editar",
        "usuarios:cambiar_estado",
        "usuarios:asignar",
        "configuracion:ver",
        "configuracion:editar",
    },
    "priorities.manage": {"configuracion:ver", "configuracion:editar"},
    "dashboard.read": {"dashboard:ver", "dashboard:ver_todos"},
    "reports.read": {"reportes:ver", "reportes:exportar"},
    "audit.read": {"auditoria:ver"},
    "attachments.write": {"tickets:adjuntar", "equipos:adjuntar"},
    "schedules.manage": {"mantenimiento:crear", "mantenimiento:editar"},
    "inventory.read": {"inventario:ver"},
    "inventory.manage": {
        "inventario:crear",
        "inventario:editar",
        "inventario:eliminar",
        "inventario:importar",
        "inventario:exportar",
    },
    "inventory.consume": {"inventario:consumir"},
}


def expand(*codes: str) -> frozenset[str]:
    """Catalogue codes for a mix of legacy and catalogue codes."""
    result: set[str] = set()
    for code in codes:
        result |= LEGACY.get(code, {code})
    return frozenset(result)


def perm_objects(*codes: str) -> list[SimpleNamespace]:
    """Permission objects (as an ORM role would carry them) for `expand(*codes)`."""
    return [
        SimpleNamespace(code=c, name=c, is_active=True) for c in sorted(expand(*codes))
    ]
