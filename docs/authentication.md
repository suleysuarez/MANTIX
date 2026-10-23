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

The existing `roles`, `permissions`, `user_roles`, and `role_permissions` tables remain authoritative. `require_permission("recurso:accion")` distinguishes authenticated users without a permission (403) from unauthenticated requests (401). Permissions use the `recurso:accion` format (for example `tickets:asignar`) and roles inherit from a parent role, so the effective permissions of a person are their roles' own plus every ancestor's (`app/core/rbac.py`). Routes that any signed-in person may use (own profile, notifications, attachments) declare `require_authenticated()` instead. The permission matrix is in [rbac-matriz.md](rbac-matriz.md).

## Session handling in the browser

`authInterceptor` (`frontend/src/app/core/auth.interceptor.ts`) adds the Clerk session token to every call to the API. On `401` it asks Clerk for a fresh token and retries once; if that fails it signs the person out. On `403` it shows the server message in Spanish. A `PermissionsService` reads the effective permissions from `/auth/me` and refreshes them when the person's roles change and when the session renews (at most once per minute).

## Pending-user administration

People who sign in for the first time have no role. Administrators (`usuarios:asignar`) use:

```text
GET    /admin/users/pending
GET    /admin/roles
POST   /admin/users/{user_id}/roles          { "role_ids": [1, 2] }
DELETE /admin/users/{user_id}/roles/{role_id}
```

Rules enforced by the backend: only whoever holds `usuarios:asignar` can change roles; nobody changes their own roles; a role can only be given or taken away by someone who already has every permission it carries; the last active ADMIN cannot be revoked. Changes are audited and notify the person. The Angular page is `/admin/pending-users`.

## Roles and permissions administration

Administrators manage the roles themselves from the *Roles y permisos* screen (`/roles`):

```text
GET    /admin/roles/manage                 roles with hierarchy, own and inherited permissions
POST   /admin/roles                        create a custom role
PATCH  /admin/roles/{role_id}              rename, change parent, activate or deactivate
PUT    /admin/roles/{role_id}/permissions  replace the permissions the role grants itself
DELETE /admin/roles/{role_id}              delete a custom role
GET    /admin/permissions                  the permission catalogue
```

Role names are unique ignoring case, inheritance cannot form a cycle and is limited to 6 levels. Base roles cannot be deleted, deactivated or moved; the Administrator role cannot be edited; a role with users, or that is a parent, cannot be deleted or deactivated; nobody edits a role they hold or grants a permission they lack. Every change is written to the audit trail with its before and after values (`roles.created`, `roles.updated`, `roles.permissions_changed`, `roles.deleted`).
