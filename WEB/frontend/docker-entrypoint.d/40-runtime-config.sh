#!/bin/sh
# Genera assets/config.json con la URL del API al arrancar el contenedor.
set -eu

API_URL="${API_URL:-http://localhost:8000}"
# Escapa comillas y barras invertidas para que el JSON siga siendo válido.
ESCAPED=$(printf '%s' "$API_URL" | sed 's/\\/\\\\/g; s/"/\\"/g')

printf '{\n  "apiUrl": "%s"\n}\n' "$ESCAPED" > /usr/share/nginx/html/assets/config.json
echo "runtime config: apiUrl=$API_URL"
