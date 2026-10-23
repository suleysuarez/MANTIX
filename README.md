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

```mermaid
flowchart TB
    User(["Usuario<br/>navegador"])

    subgraph FE["Frontend · Angular + Tailwind"]
        direction TB
        Smart["Componentes <b>Smart</b><br/>pantallas en features/ · cargan y coordinan datos"]
        Dumb["Componentes <b>Dumb</b><br/>presentacionales · @Input / @Output"]
        Rx["RxJS · Observer<br/>stores (BehaviorSubject) + servicios HTTP"]
        Perm["PermissionsService<br/>*hasPermission · requiresPermission · guards"]
        Int["authInterceptor<br/>Bearer token · 401 reintenta · 403 avisa"]
        Smart --> Dumb
        Smart --> Rx
        Smart --> Perm
        Rx --> Int
    end

    subgraph BE["Backend · FastAPI"]
        direction TB
        Api["API REST · app/api/routes<br/>validación Pydantic · require_permission"]
        Svc["Capa de servicios · app/services<br/>reglas de negocio · alcance de datos · auditoría<br/><b>State Pattern</b> (ticket_state.py)"]
        Repo["Repositorios · app/repositories<br/><b>Repository Pattern</b> · aíslan el SQL"]
        DI["Inyección de dependencias<br/>providers.py"]
        Jobs["Jobs en segundo plano<br/>recordatorios (APScheduler)"]
        Api --> Svc --> Repo
        DI -.-> Api
        Jobs --> Svc
    end

    DB[("Neon PostgreSQL<br/>29 tablas")]
    Files[("Archivos<br/>uploads/ · FileStorage")]
    Clerk["Clerk<br/>autenticación + JWT de sesión"]

    User --> FE
    Int -- "HTTP / JSON" --> Api
    Repo --> DB
    Svc --> Files
    User -. "inicio de sesión" .-> Clerk
    Perm -. "token" .-> Clerk
    Api -. "verifica el token" .-> Clerk

    subgraph Ops["Operación"]
        GH["GitHub<br/>control de versiones + CI"]
        Dk["Docker<br/>contenedores y despliegue"]
    end
    GH -.-> Dk
```

The browser talks only to the API. Authentication is Clerk, authorization is local (roles with inheritance), data lives in Neon PostgreSQL and files behind a `FileStorage` port. More detail, with the request flow, in [docs/architecture.md](docs/architecture.md).

### Design patterns

| # | Patrón | Dónde | Para qué |
| --- | --- | --- | --- |
| 1 | **State** | `backend/app/domain/ticket_state.py` | Cada estado del ticket es una clase con sus transiciones, reglas de entrada y efectos. Sin cadenas de `if/else`. |
| 2 | **Dependency Injection** | `backend/app/api/providers.py` | Cadena `get_db` → repositorio → servicio por petición; todo se puede sustituir en los tests. |
| 3 | **Repository** | `backend/app/repositories/` | Todo el SQL vive aquí; los servicios solo tienen reglas de negocio. |
| 4 | **Observer** | `frontend/src/app/core/*.store.ts` | RxJS (`BehaviorSubject` y observables): la interfaz reacciona a los cambios de estado. |
| 5 | **Smart & Dumb components** | `frontend/src/app/features/` y `shared/` | Los *smart* cargan datos y deciden; los *dumb* solo reciben `@Input` y emiten `@Output`. |
| 6 | **Singleton** | servicios con `providedIn: 'root'` | Una única instancia compartida (permisos, toasts, stores). |

### Backend layering

Strict layering, with no layer skipped:

```text
router (app/api/routes)  ->  service (app/services)  ->  repository (app/repositories)  ->  model (app/models)
   HTTP, validation,           business rules,             every SQL/ORM query,              SQLAlchemy tables
   permissions                 orchestration, audit        pagination, search, sorting
```

The first three patterns are mandatory and enforced by tests:

