"""What phase 2 enforces: declared permissions on every route, audited denials, hidden money."""

from types import SimpleNamespace

import pytest
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from app.api.dependencies import (
    AuthenticatedOnly,
    RequirePermission,
    get_authenticated_user,
)
from app.api.redaction import hide_one_unless, hide_unless
from app.core import access_audit
from app.core.authz import AuthContext
from app.core.permissions import CATALOG_SET
from app.main import API_ROUTERS, app
from app.schemas.technician import TechnicianResponse

PUBLIC_PATHS = {"/health", "/docs", "/redoc", "/openapi.json", "/docs/oauth2-redirect"}


def routes():
    return [
        r
        for router in API_ROUTERS
        for r in router.routes
        if isinstance(r, APIRoute) and r.path not in PUBLIC_PATHS
    ]


def guards(route):
    stack, found = [route.dependant], []
    while stack:
        node = stack.pop()
        found.append(node.call)
        stack.extend(node.dependencies)
    return found


def test_every_route_declares_a_permission_or_says_it_is_open_to_any_signed_in_person():
    undeclared = [
        f"{sorted(r.methods)} {r.path}"
        for r in routes()
        if not any(
            isinstance(g, RequirePermission | AuthenticatedOnly) for g in guards(r)
        )
    ]
    assert undeclared == []


def test_no_route_uses_a_legacy_dotted_permission():
    used = {
        g.code for r in routes() for g in guards(r) if isinstance(g, RequirePermission)
    }
    assert used <= CATALOG_SET, sorted(used - CATALOG_SET)


def test_the_open_routes_are_only_the_ones_with_no_single_permission_to_ask_for():
    open_routes = {
        r.path
        for r in routes()
        if any(isinstance(g, AuthenticatedOnly) for g in guards(r))
        and not any(isinstance(g, RequirePermission) for g in guards(r))
    }
    assert open_routes == {
        "/attachments/{attachment_id}",
        "/attachments/{attachment_id}/download",
        "/auth/me",
        "/notifications",
        "/notifications/read-all",
        "/notifications/{notification_id}/read",
    }


# -- audited denials --------------------------------------------------------------------------


@pytest.fixture
def client():
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def person(*codes):
    permissions = [SimpleNamespace(code=c, name=c, is_active=True) for c in codes]
    return SimpleNamespace(
        id=42,
        roles=[SimpleNamespace(code="X", is_active=True, permissions=permissions)],
    )


def test_a_denied_request_reports_the_endpoint_and_the_missing_permission(
    client, monkeypatch
):
    seen = []

    async def capture(request, detail):
        seen.append(
            {
                "path": request.url.path,
                "permission": getattr(request.state, "denied_permission", None),
                "detail": detail,
            }
        )

    monkeypatch.setattr("app.core.errors.record_denial", capture)
    app.dependency_overrides[get_authenticated_user] = lambda: person("tickets:ver")

    response = client.get("/audit-logs")

    assert response.status_code == 403
    assert response.json()["detail"] == "No tienes permiso para realizar esta acción."
    assert seen == [
        {
            "path": "/audit-logs",
            "permission": "auditoria:ver",
            "detail": "No tienes permiso para realizar esta acción.",
        }
    ]


def test_service_level_denials_are_audited_too(client, monkeypatch):
    seen = []

    async def capture(request, detail):
        seen.append(detail)

    monkeypatch.setattr("app.core.errors.record_denial", capture)
    app.dependency_overrides[get_authenticated_user] = lambda: person("tickets:ver")
    assert client.get("/maintenance/queue/summary").status_code == 403
    assert seen


def test_a_missing_session_is_a_401_and_not_audited_as_a_denial(client, monkeypatch):
    seen = []

    async def capture(request, detail):
        seen.append(detail)

    monkeypatch.setattr("app.core.errors.record_denial", capture)
    assert client.get("/audit-logs").status_code == 401
    assert seen == []


async def test_recording_a_denial_never_raises_and_needs_somebody_to_blame(monkeypatch):
    class Boom:
        def __call__(self):
            raise RuntimeError("database is down")

    monkeypatch.setattr("app.db.session.AsyncSessionLocal", Boom())
    monkeypatch.setattr(
        access_audit, "get_settings", lambda: SimpleNamespace(audit_denials=True)
    )
    request = SimpleNamespace(
        state=SimpleNamespace(auth_user_id=7),
        method="GET",
        url=SimpleNamespace(path="/audit-logs"),
    )
    await access_audit.record_denial(request, "x")  # swallowed, only logged
    anonymous = SimpleNamespace(
        state=SimpleNamespace(), method="GET", url=SimpleNamespace(path="/x")
    )
    await access_audit.record_denial(anonymous, "x")  # nobody to attribute it to


