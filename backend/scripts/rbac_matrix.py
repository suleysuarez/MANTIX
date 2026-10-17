"""Write the role x permission table (docs/rbac-matriz.md) from the catalogue.

    python -m scripts.rbac_matrix

`●` the role grants it itself, `○` it inherits it from an ancestor, blank: no. The file is
generated, so the documentation cannot drift from `app/core/permissions.py`.
"""

from pathlib import Path

from app.core.authz import ADMIN, AUDITOR, EMPLOYEE, SUPERVISOR, TECHNICIAN
from app.core.permissions import (
    ACTION_LABELS,
    CATALOG,
    RESOURCE_LABELS,
    ROLE_LABELS,
    ROLE_OWN_PERMISSIONS,
    ROLE_PARENTS,
)
from app.core.rbac import provenance

OUTPUT = Path(__file__).resolve().parents[2] / "docs" / "rbac-matriz.md"
ORDER = (EMPLOYEE, TECHNICIAN, SUPERVISOR, ADMIN, AUDITOR)


def build_markdown() -> str:
    parents = dict(ROLE_PARENTS)
    own = {role: frozenset(codes) for role, codes in ROLE_OWN_PERMISSIONS.items()}
    owners = {role: provenance(role, parents, own) for role in ORDER}
    names = [ROLE_LABELS[role][0] for role in ORDER]
    lines = [
        "# Mantix · Matriz de permisos por rol",
        "",
        "Generada con `python -m scripts.rbac_matrix` desde `app/core/permissions.py`: no se edita a mano.",
        "",
        (
            "**Herencia:** Solicitante → Técnico → Supervisor → Administrador "
            "(cada uno hereda del anterior). Auditor no hereda nada."
        ),
        "",
        "`●` lo concede el propio rol · `○` lo hereda de un rol anterior · vacío: no lo tiene.",
        "",
        (
            "Alcance de datos: `ver` = solo lo propio, `ver_asignados` = lo asignado a la "
            "persona (y lo suyo), `ver_todos` = todo."
        ),
        "",
        "| Permiso | Código | " + " | ".join(names) + " |",
        "|---|---|" + "|".join(":-:" for _ in ORDER) + "|",
    ]
    for code in CATALOG:
        resource, action = code.split(":")
        cells = []
        for role in ORDER:
            owner = owners[role].get(code)
            cells.append("" if owner is None else "●" if owner == role else "○")
        label = f"{RESOURCE_LABELS[resource]} · {ACTION_LABELS[action]}"
        lines.append(f"| {label} | `{code}` | " + " | ".join(cells) + " |")
    lines += ["", f"Total: {len(CATALOG)} permisos, {len(ORDER)} roles base.", ""]
    return "\n".join(lines)


if __name__ == "__main__":
    OUTPUT.write_text(build_markdown(), encoding="utf-8")
    print(f"wrote {OUTPUT}")
