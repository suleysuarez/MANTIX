from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.pagination import PageParams
from app.core.request_context import RequestInfo, get_request_info, set_request_info
from app.main import app
from app.models.auth import User
from app.repositories.audit import AuditRepository
from app.repositories.base import Page
from app.schemas.audit import AuditLogResponse
from app.services.audit import AuditService


def audit_row(**overrides):
    row = {
        "id": 1,
        "user": SimpleNamespace(id=2, full_name="Ana Ruiz", email="ana@example.com"),
        "action": "equipment.updated",
        "entity_type": "equipment",
        "entity_id": 7,
        "old_values": {"status": "assigned"},
        "new_values": {"status": "retired"},
        "ip_address": "203.0.113.7",
        "created_at": datetime(2026, 10, 11, 15, 0, tzinfo=UTC),
    }
    return SimpleNamespace(**{**row, **overrides})


class FakeAuditRepository:
    def __init__(self):
        self.kwargs = None

    async def search(self, **kwargs):
        self.kwargs = kwargs
        return Page(
            items=[audit_row(), audit_row(id=2, user=None)], total=2, page=1, size=20
        )


def test_audit_staging_stamps_request_metadata():
    repo = AuditRepository(session=None)
    staged = []
    repo.add = staged.append  # no database needed to inspect the row
    set_request_info(RequestInfo("203.0.113.7", "pytest-agent/1.0", "req-1"))
    try:
        repo.record(user_id=1, action="x.y", entity_type="x", entity_id=1)
    finally:
        set_request_info(None)
    assert staged[0].ip_address == "203.0.113.7"
    assert staged[0].user_agent == "pytest-agent/1.0"


def test_audit_staging_outside_a_request_leaves_metadata_empty():
    repo = AuditRepository(session=None)
    staged = []
    repo.add = staged.append
    repo.record(user_id=None, action="job.run", entity_type="job", entity_id=None)
    assert staged[0].ip_address is None and staged[0].user_agent is None


def test_audit_staging_truncates_oversized_user_agents():
    repo = AuditRepository(session=None)
    staged = []
    repo.add = staged.append
    set_request_info(RequestInfo("1.2.3.4", "A" * 2000, None))
    try:
        repo.record(user_id=1, action="a.b", entity_type="a", entity_id=None)
    finally:
        set_request_info(None)
    assert len(staged[0].user_agent) == 500


async def test_service_maps_rows_to_the_response_schema():
    service = AuditService(FakeAuditRepository())
    page = await service.search(entity_type="equipment", params=PageParams(size=20))
    assert page.total == 2
    first, system = page.items
    assert isinstance(first, AuditLogResponse)
    assert first.user.full_name == "Ana Ruiz"
    assert first.old_values == {"status": "assigned"}
    assert system.user is None


def test_middleware_stores_request_info_for_the_request(monkeypatch):
    captured = {}

    class SpyService:
        async def search(self, **_):
            captured["info"] = get_request_info()
            return Page(items=[], total=0, page=1, size=20)

    app.dependency_overrides[providers.get_audit_service] = lambda: SpyService()
    app.dependency_overrides[get_authenticated_user] = lambda: SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                code="SUPERVISOR",
                is_active=True,
                permissions=[SimpleNamespace(code="audit.read", is_active=True)],
            )
        ],
    )
    try:
        with TestClient(app) as client:
            client.get(
                "/audit-logs",
                headers={"User-Agent": "unit-test/2.0", "X-Request-ID": "trace-9"},
            )
    finally:
        app.dependency_overrides.clear()
    assert captured["info"].user_agent == "unit-test/2.0"
    assert captured["info"].request_id == "trace-9"
    assert captured["info"].ip_address


@pytest.fixture
def client():
    repo = FakeAuditRepository()
    app.dependency_overrides[providers.get_audit_service] = lambda: AuditService(repo)
    app.dependency_overrides[get_authenticated_user] = lambda: SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                code="SUPERVISOR",
                is_active=True,
                permissions=[SimpleNamespace(code="audit.read", is_active=True)],
            )
        ],
    )
    with TestClient(app, raise_server_exceptions=False) as test_client:
        test_client.repo = repo
        yield test_client
    app.dependency_overrides.clear()


def test_audit_endpoint_filters_paginates_and_documents_values(client):
    response = client.get(
        "/audit-logs?entity_type=equipment&entity_id=7&action=equipment.updated"
        "&user_id=2&page=1&size=20&sort=-created_at&date_from=2026-10-01T00:00:00Z"
    )
    assert response.status_code == 200
    body = response.json()
    assert body[0]["old_values"] == {"status": "assigned"}
    assert body[0]["new_values"] == {"status": "retired"}
    assert body[0]["user"]["full_name"] == "Ana Ruiz"
    assert body[1]["user"] is None
    assert response.headers["X-Total-Count"] == "2"
    kwargs = client.repo.kwargs
    assert (kwargs["entity_type"], kwargs["entity_id"], kwargs["user_id"]) == (
        "equipment",
        7,
        2,
    )
    assert kwargs["params"].sort == "-created_at"
    assert kwargs["date_from"] == datetime(2026, 10, 1, tzinfo=UTC)


# -- real database ---------------------------------------------------------------------


async def test_audit_rows_persist_ip_and_user_agent_and_are_searchable(db_session):
    user = User(clerk_user_id="c1", email="a@x.co", full_name="Ana", is_active=True)
    db_session.add(user)
    await db_session.flush()
    repo = AuditRepository(db_session)
    set_request_info(RequestInfo("198.51.100.4", "curl/8", None))
    try:
        repo.record(
            user_id=user.id,
            action="priority.updated",
            entity_type="priority",
            entity_id=3,
            old_values={"level": 1},
            new_values={"level": 2},
        )
    finally:
        set_request_info(None)
    await db_session.flush()

    page = await repo.search(user_id=user.id, entity_type="priority", entity_id=3)
    (row,) = page.items
    assert row.ip_address == "198.51.100.4" and row.user_agent == "curl/8"
    assert (row.old_values, row.new_values) == ({"level": 1}, {"level": 2})
    assert row.user.full_name == "Ana"  # eagerly loaded for the response
    response = AuditLogResponse.model_validate(row)
    assert response.user.email == "a@x.co"
