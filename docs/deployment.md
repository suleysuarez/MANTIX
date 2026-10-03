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

In production set `CORS_ORIGINS` and `CLERK_AUTHORIZED_PARTIES` to the real frontend origin
and use Clerk **production** keys (development keys show the "Development mode" badge).

## Release checklist

1. `alembic upgrade head` against the target database before starting the new backend.
2. Backend: `pytest`, `ruff check app tests`, `ruff format --check app tests`.
3. Frontend: `npm run lint`, `npm run build`, `npm test`.
4. Confirm `/health` answers `200` after the deploy.

## Operational notes

- **Rate limiting** is in-memory per process. With several workers or replicas each keeps its own
  counters; move the limit to the reverse proxy or a shared store when scaling out.
- **Logging** records method, path, status and latency with an `X-Request-ID` (echoed back to the
  client). Headers, tokens and bodies are never logged.
- **CORS** only allows `GET, POST, PATCH, DELETE, OPTIONS` and the `Authorization`,
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
- Equipment location/custody assignment and file attachments have API support or models but no
  UI/endpoint yet.