**State pattern - ticket workflow** (`app/domain/ticket_state.py`). Each status is a class that owns its allowed transitions, entry rules (`requires_technician`) and side effects (`resolved_at`, `closed_at`, requester notification). Services and routers contain no status `if/else` chains; *every* status change, including the automatic one when a technician is assigned, goes through `TicketState.transition()`. An invalid change raises `InvalidTransitionError` (HTTP 409, code `invalid_transition`). Adding a status means adding one class. The diagram is in [docs/api-reference.md](docs/api-reference.md#ticket-state-diagram).

**Dependency injection** (`app/api/providers.py`). One chain per request: `get_db` (session) -> `get_*_repository` -> `get_*_service`. Routers only receive services; services never build repositories or sessions. Every link can be replaced with `app.dependency_overrides` (the unit tests do exactly that).

**Repository pattern.** `BaseRepository[T]` provides get/add/delete, escaped `ILIKE` search, whitelisted ordering (a client-supplied `sort` never reaches SQL), pagination and `commit`/`rollback`. Concrete repositories add the queries of their aggregate. Services contain no queries.

Other building blocks: `core/authz.py` (`AuthContext`), `core/errors.py` (global exception handlers), `core/uploads.py` and `core/storage.py` (safe uploads behind a `FileStorage` port), `services/exporters.py` (CSV/Excel/PDF strategies), `jobs.py` (background scheduler).

## Authentication and authorization

**Authentication is delegated to Clerk.** The access token (a short-lived session JWT), its refresh, rotation and revocation are managed entirely by Clerk: Clerk issues sessions, silently renews short-lived tokens and revokes them on sign-out or from the Clerk dashboard. The API never issues or stores tokens; it verifies the `Authorization: Bearer <session JWT>` header with the Clerk SDK (signature, expiry and authorized parties) and maps the Clerk subject to a local user. Missing or invalid credentials return `401`. See [docs/authentication.md](docs/authentication.md).

**Authorization is local.** Roles and permissions live in the database, as `resource:action` codes written in Spanish (for example `tickets:asignar`). Every endpoint declares what it needs with a reusable dependency, and services receive the resulting `AuthContext` as `actor`:

```python
require_permission("tickets:asignar")   # holds this permission (own or inherited)
require_authenticated()                  # any signed-in person (own profile, notifications)
```

Unauthorized callers get `403`, and the denial is written to the audit trail (`AUDIT_DENIALS`). A test fails if an endpoint declares neither. The first user to sign in becomes ADMIN; later users wait without a role until an administrator grants one.

**Roles and inheritance.** A role has the permissions it grants itself plus everything its parent grants. Cycles are refused and the chain is limited to 6 levels. Five base roles are seeded; administrators can create custom ones from the *Roles y permisos* screen.

| Role | Inherits from | What it is for |
| --- | --- | --- |
| Solicitante (`EMPLOYEE`) | - | Reports problems and follows its own requests and tickets. |
| Técnico (`TECHNICIAN`) | - | Works the tickets and preventive plans assigned to it, sees only its own figures and exports its own tickets. |
| Supervisor (`SUPERVISOR`) | Técnico | Sees and manages the whole operation: approves requests, assigns technicians, inventory, equipment, reports. |
| Administrador (`ADMIN`) | Supervisor | Users, roles and permissions, settings, audit, imports. |
| Auditor (`AUDITOR`) | - | Read-only: dashboard, reports and audit. |

**Data scope** follows the permissions, not the role name: `ver` is what the person owns, `ver_asignados` what is assigned to them, `ver_todos` everything. Dashboards, maintenance figures, plans and exports are limited the same way. Sensitive fields (`hourly_rate`, `purchase_cost`) are removed from responses unless the person may edit them.

**Rules for changing roles** (enforced in the backend): only whoever holds `usuarios:asignar` can; nobody changes their own roles; a role can only be given or taken by someone who already has every permission it carries; base roles cannot be deleted, deactivated or moved; Administrador cannot be edited; a role with users, or that is a parent, cannot be deleted. Every change is audited with its before and after values.

The full matrix is generated into [docs/rbac-matriz.md](docs/rbac-matriz.md) (`python -m scripts.rbac_matrix`) and the endpoint list, with the permission of each one, into [docs/api-reference.md](docs/api-reference.md). Tests check both against the code and the migration seeds. The frontend asks `PermissionsService` and hides or disables what the person cannot use (`*hasPermission`, `[requiresPermission]`); that is a convenience, the backend decides.

## Features

| Area | What it does |
| --- | --- |
| Equipment | Catalog, types, locations, custody history, status history, bulk import (CSV/Excel). |
| Requests queue | Pending requests to classify, approve or reject, with queue metrics. |
| Tickets | Create, assign, work records with costs, guarded state machine, Kanban board, history, notifications. |
| Priorities | Managed catalog (`/priorities`) with SLA hours; tickets validate against it. |
| Technicians | Profiles, availability, workload, hourly rate. |
| Preventive maintenance | Recurring plans, calendar, compliance and cost metrics (`/maintenance/*`) and a scheduled reminder job. |
| Inventory | Parts and supplies with movements, low-stock alerts, consumption by ticket and catalogues. |
| Dashboard | KPIs against the previous period (MTTR, SLA compliance, first assignment, resolution rate, backlog by age, availability), trends, alerts and per-technician load. It adapts to the role: whole operation, own assigned work, or own requests. |
| Reports | Report builder (CSV, Excel, PDF) with history, and PDF/Excel export panels for tickets, technicians and users. Each export is authorised by its own permission. |
| Users and roles | Accounts, role assignment, pending users, and the *Roles y permisos* matrix with a "test as this role" preview. |
| Settings | Organization, priorities (with SLA) and request categories. |
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
| `AUDIT_DENIALS` | Write an audit entry for every `403` | `true` |
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

29 tables with foreign keys, check constraints, partial unique indexes and query indexes. Roles, permissions, priorities and equipment types are seeded by migrations (`python -m scripts.seed_rbac` re-syncs the role catalogue idempotently). The domain design is in [docs/domain-model.md](docs/domain-model.md) (the implementation uses integer identity keys).

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

### Demo data

`backend/scripts/seed_demo.py` loads a year of realistic data (users per role, equipment, tickets with history and costs, inventory, preventive plans, audit) so the dashboard and reports have something to show. Everything it creates is marked `DEMO` (`DEMO-*` codes, `@demo.mantix.co` emails), and demo users cannot sign in because they do not exist in Clerk.

```bash
cd backend
python -m scripts.seed_demo --yes            # add (prints the target database host first)
python -m scripts.seed_demo --yes --reset    # remove the demo data and add it again
python -m scripts.seed_demo --yes --remove   # remove only the demo data
```

Without `--yes` nothing is written.

## CI/CD

`.github/workflows/ci.yml` runs on every push to `main` and every pull request:

1. **backend** - `ruff` (lint + format), `mypy --strict`, migrations on a fresh PostgreSQL, `alembic check` (no schema drift), tests with a 90% coverage gate, dependency audit (informational).
2. **frontend** - ESLint, production build, tests, `npm audit` (informational).
3. **docker** - builds the images and smoke-tests the stack: PostgreSQL + migrations + API healthcheck, verifying the container runs as a non-root user.

## Further documentation

- [docs/api-reference.md](docs/api-reference.md) - endpoints with their permission, ticket state diagram (generated)
- [docs/rbac-matriz.md](docs/rbac-matriz.md) - permissions per role, with inheritance (generated)
- [docs/rbac-inventario.md](docs/rbac-inventario.md) - inventory of the endpoints and screens moved to the new permissions
- [docs/architecture.md](docs/architecture.md) - architecture notes
- [docs/authentication.md](docs/authentication.md) - Clerk integration
- [docs/domain-model.md](docs/domain-model.md) - database design
- [docs/deployment.md](docs/deployment.md) - operations and release checklist
