"""Role/permission enforcement across the whole API.

The matrix in `app.core.permissions` is the contract. These tests prove that
(1) every endpoint requires authentication, (2) every permission-protected
endpoint answers 403 for exactly the roles the matrix leaves out, and (3) the
rows seeded by the Alembic migrations match the matrix.
"""

import os
import re
from types import SimpleNamespace

import pytest
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from app.api.dependencies import (
    RequirePermission,
    get_authenticated_user,
)
from app.core.authz import ADMIN, AUDITOR, EMPLOYEE, SUPERVISOR, TECHNICIAN, AuthContext
from app.core.config import Settings
from app.core.exceptions import ConflictError, ForbiddenError, NotFoundError
from app.core.permissions import (
    ALL_PERMISSIONS,
    CATALOG_SET,
    ROLE_PERMISSIONS,
    effective_for_system_roles,
)
from app.main import API_ROUTERS, app
from app.services.admin import AdminUserService

PUBLIC_PATHS = {"/health", "/docs", "/redoc", "/openapi.json", "/docs/oauth2-redirect"}
LEGACY_ROLES = [ADMIN, SUPERVISOR, TECHNICIAN, EMPLOYEE]
ROLES = [*LEGACY_ROLES, AUDITOR]


def dependency_calls(route: APIRoute):
    stack = [route.dependant]
    while stack:
        node = stack.pop()
        yield node.call
        stack.extend(node.dependencies)


def api_routes():
    """Every endpoint of the application routers (FastAPI nests included routers)."""
    return [
        route
        for router in API_ROUTERS
        for route in router.routes
        if isinstance(route, APIRoute) and route.path not in PUBLIC_PATHS
    ]


def required_permission(route: APIRoute) -> str | None:
    for call in dependency_calls(route):
        if isinstance(call, RequirePermission):
            return call.code
    return None


def concrete_path(route: APIRoute) -> str:
    return re.sub(r"\{[^}]+\}", "1", route.path)


def user_for(role_code: str):
    """A person holding the system role's permissions (its own plus its ancestors')."""
    permissions = [
        SimpleNamespace(code=code, is_active=True)
        for code in sorted(effective_for_system_roles(role_code))
    ]
    return SimpleNamespace(
        id=900,  # nobody the routes' path ids ("1") could point at: not a change to oneself
        roles=[
            SimpleNamespace(code=role_code, is_active=True, permissions=permissions)
        ],
    )


@pytest.fixture
def client():
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


# -- matrix sanity (the legacy matrix is checked against the database below) ----


def test_every_permission_used_by_a_route_exists_in_the_catalogue():
    used = {code for route in api_routes() if (code := required_permission(route))}
    assert used
    assert used <= CATALOG_SET


# -- endpoint enforcement -------------------------------------------------------


def test_every_endpoint_requires_authentication(client):
    routes = api_routes()
    assert len(routes) > 25
    for route in routes:
        method = next(iter(route.methods))
        response = client.request(method, concrete_path(route))
        assert response.status_code == 401, (method, route.path, response.status_code)


def _matrix_cases():
    for route in api_routes():
        permission = required_permission(route)
        if permission is None:
            continue
        for method in sorted(route.methods):
            for role in ROLES:
                yield pytest.param(
                    method,
                    route,
                    role,
                    permission,
                    id=f"{role}-{method}-{route.path}",
                )


@pytest.mark.parametrize(("method", "route", "role", "permission"), _matrix_cases())
def test_endpoint_follows_the_role_matrix(client, method, route, role, permission):
    app.dependency_overrides[get_authenticated_user] = lambda: user_for(role)
    response = client.request(method, concrete_path(route), json={})
    allowed = permission in effective_for_system_roles(role)
    if allowed:
        # Past the permission check; the stack below is not wired in this test.
        assert response.status_code != 403
    else:
        assert response.status_code == 403
        assert response.json()["code"] == "forbidden"


# -- reusable dependencies --------------------------------------------------------


def test_dependencies_expose_what_they_require():
    assert RequirePermission("equipos:ver").code == "equipos:ver"


def test_inactive_roles_and_permissions_grant_nothing():
    user = SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                code=ADMIN,
                is_active=False,
                permissions=[SimpleNamespace(code="users.manage", is_active=True)],
            ),
            SimpleNamespace(
                code=EMPLOYEE,
                is_active=True,
                permissions=[SimpleNamespace(code="equipment.read", is_active=False)],
            ),
        ],
    )
    context = AuthContext.from_user(user)
    assert context.roles == {EMPLOYEE}
    assert context.permissions == frozenset()


