# Mantix - Technology Equipment Maintenance System

Mantix manages technology equipment and the maintenance work done on it: an equipment catalog, maintenance tickets with a guarded workflow, technicians, priorities, preventive-maintenance plans, an audit trail, an operational dashboard, reports and file attachments.

- **Backend:** FastAPI + SQLAlchemy 2 (async) + PostgreSQL (Neon in production), Alembic migrations.
- **Frontend:** Angular (standalone components, strict TypeScript).
- **Authentication:** Clerk. **Authorization:** roles and permissions stored locally.

## Contents

- [Quick start](#quick-start)
- [Architecture](#architecture)
- [Authentication and authorization](#authentication-and-authorization)
- [Features](#features)
- [Configuration](#configuration)
- [Database and migrations](#database-and-migrations)
- [Testing and quality](#testing-and-quality)
- [CI/CD](#cicd)
- [Further documentation](#further-documentation)

## Quick start

### With Docker (API + PostgreSQL + frontend)

```bash
cp backend/.env.example backend/.env      # set CLERK_SECRET_KEY / CLERK_PUBLISHABLE_KEY
docker compose up --build
```

The API is on <http://localhost:8000> (`/health`, and `/docs` outside production), the frontend on <http://localhost:4200>. PostgreSQL runs in the `db` service and migrations are applied on start (`RUN_MIGRATIONS=true`). Data lives in the `pgdata` and `uploads` volumes; `docker compose down -v` deletes them.

Only the API and database: `docker compose up --build db backend`.

### Without Docker

```bash
cd backend
python -m venv .venv && source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
cp .env.example .env                                    # set DATABASE_URL, Clerk keys
alembic upgrade head
uvicorn app.main:app --reload --port 8000
```

```bash
cd frontend
npm install
npm start
```

> `python -m alembic` does not work here because the project's `alembic/` folder shadows the library; use the `alembic` command.

### Production (Neon)

Set `DATABASE_URL` (the Neon connection string) in `backend/.env`, build the image, run migrations as a release step and start only the API:

```bash
docker compose run --rm backend alembic upgrade head
docker compose up -d --no-deps backend
```

Leave `RUN_MIGRATIONS` unset in production so several replicas never race to migrate. See [docs/deployment.md](docs/deployment.md).

## Architecture

Strict layering, with no layer skipped:

```text
router (app/api/routes)  ->  service (app/services)  ->  repository (app/repositories)  ->  model (app/models)
   HTTP, validation,           business rules,             every SQL/ORM query,              SQLAlchemy tables
   permissions                 orchestration, audit        pagination, search, sorting
```

Three design patterns are mandatory and enforced by tests:

**State pattern - ticket workflow** (`app/domain/ticket_state.py`). Each status is a class that owns its allowed transitions, entry rules (`requires_technician`) and side effects (`resolved_at`, `closed_at`, requester notification). Services and routers contain no status `if/else` chains; *every* status change, including the automatic one when a technician is assigned, goes through `TicketState.transition()`. An invalid change raises `InvalidTransitionError` (HTTP 409, code `invalid_transition`). Adding a status means adding one class. The diagram is in [docs/api-reference.md](docs/api-reference.md#ticket-state-diagram).

**Dependency injection** (`app/api/providers.py`). One chain per request: `get_db` (session) -> `get_*_repository` -> `get_*_service`. Routers only receive services; services never build repositories or sessions. Every link can be replaced with `app.dependency_overrides` (the unit tests do exactly that).

**Repository pattern.** `BaseRepository[T]` provides get/add/delete, escaped `ILIKE` search, whitelisted ordering (a client-supplied `sort` never reaches SQL), pagination and `commit`/`rollback`. Concrete repositories add the queries of their aggregate. Services contain no queries.

Other building blocks: `core/authz.py` (`AuthContext`), `core/errors.py` (global exception handlers), `core/uploads.py` and `core/storage.py` (safe uploads behind a `FileStorage` port), `services/exporters.py` (CSV/Excel/PDF strategies), `jobs.py` (background scheduler).

## Authentication and authorization

**Authentication is delegated to Clerk.** The access token (a short-lived session JWT), its refresh, rotation and revocation are managed entirely by Clerk: Clerk issues sessions, silently renews short-lived tokens and revokes them on sign-out or from the Clerk dashboard. The API never issues or stores tokens; it verifies the `Authorization: Bearer <session JWT>` header with the Clerk SDK (signature, expiry and authorized parties) and maps the Clerk subject to a local user. Missing or invalid credentials return `401`. See [docs/authentication.md](docs/authentication.md).

**Authorization is local.** Roles and permissions live in the database and are enforced by reusable dependencies:

```python
require_permission("equipment.manage")   # holds this permission
require_role("ADMIN", "SUPERVISOR")      # holds one of these roles
```

Both return an `AuthContext` that services receive as `actor`. Unauthorized callers get `403`. The first user to sign in becomes ADMIN; later users wait without a role until an administrator grants one.

| Permission | ADMIN | SUPERVISOR | TECHNICIAN | EMPLOYEE |
| --- | :-: | :-: | :-: | :-: |
| `equipment.read` | yes | yes | yes | yes |
| `equipment.manage` | yes | yes | - | - |
| `maintenance.read` | yes | yes | yes | yes |
| `maintenance.create` | yes | yes | - | yes |
| `maintenance.manage` | yes | yes | own tickets | - |
| `technicians.manage` | yes | yes | - | - |
| `schedules.manage` | yes | yes | - | - |
| `dashboard.read` | yes | yes | own tickets | - |
| `reports.read` | yes | yes | - | - |
| `audit.read` | yes | yes | - | - |
| `attachments.write` | yes | yes | yes | yes |
| `priorities.manage` | yes | - | - | - |
| `users.manage` | yes | - | - | - |

Ticket visibility: ADMIN/SUPERVISOR see all tickets, a TECHNICIAN the tickets assigned to them, an EMPLOYEE the tickets they requested. The matrix is generated into [docs/api-reference.md](docs/api-reference.md) together with the full endpoint list, and tests check it against every endpoint and against the migration seeds.

## Features

| Area | What it does |
| --- | --- |
| Equipment | Catalog, types, locations, custody history, status history, bulk import (CSV/Excel). |
| Tickets | Create, assign, work records with costs, guarded state machine, history, notifications. |
| Priorities | Managed catalog (`/priorities`) with SLA hours; tickets validate against it. |
| Technicians | Profiles, availability, workload. |
| Preventive maintenance | Recurring plans (`/maintenance/schedules`) and a scheduled reminder job. |
| Dashboard | Tickets by status/priority, overdue vs SLA, mean/median resolution time, workload per technician, equipment with most failures. |
| Reports | Equipment inventory, tickets and operational summary as CSV, Excel or PDF. |
| Audit | Who, what, when, IP, previous and new values (`/audit-logs`). |
| Attachments | Tickets and equipment; validated by size, extension and file signature. |
| Notifications | In-app inbox for assignments, status changes, role changes and reminders. |
| Listings | `page`, `size`, `sort`, `search` and filters everywhere; page info in `X-Total-Count`, `X-Page`, `X-Page-Size`, `X-Total-Pages`. |
| Errors | One body for every failure: `{detail, code, errors, request_id}`. |

### Background jobs

Reminders for preventive-maintenance plans run inside the API process with APScheduler (`SCHEDULER_ENABLED`, `REMINDER_INTERVAL_MINUTES`). With several replicas every instance runs the job, and a PostgreSQL advisory lock guarantees each reminder is sent once. `POST /maintenance/schedules/run-reminders` runs the same job on demand.

### Uploads

Files go to `UPLOAD_DIR` (a Docker volume by default). On hosting with ephemeral disks, implement the `FileStorage` port with an object store before relying on attachments.

## Configuration

All settings come from environment variables (`pydantic-settings`); nothing secret is in the code. See `backend/.env.example`.

| Variable | Purpose | Default |
| --- | --- | --- |
| `APP_ENV` | `production` hides `/docs`, `/redoc`, `/openapi.json` | `development` |
| `DATABASE_URL` | PostgreSQL connection string (Neon in production) | - |
| `CORS_ORIGINS` | Allowed browser origins (comma separated) | `http://localhost:4200` |
| `CLERK_SECRET_KEY` | Server-side key to verify session tokens | - |
| `CLERK_PUBLISHABLE_KEY` | Public Clerk key | - |
| `CLERK_AUTHORIZED_PARTIES` | Accepted `azp` origins | `http://localhost:4200` |
| `RATE_LIMIT_PER_MINUTE` | Requests per IP per minute (`0` disables) | `120` |
| `LOG_LEVEL` | Python log level | `INFO` |
| `UPLOAD_DIR` | Where attachments are stored | `uploads` |
| `MAX_UPLOAD_MB` | Upload size limit | `10` |
| `SCHEDULER_ENABLED` | Run background jobs in the API process | `true` |
| `REMINDER_INTERVAL_MINUTES` | How often reminders are evaluated | `60` |
| `RUN_MIGRATIONS` | Container only: `alembic upgrade head` on start | unset |

## Database and migrations

```bash
cd backend
alembic upgrade head                                   # apply
alembic revision --autogenerate -m "describe change"   # new migration (review it!)
alembic check                                          # models and migrations agree?
```

21 tables with foreign keys, check constraints, partial unique indexes and query indexes. Roles, permissions, priorities and equipment types are seeded by migrations. The domain design is in [docs/domain-model.md](docs/domain-model.md) (the implementation uses integer identity keys).

## Testing and quality

```bash
cd backend
ruff check app tests && ruff format --check app tests
mypy                                   # strict
pytest                                 # unit tests only (database tests are skipped)
```

Unit tests mock repositories through DI and use `dependency_overrides` for endpoints. Database tests need two PostgreSQL databases:

```bash
export MIGRATED_DATABASE_URL=postgresql://user:pass@localhost:5432/mantix_migrated   # after `alembic upgrade head`
export TEST_DATABASE_URL=postgresql://user:pass@localhost:5432/mantix_scratch         # disposable: tables are dropped
pytest --cov=app --cov-fail-under=90
```

`MIGRATED_DATABASE_URL` runs the end-to-end API flows (each test is rolled back). `TEST_DATABASE_URL` is wiped by the repository tests: never point it at real data.

Regenerate the API reference after changing endpoints, permissions or ticket states (a test fails if it is stale):

```bash
python -m scripts.api_docs
```

Frontend: `npm run lint`, `npm run build`, `npm test` inside `frontend/`.

## CI/CD

`.github/workflows/ci.yml` runs on every push to `main` and every pull request:

1. **backend** - `ruff` (lint + format), `mypy --strict`, migrations on a fresh PostgreSQL, `alembic check` (no schema drift), tests with a 90% coverage gate, dependency audit (informational).
2. **frontend** - ESLint, production build, tests, `npm audit` (informational).
3. **docker** - builds the images and smoke-tests the stack: PostgreSQL + migrations + API healthcheck, verifying the container runs as a non-root user.

## Further documentation

- [docs/api-reference.md](docs/api-reference.md) - endpoints, role-permission matrix, ticket state diagram (generated)
- [docs/architecture.md](docs/architecture.md) - architecture notes
- [docs/authentication.md](docs/authentication.md) - Clerk integration
- [docs/domain-model.md](docs/domain-model.md) - database design
- [docs/deployment.md](docs/deployment.md) - operations and release checklist
