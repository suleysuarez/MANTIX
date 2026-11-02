#!/bin/sh
# Container entrypoint: optionally apply database migrations, then run the command.
#
# RUN_MIGRATIONS=true  -> `alembic upgrade head` before starting (development, single
#                         instance). Leave it unset/false in production and run the
#                         migration as a separate release step, so several replicas
#                         never race to migrate the same database.
set -eu

if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
    echo "Applying database migrations..."
    alembic upgrade head
fi

exec "$@"
