# Clerk authentication and local authorization

The application now uses Clerk as the identity and session authority. Angular loads ClerkJS from the provided CDN snippet, Clerk owns sign-in, sign-up, password recovery, session lifecycle, and sign-out, and FastAPI verifies the Clerk session token before resolving the local application profile.

```text
Angular + ClerkJS
        │  Authorization: Bearer <Clerk session token>
        ▼
FastAPI + Clerk Python SDK verification
        ▼
users.clerk_user_id
        ▼
local roles → permissions in Neon
```

## Configuration

The backend reads Clerk configuration from `backend/.env`:

```env
CLERK_SECRET_KEY=<server-only secret>
CLERK_PUBLISHABLE_KEY=<public key>
CLERK_AUTHORIZED_PARTIES=http://localhost:4200
```

`CLERK_SECRET_KEY` must never be copied into Angular, committed, logged, or returned by an endpoint. The provided publishable key is intentionally present in `frontend/src/index.html` because it is public by design. `backend/.env.example` contains placeholders only.

## Angular integration

The exact Clerk CDN scripts supplied for this project are in `frontend/src/index.html`. `ClerkService` is the only application service that accesses `window.Clerk`. It initializes Clerk once, loads the Clerk UI bundle, exposes the current authentication state, retrieves the active session token, mounts `SignIn` and `UserButton`, and delegates sign-out to Clerk.

The `/auth/login` route is only a host for Clerk's mounted `SignIn` component. It does not collect or submit passwords. The authenticated dashboard mounts Clerk's `UserButton`. `authGuard` waits for Clerk initialization and allows only signed-in sessions. The Angular interceptor attaches a Clerk session token only to requests whose URL starts with the FastAPI API URL; it never stores tokens in `localStorage`, refreshes custom JWTs, or intercepts Clerk's own requests.

## Backend verification

FastAPI uses the official `clerk-backend-api` SDK's `authenticate_request` boundary with the server-only `CLERK_SECRET_KEY` and the configured authorized parties. The backend does not decode an unverified JWT. Missing, invalid, expired, or unconfigured Clerk authentication produces HTTP 401.

`GET /auth/me` is an application-profile endpoint. It does not issue tokens, refresh sessions, manage passwords, or perform password recovery. It verifies the Clerk request, resolves the Clerk `sub` claim, provisions or loads the local profile, and returns local roles and permissions.

## Clerk-to-local provisioning

The local `users` table remains the application profile table. A new nullable, unique, indexed `users.clerk_user_id` column links it to Clerk. The new migration is `b2c7f1a8d4e1_add_clerk_user_id_to_users.py`; it does not edit or replace the already-applied initial migration.

When a verified Clerk user is first encountered, the backend resolves the Clerk email and display name and creates the local profile. The first user is assigned the existing `ADMIN` role only when the local database has no `user_roles` records. This is based on local application state, never Clerk creation metadata. The bootstrap check is serialized with a PostgreSQL transaction-scoped advisory lock, so concurrent first logins cannot both receive `ADMIN`.

Every subsequent new user is created without a `user_roles` record. This is the pending-authorization state: the person is authenticated by Clerk and has a local profile, but has no application permissions. A local email already linked to a different Clerk identity fails with HTTP 409 rather than silently reassigning ownership. Inactive local profiles return HTTP 403.

The existing `roles`, `permissions`, `user_roles`, and `role_permissions` tables remain authoritative. `require_permission("module.action")` continues to distinguish authenticated users without a permission (403) from unauthenticated requests (401).

## Legacy table cleanup

`user_credentials`, `refresh_tokens`, and `password_reset_tokens` are no longer part of the active SQLAlchemy model or any Clerk flow. Migration `c4d8e2f1a9b7_drop_legacy_auth_tables.py` removes those three obsolete tables without editing the applied initial migration. The migration preserves `users`, `roles`, `permissions`, `user_roles`, and `role_permissions`.

## Validation

Backend checks:

```bash
cd backend
.venv/bin/ruff check app tests
.venv/bin/ruff format --check app tests
.venv/bin/alembic heads
.venv/bin/pytest
```

The backend tests mock the Clerk verification boundary and cover missing and invalid authentication, valid identity extraction, first-user ADMIN provisioning, subsequent pending users, concurrent first-login safety, inactive users, `/auth/me` mapping, and RBAC allow/deny behavior.

Frontend checks:

```bash
cd frontend
npm ci
npm run build
npm test -- --watch=false --browsers=ChromeHeadless
```

The Angular production build is available in the current environment. Karma unit tests are configured, but execution requires a Chrome/Chromium binary in the environment.
