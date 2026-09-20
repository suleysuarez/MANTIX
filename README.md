# Technology Equipment Maintenance System

This repository provides the production-oriented foundation for a technology equipment maintenance system. The current stage establishes architecture, configuration, migrations, containers, and CI; business functionality is intentionally deferred.

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
cp .env.example .env
# edit .env and set DATABASE_URL and any permitted CORS origins
```

`DATABASE_URL` is read only by the backend and Alembic. Do not commit `.env`, credentials, tokens, or API keys.

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

No business tables or migrations are included at this stage.

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

The next stage should define domain models and contracts for equipment, locations, technicians, users, and maintenance records, then add the first vertical slice with migrations, API tests, and corresponding lazy-loaded Angular UI. Authentication and authorization should be designed before exposing protected business endpoints.
