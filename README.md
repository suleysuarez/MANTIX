# Mantix - Technology Equipment Maintenance System

[![CI](https://github.com/suleysuarez/MANTIX/actions/workflows/ci.yml/badge.svg)](https://github.com/suleysuarez/MANTIX/actions/workflows/ci.yml)

Mantix manages technology equipment and the maintenance work done on it: an equipment catalog, maintenance tickets with a guarded workflow, technicians, priorities, preventive-maintenance plans, an audit trail, an operational dashboard, reports and file attachments.

- **Backend:** FastAPI + SQLAlchemy 2 (async) + PostgreSQL (Neon in production), Alembic migrations.
- **Frontend:** Angular (standalone components, strict TypeScript).
- **Authentication:** Clerk. **Authorization:** roles and permissions stored locally.

## Contents

- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
  - [With Docker](#with-docker-api--postgresql--frontend)
  - [Without Docker](#without-docker)
  - [Production (Neon)](#production-neon)
- [Project structure](#project-structure)
- [Architecture](#architecture)
  - [Design patterns](#design-patterns)
  - [Backend layering](#backend-layering)
- [Authentication and authorization](#authentication-and-authorization)
- [Features](#features)
- [Configuration](#configuration)
  - [Backend](#backend)
  - [Frontend](#frontend)
- [API usage example](#api-usage-example)
- [Database and migrations](#database-and-migrations)
- [Testing and quality](#testing-and-quality)
  - [Demo data](#demo-data)
- [CI/CD](#cicd)
- [Troubleshooting](#troubleshooting)
- [Project status](#project-status)
- [Further documentation](#further-documentation)
- [Authors](#authors)
- [License](#license)

## Prerequisites

| Tool | Version | Used for |
| --- | --- | --- |
| Python | 3.12 (`python:3.12-slim` in `backend/Dockerfile`, 3.12 in CI) | Backend |
| Node.js | 22 (`node:22-alpine` in `frontend/Dockerfile`, 22 in CI) with npm | Frontend (Angular 19, Tailwind 3) |
| Docker and Docker Compose v2 | any recent version (`docker compose`) | The Docker quick start and the production image |
| PostgreSQL | 16 (`postgres:16-alpine` in `docker-compose.yml`, `postgres:16` in CI) or a [Neon](https://neon.tech) project | Database |
| Clerk application | publishable and secret keys | Sign-in (see [Configuration](#configuration)) |
| Google Chrome | any recent version | `npm test` runs Karma with `ChromeHeadless` |

## Quick start

### With Docker (API + PostgreSQL + frontend)

```bash
cp backend/.env.example backend/.env      # set CLERK_SECRET_KEY / CLERK_PUBLISHABLE_KEY
docker compose up --build
```

The API is on <http://localhost:8000> (`/health`, and `/docs` outside production), the frontend on <http://localhost:4200>. PostgreSQL runs in the `db` service and migrations are applied on start (`RUN_MIGRATIONS=true`). Data lives in the `pgdata` and `uploads` volumes; `docker compose down -v` deletes them.

Only the API and database: `docker compose up --build db backend`.

> **Security:** the first person to sign in on an empty database becomes `ADMIN` automatically, and everyone who signs in afterwards waits without a role until an administrator grants one. Sign in yourself first, before you share the URL or open the sign-up page to anyone else.

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

> **Security:** the first person to sign in on an empty database becomes `ADMIN` automatically, and everyone who signs in afterwards waits without a role until an administrator grants one. Sign in yourself first, before you share the URL or open the sign-up page to anyone else.

### Production (Neon)

Set `DATABASE_URL` (the Neon connection string) in `backend/.env`, build the image, run migrations as a release step and start only the API:

```bash
docker compose run --rm backend alembic upgrade head
docker compose up -d --no-deps backend
```

Leave `RUN_MIGRATIONS` unset in production so several replicas never race to migrate. See [docs/deployment.md](docs/deployment.md).

> **Security:** on a new production database the first sign-in gets the `ADMIN` role. Do that sign-in yourself right after running the migrations and before exposing the application, then create the other accounts from *Usuarios* and give each one only the role it needs. Use Clerk **production** keys and set `CORS_ORIGINS` and `CLERK_AUTHORIZED_PARTIES` to the real frontend origin.

## Project structure

Generated from the repository (folders only; `21` migrations, `17` frontend feature folders):

```text
.
├── backend/                       FastAPI application
│   ├── app/
│   │   ├── api/                   dependencies, pagination headers, DI providers
│   │   │   └── routes/            one router per area (equipment, tickets, inventory, admin, ...)
│   │   ├── assets/                logo used in the exported PDFs
│   │   ├── core/                  settings, AuthContext, RBAC and data scope, errors, storage, middleware
│   │   ├── db/                    engine, session, declarative base
│   │   ├── domain/                ticket state machine (State pattern)
│   │   ├── exports/               PDF and Excel export definitions (tickets, technicians, users)
│   │   ├── models/                SQLAlchemy tables
│   │   ├── repositories/          every query (Repository pattern)
│   │   ├── schemas/               Pydantic request and response models
│   │   ├── services/              business rules, audit, reports
│   │   ├── jobs.py                scheduler for preventive-maintenance reminders
│   │   └── main.py                application, routers, CORS and error handlers
│   ├── alembic/                   migrations (versions/)
│   ├── scripts/                   api_docs, rbac_matrix, seed_rbac, seed_demo, normalize_inventory
│   └── tests/                     pytest suite: unit tests, API flows and PostgreSQL tests
├── frontend/                      Angular application
│   ├── src/
│   │   ├── app/
│   │   │   ├── core/              services, stores, guards, interceptor, PermissionsService
│   │   │   ├── features/          one folder per screen (admin, auth, dashboard, equipos, errors, export, inventory, kanban, maintenance-hub, pending-requests, profile, reports, roles, settings, technicians, tickets, users)
│   │   │   ├── layout/            application shell: sidebar, header, notifications
│   │   │   └── shared/            reusable components and the permission directives
│   │   └── assets/                config.json (API URL), images, videos
│   └── docker-entrypoint.d/       writes assets/config.json from API_URL when the container starts
├── docs/                          architecture, authentication, deployment, domain model, API reference, RBAC matrix
│   └── images/                    diagrams used by the documents
├── .github/workflows/             ci.yml
└── docker-compose.yml             PostgreSQL, API and frontend
```

## Architecture

![Arquitectura del proyecto Mantix](docs/images/arquitectura-mantix.png)

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

```mermaid
flowchart LR
    Client(["Angular"]) -->|HTTP / JSON| Router
    subgraph Backend["FastAPI"]
        Router["<b>Router</b><br/>app/api/routes<br/>HTTP, validation, permissions"]
        Service["<b>Service</b><br/>app/services<br/>business rules, scope, audit"]
        Repository["<b>Repository</b><br/>app/repositories<br/>every SQL / ORM query"]
        Model["<b>Model</b><br/>app/models<br/>SQLAlchemy tables"]
        Router --> Service --> Repository --> Model
    end
    Model --> DB[("PostgreSQL<br/>Neon")]
    Router -.->|verifies the token| Clerk["Clerk"]
    Service -.-> Files[("uploads/<br/>FileStorage")]
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

Unauthorized callers get `403`, and the denial is written to the audit trail (`AUDIT_DENIALS`). A test fails if an endpoint declares neither. The first user to sign in becomes ADMIN (see the security notes in [Quick start](#quick-start)); later users wait without a role until an administrator grants one.

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

### Backend

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

### Frontend

There are no `environment.ts` files; the frontend is configured in two places:

| What | Where | Notes |
| --- | --- | --- |
| API URL | `frontend/src/assets/config.json` (`{ "apiUrl": "http://localhost:8000" }`) | Read when the app starts by `src/app/core/api.config.ts`; if the file is missing the default is `http://localhost:8000`. In Docker the `frontend` service writes it from the `API_URL` variable (`docker-entrypoint.d/40-runtime-config.sh`), so one image works in every environment. |
| Clerk publishable key | `frontend/src/index.html` (`data-clerk-publishable-key` on the ClerkJS script, and the Clerk domain in the two script URLs) | The publishable key is public by design. It must belong to the same Clerk application as the backend `CLERK_SECRET_KEY`. Change the key and the domain together when you move to production keys. |

The token travels only to the API: `src/app/core/auth.interceptor.ts` adds `Authorization: Bearer <token>` to requests whose URL starts with the API URL, retries once on `401` with a fresh token and shows a message on `403`. The Clerk **secret** key never goes to the frontend.

## API usage example

Every endpoint expects the Clerk session token. Sign in to the app, open the browser console and copy a token (it is short-lived, so copy a new one when it expires):

```js
await Clerk.session.getToken()
```

Then list equipment, two per page, sorted by asset tag:

```bash
TOKEN="<paste the token here>"
curl -i "http://localhost:8000/equipment?page=1&size=2&sort=asset_tag" \
  -H "Authorization: Bearer $TOKEN"
```

The response carries the page information in headers and the rows as a JSON array (headers and rows trimmed; example with the demo data):

```http
HTTP/1.1 200 OK
x-total-count: 36
x-page: 1
x-page-size: 2
x-total-pages: 18
content-type: application/json
```

```json
[
  {
    "id": 73,
    "asset_tag": "DEMO-001",
    "equipment_type": { "id": 1, "code": "LAPTOP", "name": "Laptop" },
    "brand": "Dell",
    "model": "Latitude 5420",
    "status": "assigned",
    "purchase_date": "2024-12-25",
    "warranty_end_date": "2027-12-25",
    "current_location": { "id": 13, "code": "DEMO-SRV", "name": "Sala de servidores" },
    "current_custodian": { "id": 34, "full_name": "Laura Gómez", "email": "req1@demo.mantix.co" },
    "last_maintenance": { "work_type": "corrective", "result": "Sin falla encontrada", "technician_name": "Ana Demo" }
  }
]
```

Without a valid token the API answers `401`; with a valid token but without the permission the endpoint needs (`equipos:ver` here), `403` with a message in Spanish. Fields such as `purchase_cost` are only present for people who may edit equipment. With `APP_ENV` not set to `production`, the interactive reference is at <http://localhost:8000/docs>, and every endpoint with its permission is in [docs/api-reference.md](docs/api-reference.md).

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

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `No module named alembic.__main__` when running `python -m alembic ...` | The project's `alembic/` folder shadows the library. Use the `alembic` command (`alembic upgrade head`), inside the virtual environment. |
| The database is empty or full of old data after `docker compose up` | Data lives in the `pgdata` and `uploads` volumes and survives restarts. `docker compose down -v` deletes both, which is the way to start from zero. Without `-v` the old data and the old migrations stay. |
| Changing the `db` credentials in `docker-compose.yml` has no effect | `POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DB` only apply the first time the `pgdata` volume is created. Remove the volume (`docker compose down -v`) or point the API at another database with `COMPOSE_DATABASE_URL`. |
| The browser console says the request was blocked by CORS | The frontend origin is not in `CORS_ORIGINS` (default `http://localhost:4200`). Add it, comma separated, and restart the API. Check also that `assets/config.json` points to the API you are running. |
| Every request answers `401` right after signing in | The Clerk keys do not match: the publishable key in `frontend/src/index.html` and the backend `CLERK_SECRET_KEY` must be from the same Clerk application, and the frontend origin must be in `CLERK_AUTHORIZED_PARTIES`. |
| `401` after the app has been open for a while, or from a copied token | Clerk session tokens are short-lived. The app renews them and retries once; if the session is gone it signs you out, so sign in again. For `curl`, copy a fresh token. |
| Signed in but the menu is empty, or a screen says you have no permission | A new account has no role until an administrator assigns one (*Usuarios pendientes*). The first person on an empty database becomes `ADMIN`. |
| `npm test` fails with "No binary for ChromeHeadless" | Install Google Chrome, or set `CHROME_BIN` to its path. |
| Backend tests are skipped or fail with a pytest import error | Run them inside `backend/` with the virtual environment active. Database tests need `MIGRATED_DATABASE_URL` and `TEST_DATABASE_URL` (see [Testing and quality](#testing-and-quality)). |
| Uploaded files disappear after redeploying | Files go to `UPLOAD_DIR`. Mount a persistent volume or implement the `FileStorage` port with an object store. |

## Project status

The application covers the whole maintenance cycle and the role-based access model is complete (roles with inheritance, data scope, audit of denied access and the *Roles y permisos* screen). Open items:

- The legacy dotted permissions (`equipment.read`, ...) are still in the database so the migration can be rolled back; a final migration will remove them.
- The report builder offers five fixed inventory categories (`CATEGORIES` in `backend/app/services/report_builder.py`); they are not editable.
- Inventory figures are global: a technician sees the stock and movement metrics of the whole warehouse, not only what they consumed.
- Attachments of maintenance records are modeled in the database but have no endpoint; files and profile pictures live on the server disk (`FileStorage` port ready for an object store).
- Rate limiting is in memory per process; with several replicas move it to the proxy or a shared store.
- `npm audit` reports advisories in Angular 19 whose fix is a major upgrade (informational in CI).

## Further documentation

- [docs/api-reference.md](docs/api-reference.md) - endpoints with their permission, ticket state diagram (generated)
- [docs/rbac-matriz.md](docs/rbac-matriz.md) - permissions per role, with inheritance (generated)
- [docs/rbac-inventario.md](docs/rbac-inventario.md) - inventory of the endpoints and screens moved to the new permissions
- [docs/architecture.md](docs/architecture.md) - architecture notes
- [docs/authentication.md](docs/authentication.md) - Clerk integration
- [docs/domain-model.md](docs/domain-model.md) - database design
- [docs/deployment.md](docs/deployment.md) - operations and release checklist

## Authors

- Suley Yariza Suárez Buitrago

## License

This project was developed for academic purposes. All rights reserved.