# -- admin: matrix view and revocation ------------------------------------------


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


class FakeNotifications:
    def __init__(self):
        self.sent = []

    def notify(self, **kwargs):
        self.sent.append(kwargs)


class FakeAdminRepository:
    def __init__(self, user_roles, admin_count=2):
        self.user_roles = user_roles  # {(user_id, role_id): SimpleNamespace}
        self.admin_count = admin_count
        self.committed = False
        self.removed = []

    async def get_user_role(self, user_id, role_id):
        return self.user_roles.get((user_id, role_id))

    async def count_active_users_with_role(self, role_code):
        return self.admin_count

    async def remove_user_role(self, user_role):
        self.removed.append(user_role)

    async def commit(self):
        self.committed = True

    async def reload_user(self, user_id):
        return SimpleNamespace(id=user_id, email="u@x.co", full_name="U", user_roles=[])


def admin_service(user_roles, admin_count=2):
    repo = FakeAdminRepository(user_roles, admin_count)
    return AdminUserService(repo, FakeAudit(), FakeNotifications()), repo


def membership(role_code, role_id):
    return SimpleNamespace(
        role_id=role_id, role=SimpleNamespace(code=role_code, name=role_code.title())
    )


ADMIN_ACTOR = AuthContext.for_roles(SimpleNamespace(id=1), ADMIN)


async def test_revoke_role_removes_audits_and_notifies():
    service, repo = admin_service({(5, 30): membership(EMPLOYEE, 30)})
    result = await service.revoke_role(5, 30, ADMIN_ACTOR)
    assert result.id == 5
    assert len(repo.removed) == 1 and repo.committed
    assert service.audit.records[0]["action"] == "roles.revoked"
    assert service.notifications.sent[0]["notification_type"] == "role_revoked"


async def test_revoke_unknown_membership_is_404():
    service, _ = admin_service({})
    with pytest.raises(NotFoundError):
        await service.revoke_role(5, 30, ADMIN_ACTOR)


async def test_admin_cannot_revoke_own_admin_role():
    service, repo = admin_service({(1, 10): membership(ADMIN, 10)})
    with pytest.raises(ForbiddenError, match="propios roles"):
        await service.revoke_role(1, 10, ADMIN_ACTOR)
    assert not repo.removed


async def test_last_active_admin_cannot_be_revoked():
    service, repo = admin_service({(2, 10): membership(ADMIN, 10)}, admin_count=1)
    with pytest.raises(ConflictError, match="last active ADMIN"):
        await service.revoke_role(2, 10, ADMIN_ACTOR)
    assert not repo.removed


async def test_another_admin_can_be_revoked_when_more_than_one_exists():
    service, repo = admin_service({(2, 10): membership(ADMIN, 10)}, admin_count=2)
    await service.revoke_role(2, 10, ADMIN_ACTOR)
    assert len(repo.removed) == 1


# -- seeded data == matrix ---------------------------------------------------------

MIGRATED_DATABASE_URL = os.environ.get("MIGRATED_DATABASE_URL", "")


async def test_migration_seeds_match_the_canonical_matrix():
    if not MIGRATED_DATABASE_URL:
        pytest.skip("MIGRATED_DATABASE_URL is not set (needs `alembic upgrade head`)")
    url = Settings(database_url=MIGRATED_DATABASE_URL).database_url
    engine = create_async_engine(url)
    try:
        async with engine.connect() as conn:
            rows = (
                await conn.execute(
                    text(
                        "SELECT r.code, p.code FROM roles r "
                        "JOIN role_permissions rp ON rp.role_id = r.id "
                        "JOIN permissions p ON p.id = rp.permission_id "
                        "WHERE r.is_active AND p.is_active"
                    )
                )
            ).all()
            known = {
                row[0]
                for row in (await conn.execute(text("SELECT code FROM permissions")))
            }
    finally:
        await engine.dispose()
    # Only the legacy dotted permissions and the four original roles: the `recurso:accion`
    # catalogue and the AUDITOR role have their own tests (test_rbac_hierarchy.py).
    known = {code for code in known if ":" not in code}
    seeded: dict[str, set[str]] = {role: set() for role in LEGACY_ROLES}
    for role_code, permission_code in rows:
        if role_code in seeded and ":" not in permission_code:
            seeded[role_code].add(permission_code)
    assert {role: frozenset(codes) for role, codes in seeded.items()} == dict(
        ROLE_PERMISSIONS
    )
    assert known == ALL_PERMISSIONS
