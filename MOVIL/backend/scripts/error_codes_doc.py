"""Genera `docs/error-codes.md` desde `app.core.error_codes`, para que la tabla no se desfase.

    python -m scripts.error_codes_doc            # reescribe el archivo
    python -m scripts.error_codes_doc --check    # sale con 1 si está desactualizado

Un test ejecuta la lógica de `--check`.
"""

import sys
from pathlib import Path

from app.core.error_codes import ERROR_CODES

OUTPUT = Path(__file__).resolve().parents[2] / "docs" / "error-codes.md"

_STATUS_NAMES = {
    400: "400 Petición mal formada",
    401: "401 Sin sesión",
    403: "403 Prohibido",
    404: "404 No encontrado",
    405: "405 Método no permitido",
    409: "409 Conflicto",
    413: "413 Archivo demasiado grande",
    415: "415 Formato no admitido",
    422: "422 Datos no válidos",
    429: "429 Demasiadas peticiones",
    500: "500 Error interno",
}


def _table(generic: bool) -> list[str]:
    lines = []
    statuses = sorted(
        {info.status for info in ERROR_CODES.values() if info.generic == generic}
    )
    for status in statuses:
        rows = sorted(
            (code, info)
            for code, info in ERROR_CODES.items()
            if info.status == status and info.generic == generic
        )
        lines += [
            f"### {_STATUS_NAMES.get(status, str(status))}",
            "",
            "| Código | Significado |",
            "| --- | --- |",
        ]
        lines += [f"| `{code}` | {info.meaning} |" for code, info in rows]
        lines.append("")
    return lines


def build_markdown() -> str:
    lines = [
        "# Códigos de error de la API",
        "",
        "> Generado por `python -m scripts.error_codes_doc`. No lo edites a mano: cámbialo en",
        "> `backend/app/core/error_codes.py` y regenera.",
        "",
        "Toda respuesta de error tiene el mismo cuerpo:",
        "",
        "```json",
        '{ "detail": "mensaje legible", "code": "ticket_not_found", "errors": null, "request_id": "3f2c9d1e0b7a4c58" }',
        "```",
        "",
        "- `code` es un contrato: **no se renombra ni se reutiliza** para otro significado. Un caso nuevo recibe un código nuevo.",
        "- `errors` solo viene en los 422 (`validation_error`): lista de `{field, message, type}`.",
        "- `request_id` identifica la petición en los logs del servidor; el soporte lo pide.",
        "- `detail` es para mostrar, pero puede estar en español o en inglés: la app decide por `code`, no por el texto.",
        "",
        "## Cómo debe usarlos un cliente",
        "",
        "1. Si el `code` es uno de los **específicos**, usar el mensaje o la acción propia de ese caso.",
        "2. Si el `code` no está en la tabla (por ejemplo, uno añadido por un servidor más nuevo), decidir por el **estado HTTP** con el significado del genérico de esa fila.",
        "3. Nunca decidir por el texto de `detail`.",
        "",
        "## Genéricos (respaldo por estado HTTP)",
        "",
        *_table(generic=True),
        "## Específicos (un caso de negocio)",
        "",
        *_table(generic=False),
    ]
    return "\n".join(lines).rstrip() + "\n"


def main(argv: list[str]) -> int:
    content = build_markdown()
    if "--check" in argv:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current.replace("\r\n", "\n") != content:
            print(
                f"{OUTPUT} está desactualizado: ejecuta `python -m scripts.error_codes_doc`"
            )
            return 1
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(content, encoding="utf-8", newline="\n")
    print(f"wrote {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
