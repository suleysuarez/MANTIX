# Architecture

## Runtime boundary

```text
Angular
   │
   │ REST/HTTP
   ▼
FastAPI
   │
   │ SQLAlchemy
   ▼
Neon PostgreSQL
```

The browser communicates exclusively with FastAPI. `DATABASE_URL` is consumed by backend configuration and Alembic only; it is never included in frontend code or browser configuration.

## Frontend

The Angular application is organized by responsibility and feature rather than global business-type folders:

```text
Core       cross-cutting services, guards, interceptors, and models
Shared     reusable components, directives, pipes, and utilities
Layout     application shell, navigation, sidebar, and footer
Features   auth, dashboard, equipos, mantenimientos, usuarios, tecnicos,
           ubicaciones, and reportes
```

Each feature can own its components, pages, services, models, and routes. Routes are lazy-loaded so future business capabilities remain isolated and independently extendable. Standalone components and strict TypeScript are enabled.

## Backend

The backend follows explicit layers:

```text
API             HTTP routes and dependency injection
Schemas         Pydantic request and response validation
Services        business logic boundary
Repositories    persistence and query boundary
Models          SQLAlchemy mappings
DB              engine, sessions, and declarative base
Core            environment and cross-cutting configuration
```

The current API exposes only a health endpoint. No CRUD, authentication, authorization, or business rules are implemented yet.

## Data and secrets

Neon is the database from day one. The application expects `DATABASE_URL` in the environment and uses SQLAlchemy with PostgreSQL. Alembic reads the same setting for migrations. `.env` is ignored by Git, while `.env.example` contains placeholders only. Future CI secrets should be provided with GitHub Secrets.

## Containers and CI

Docker Compose starts the frontend and backend only. The backend health check gates frontend startup; no local PostgreSQL service is defined. GitHub Actions progressively validates backend dependencies, linting, formatting, import/startup behavior, real tests when present, frontend dependencies, and the production build.