def test_the_denial_row_says_the_endpoint_the_permission_and_the_message():
    request = SimpleNamespace(
        state=SimpleNamespace(denied_permission="usuarios:asignar"),
        method="POST",
        url=SimpleNamespace(path="/admin/users/3/roles"),
    )
    assert access_audit.denial_values(request, "msg") == {
        "method": "POST",
        "path": "/admin/users/3/roles",
        "permission": "usuarios:asignar",
        "detail": "msg",
    }


# -- hidden money -----------------------------------------------------------------------------


def technician(rate="25.00"):
    return TechnicianResponse(
        id=1,
        user_id=2,
        full_name="Tec",
        email="t@x.co",
        employee_code=None,
        specialization=None,
        is_available=True,
        is_active=True,
        hourly_rate=rate,
        created_at="2026-01-01T00:00:00Z",
    )


def test_the_hourly_rate_is_hidden_from_whoever_cannot_manage_technicians():
    viewer = AuthContext(
        user=SimpleNamespace(id=1), permissions=frozenset({"tecnicos:ver"})
    )
    manager = AuthContext(
        user=SimpleNamespace(id=2),
        permissions=frozenset({"tecnicos:ver", "tecnicos:editar"}),
    )
    hidden = hide_unless(viewer, "tecnicos:editar", [technician()], "hourly_rate")
    assert hidden[0].hourly_rate is None
    shown = hide_one_unless(manager, "tecnicos:editar", technician(), "hourly_rate")
    assert str(shown.hourly_rate) == "25.00"


def test_hiding_does_not_touch_the_original_object():
    viewer = AuthContext(user=SimpleNamespace(id=1), permissions=frozenset())
    original = technician()
    hide_one_unless(viewer, "tecnicos:editar", original, "hourly_rate")
    assert str(original.hourly_rate) == "25.00"


def test_the_technicians_route_never_returns_rates_to_a_viewer(client):
    from app.api import providers
    from app.repositories.base import Page

    class Stub:
        async def list(self, **_):
            return Page(items=[technician()], total=1, page=1, size=200)

    app.dependency_overrides[providers.get_technician_service] = lambda: Stub()
    app.dependency_overrides[get_authenticated_user] = lambda: person("tecnicos:ver")
    assert client.get("/technicians").json()[0]["hourly_rate"] is None
    app.dependency_overrides[get_authenticated_user] = lambda: person(
        "tecnicos:ver", "tecnicos:editar"
    )
    assert client.get("/technicians").json()[0]["hourly_rate"] == "25.00"


async def test_a_denial_is_written_to_the_audit_log_with_who_what_and_where(
    db_session, monkeypatch
):
    from sqlalchemy import select
    from sqlalchemy.ext.asyncio import async_sessionmaker

    from app.core.request_context import RequestInfo, set_request_info
    from app.models.audit import AuditLog
    from app.models.auth import User

    user = User(email="denied@x.co", full_name="Denied", is_active=True)
    db_session.add(user)
    await db_session.commit()  # the denial is written in its own transaction

    maker = async_sessionmaker(bind=db_session.bind, expire_on_commit=False)
    monkeypatch.setattr("app.db.session.AsyncSessionLocal", maker)
    monkeypatch.setattr(
        access_audit, "get_settings", lambda: SimpleNamespace(audit_denials=True)
    )
    set_request_info(
        RequestInfo(ip_address="203.0.113.9", user_agent="pytest", request_id="r1")
    )
    request = SimpleNamespace(
        state=SimpleNamespace(
            auth_user_id=user.id, denied_permission="usuarios:asignar"
        ),
        method="POST",
        url=SimpleNamespace(path="/admin/users/3/roles"),
    )
    try:
        await access_audit.record_denial(
            request, "No tienes permiso para realizar esta acción."
        )
    finally:
        set_request_info(None)

    rows = (await db_session.execute(select(AuditLog))).scalars().all()
    assert len(rows) == 1
    row = rows[0]
    assert (row.user_id, row.action, row.entity_type) == (
        user.id,
        "access.denied",
        "endpoint",
    )
    assert row.new_values == {
        "method": "POST",
        "path": "/admin/users/3/roles",
        "permission": "usuarios:asignar",
        "detail": "No tienes permiso para realizar esta acción.",
    }
    assert row.ip_address == "203.0.113.9" and row.created_at is not None
