# Technology Equipment Maintenance System

This repository provides the production-oriented foundation for a technology equipment maintenance system. The current stage includes the approved database foundation, CI, and a complete authentication and authorization slice; business modules remain intentionally separate.

## Architecture

The Angular frontend communicates with the FastAPI backend over REST/HTTP. Only the backend connects to Neon PostgreSQL through SQLAlchemy. Neon credentials remain server-side and are never exposed to Angular.

The frontend uses standalone Angular components, strict TypeScript, Angular Router, HttpClient, and lazy-loaded feature routes. Its structure is organized by `core`, `shared`, `layout`, and business `features`. The backend uses layered boundaries between API routes, schemas, services, repositories, models, database utilities, and core configuration.

## Technology stack

- Angular and TypeScript
- FastAPI and Python
- PostgreSQL on Neon
- SQLAlchemy and Alembic
- Docker Compose
- GitHub Actions

## Repository structure

```text
backend/       FastAPI application, database setup, Alembic, tests
frontend/      Angular standalone application
docs/          Architecture documentation
.github/       Continuous integration workflow
docker-compose.yml
.env.example
```

## Environment setup

```bash
cd backend
cp .env.example .env
# set DATABASE_URL, JWT_SECRET_KEY, and permitted CORS origins
```

`DATABASE_URL` is read only by the backend and Alembic. Authentication secrets are read by the backend only. Do not commit `.env`, credentials, tokens, or API keys.

## Local development

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --port 8000
```

In a second terminal:

```bash
cd frontend
npm install
npm start
```

The API health endpoint is available at `http://localhost:8000/health`.

## Docker

Docker Compose runs only the `backend` and `frontend` services. There is deliberately no PostgreSQL container because the database is Neon.

```bash
docker compose up --build
docker compose down
```

## Database migrations

With `DATABASE_URL` configured and the backend environment active:

```bash
cd backend
alembic revision --autogenerate -m "describe change"
alembic upgrade head
```

The initial migration is already part of the repository and must be reviewed before any future schema change is applied.

## Authentication

Authentication endpoints are documented in [docs/authentication.md](docs/authentication.md). The backend provides login, access-token validation, refresh-token rotation, logout, current-user, and password-reset endpoints. Angular provides the `/auth/login` page, a route guard, session state, and a refresh-aware HTTP interceptor. The reusable RBAC dependency distinguishes unauthenticated `401` responses from authenticated-but-unauthorized `403` responses.

## Testing, linting, and build

```bash
cd backend && pytest
cd backend && ruff check app tests
cd backend && ruff format --check app tests
cd frontend && npm run build
```

The CI workflow runs these checks without inventing placeholder tests.

## CI workflow

`.github/workflows/ci.yml` installs dependencies, checks backend imports and formatting/linting, runs backend tests only when test files exist, installs frontend dependencies, performs a production Angular build, and validates Docker Compose configuration.

## Next development stage

The next stage can add protected equipment and maintenance vertical slices using `get_authenticated_user` and `require_permission(...)`; it should not duplicate token or role checks in individual route handlers.
