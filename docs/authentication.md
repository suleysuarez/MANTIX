# Authentication and authorization

The authentication module uses a layered FastAPI implementation: routes validate DTOs, the service owns authentication and token lifecycle rules, repositories query SQLAlchemy models, and database sessions are supplied through FastAPI dependency injection. Angular stores only the short-lived access token and opaque refresh token in browser storage; the backend stores only a SHA-256 digest of refresh and password-reset tokens.

## Configuration

Set these variables in the backend environment, normally `backend/.env` for local development:

```env
DATABASE_URL=postgresql+asyncpg://...
JWT_SECRET_KEY=<random-secret>
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=30
PASSWORD_RESET_EXPIRE_MINUTES=30
```

`JWT_SECRET_KEY` is required when issuing tokens and must never be committed or logged. The database foundation and existing Alembic migration are reused; this authentication feature does not create or alter tables.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/login` | Validate credentials and issue access/refresh tokens. |
| POST | `/auth/refresh` | Rotate a refresh token and issue a new token pair. |
| POST | `/auth/logout` | Revoke the supplied refresh token. |
| GET | `/auth/me` | Return safe current-user data, roles, and permissions. |
| POST | `/auth/password-reset/request` | Create a reset token without revealing account existence. |
| POST | `/auth/password-reset/confirm` | Consume a valid one-time reset token and update the password hash. |

Access tokens are JWTs with only `sub`, `type`, `iat`, and `exp` claims. Refresh tokens are cryptographically random opaque values. Rotation revokes the old database record before committing the new record, so a rotated or revoked token cannot be reused.

## RBAC

The reusable `get_authenticated_user` dependency returns HTTP 401 when the request has no valid access token. `require_permission("module.action")` builds authorization on top of it and returns HTTP 403 when an authenticated user lacks the permission. The approved role vocabulary is `ADMIN`, `SUPERVISOR`, `TECHNICIAN`, and `EMPLOYEE` (the Spanish display label `empleado` may be used as the role name, but the stable code remains `EMPLOYEE`). Permissions are resolved through `user_roles` and `role_permissions`; route handlers do not contain role conditionals.

## Angular flow

The `/auth/login` lazy route validates the form and calls FastAPI. `AuthService` owns the session state. `authGuard` protects the dashboard, and the functional HTTP interceptor attaches the access token. A single shared refresh observable handles concurrent 401 responses; successful refresh retries the original requests, while a failed refresh clears the session and returns the user to `/auth/login`.

## Local verification

Run the backend tests and checks from `backend`:

```bash
.venv/bin/ruff check app tests
.venv/bin/ruff format --check app tests
.venv/bin/pytest
```

Build Angular from `frontend`:

```bash
npm ci
npm run build
```

The frontend expects FastAPI at `http://localhost:8000` during local development. CORS remains configured by the backend environment.
