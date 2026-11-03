"""Exporta el esquema OpenAPI de la API a un archivo JSON.

    python -m scripts.export_openapi                 # escribe ./openapi.json
    python -m scripts.export_openapi ruta/salida.json

Lo usa el CI para publicar el contrato como artefacto, y sirve para comparar versiones
del contrato que consume la app móvil. No necesita base de datos ni claves.
"""

import json
import sys
from pathlib import Path
from typing import Any

from app.main import app


def build_openapi() -> dict[str, Any]:
    return app.openapi()


def main(argv: list[str]) -> int:
    output = Path(argv[0]) if argv else Path("openapi.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    schema = build_openapi()
    # Orden estable y sin escapar acentos: un diff entre versiones solo muestra cambios reales.
    output.write_text(
        json.dumps(schema, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"wrote {output} ({len(schema.get('paths', {}))} paths)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
