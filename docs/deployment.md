# Deployment and operations

## Environment variables (backend)

| Variable | Purpose | Default |
| --- | --- | --- |
| `APP_ENV` | `production` disables `/docs`, `/redoc` and `/openapi.json` | `development` |
| `DATABASE_URL` | Neon PostgreSQL connection string (server-side only) | — |
| `CORS_ORIGINS` | Comma-separated browser origins allowed to call the API | `http://localhost:4200` |
| `CLERK_SECRET_KEY` | Clerk backend key used to verify session tokens | — |
| `CLERK_PUBLISHABLE_KEY` | Clerk publishable key | — |
| `CLERK_AUTHORIZED_PARTIES` | Origins accepted as the token's `azp` claim | `http://localhost:4200` |
| `RATE_LIMIT_PER_MINUTE` | Requests per client IP per minute; `0` disables | `120` |
| `LOG_LEVEL` | Python log level | `INFO` |
| `UPLOAD_DIR` | Directory for attachments (a volume in Docker) | `uploads` |
| `MAX_UPLOAD_MB` | Upload size limit in MB | `10` |
| `SCHEDULER_ENABLED` | Run the reminder scheduler inside the API process | `true` |
| `REMINDER_INTERVAL_MINUTES` | How often preventive-maintenance reminders are evaluated | `60` |
| `RUN_MIGRATIONS` | Container entrypoint only: run `alembic upgrade head` before starting | unset |

In production set `CORS_ORIGINS` and `CLERK_AUTHORIZED_PARTIES` to the real frontend origin
and use Clerk **production** keys (development keys show the "Development mode" badge).

## Release checklist

1. `alembic upgrade head` against the target database before starting the new backend
   (`docker compose run --rm backend alembic upgrade head`). Do not set `RUN_MIGRATIONS` in
   production when running several replicas.
2. Backend: `pytest --cov=app`, `ruff check app tests`, `ruff format --check app tests`, `mypy`,
   `alembic check`, and `python -m scripts.api_docs --check`.
3. Frontend: `npm run lint`, `npm run build`, `npm test`.
4. Confirm `/health` answers `200` after the deploy.

## Operational notes

- **Rate limiting** is in-memory per process. With several workers or replicas each keeps its own
  counters; move the limit to the reverse proxy or a shared store when scaling out.
- **Scheduler.** Reminders run in-process (APScheduler). Every replica runs the job; a PostgreSQL
  advisory lock makes sure only one sends each reminder. Disable it with `SCHEDULER_ENABLED=false`
  on instances that should not run jobs, and use `POST /maintenance/schedules/run-reminders` to
  trigger it manually.
- **Attachments** are stored on the local disk (`UPLOAD_DIR`). Mount a persistent volume, or
  implement the `FileStorage` port with an object store when the host has ephemeral disks.
- **Audit** rows store the client IP as seen by uvicorn; behind a reverse proxy start uvicorn with
  `--proxy-headers --forwarded-allow-ips=<proxy ip>` so the real client address is recorded.
- **Logging** records method, path, status and latency with an `X-Request-ID` (echoed back to the
  client). Headers, tokens and bodies are never logged.
- **CORS** only allows `GET, POST, PUT, PATCH, DELETE, OPTIONS` and the `Authorization`,
  `Content-Type` and `X-Request-ID` headers.

## Frontend container

- `frontend/nginx.conf` serves the SPA with an `index.html` fallback, so deep links such as
  `/auth/login` or `/maintenance/12` work after a refresh.
- The API URL is **runtime** configuration: on start, `docker-entrypoint.d/40-runtime-config.sh`
  writes `assets/config.json` from the `API_URL` environment variable (`docker-compose.yml`
  already passes it). The same image therefore works in every environment. Outside Docker,
  edit `src/assets/config.json`.
- The Clerk publishable key and Clerk domain are still fixed in `src/index.html`; change them
  there when moving to production keys.

## Known gaps

- Dependency audits run in CI as informational steps: `npm audit` currently reports high-severity
  advisories in Angular 19 whose fix is a major upgrade.
- The Angular UI does not yet cover reports, attachments, schedules, the audit log or priorities;
  the API for all of them is available (see `docs/api-reference.md`).
- Attachments for maintenance records are modeled in the database but have no endpoint.
