"""HTTP-level contract: error shape, pagination headers, priorities, OpenAPI."""

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.authz import AuthContext
from app.core.exceptions import ConflictError, NotFoundError
from app.main import app
from app.repositories.base import Page
from app.schemas.priority import PriorityCreate, PriorityUpdate
from app.services.priority import PriorityService


def role(code, *permissions):
    return SimpleNamespace(
        code=code,
        is_active=True,
        permissions=[SimpleNamespace(code=p, is_active=True) for p in permissions],
    )


def user_with(code, *permissions):
    return SimpleNamespace(id=1, roles=[role(code, *permissions)])


@pytest.fixture
def client():
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def sign_in(code, *permissions):
    app.dependency_overrides[get_authenticated_user] = lambda: user_with(
        code, *permissions
    )


class RaisingService:
    def __init__(self, error):
        self.error = error

    async def list_requests(self, **_):
        raise self.error


def assert_error_shape(body, code):
    assert set(body) == {"detail", "code", "errors", "request_id"}
    assert body["code"] == code
    assert isinstance(body["detail"], str)


def test_domain_error_uses_uniform_body(client):
    sign_in("ADMIN", "maintenance.read")
    app.dependency_overrides[providers.get_maintenance_service] = lambda: (
        RaisingService(NotFoundError("maintenance request not found"))
    )
    response = client.get("/maintenance/requests", headers={"X-Request-ID": "abc123"})
    assert response.status_code == 404
    body = response.json()
    assert_error_shape(body, "not_found")
    assert body["detail"] == "maintenance request not found"
    assert body["request_id"] == "abc123"


def test_conflict_maps_to_409(client):
    sign_in("ADMIN", "maintenance.read")
    app.dependency_overrides[providers.get_maintenance_service] = lambda: (
        RaisingService(ConflictError("duplicate"))
    )
    response = client.get("/maintenance/requests")
    assert response.status_code == 409
    assert_error_shape(response.json(), "conflict")


def test_permission_denied_uses_uniform_body(client):
    sign_in("EMPLOYEE")
    response = client.get("/maintenance/requests")
    assert response.status_code == 403
    assert_error_shape(response.json(), "forbidden")


def test_validation_error_lists_fields_without_echoing_input(client):
    sign_in("ADMIN", "maintenance.create")
    response = client.post(
        "/maintenance/requests",
        json={"equipment_id": "oops", "title": "", "description": "secret-value"},
    )
    assert response.status_code == 422
    body = response.json()
    assert_error_shape(body, "validation_error")
    fields = {error["field"] for error in body["errors"]}
    assert {"equipment_id", "title"} <= fields
    assert "secret-value" not in response.text


def test_unexpected_error_is_hidden_behind_a_generic_500(client):
    sign_in("ADMIN", "maintenance.read")
    app.dependency_overrides[providers.get_maintenance_service] = lambda: (
        RaisingService(RuntimeError("db password is hunter2"))
    )
    response = client.get("/maintenance/requests")
    assert response.status_code == 500
    assert_error_shape(response.json(), "internal_error")
    assert "hunter2" not in response.text


def test_unknown_route_uses_uniform_body(client):
    response = client.get("/nope")
    assert response.status_code == 404
    assert_error_shape(response.json(), "not_found")


def test_missing_credentials_return_401_in_the_same_shape(client):
    response = client.get("/maintenance/requests")
    assert response.status_code == 401
    assert_error_shape(response.json(), "unauthorized")


class PagedService:
    def __init__(self):
        self.kwargs = None

    async def list_requests(self, **kwargs):
        self.kwargs = kwargs
        return Page(items=[], total=45, page=2, size=20)


def test_pagination_params_reach_the_service_and_headers_come_back(client):
    sign_in("ADMIN", "maintenance.read")
    service = PagedService()
    app.dependency_overrides[providers.get_maintenance_service] = lambda: service
    response = client.get(
        "/maintenance/requests?page=2&size=20&sort=-priority&search=screen"
    )
    assert response.status_code == 200
    assert response.headers["X-Total-Count"] == "45"
    assert response.headers["X-Page"] == "2"
    assert response.headers["X-Page-Size"] == "20"
    assert response.headers["X-Total-Pages"] == "3"
    params = service.kwargs["params"]
    assert (params.page, params.size, params.sort) == (2, 20, "-priority")
    assert service.kwargs["search"] == "screen"


def test_legacy_limit_and_offset_still_work_and_defaults_are_unchanged(client):
    sign_in("ADMIN", "maintenance.read")
    service = PagedService()
    app.dependency_overrides[providers.get_maintenance_service] = lambda: service
    client.get("/maintenance/requests?limit=50&offset=100")
    assert (service.kwargs["params"].size, service.kwargs["params"].offset) == (50, 100)
    client.get("/maintenance/requests")
    assert service.kwargs["params"].size == 200  # legacy listing default


@pytest.mark.parametrize("query", ["page=0", "size=0", "size=9999", "sort=a;drop"])
def test_invalid_pagination_params_are_rejected(client, query):
    sign_in("ADMIN", "maintenance.read")
    response = client.get(f"/maintenance/requests?{query}")
    assert response.status_code == 422


# -- priorities ---------------------------------------------------------------


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


class FakePriorityRepository:
    def __init__(self):
        self.items = []
        self.committed = False

    async def list(self, *, include_inactive=False):
        return [i for i in self.items if include_inactive or i.is_active]

    async def get(self, priority_id):
        return next((i for i in self.items if i.id == priority_id), None)

    async def get_by_code(self, code):
        return next((i for i in self.items if i.code == code), None)

    async def add_and_flush(self, entity):
        entity.id = len(self.items) + 1
        entity.created_at = "2026-10-11T12:00:00Z"
        self.items.append(entity)
        return entity

    async def update_fields(self, entity, values):
        for key, value in values.items():
            setattr(entity, key, value)
        return entity

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


def priority_service():
    return PriorityService(FakePriorityRepository(), FakeAudit())


ACTOR = AuthContext(user=SimpleNamespace(id=9), roles=frozenset({"ADMIN"}))


async def test_priority_create_audits_and_rejects_duplicates():
    service = priority_service()
    payload = PriorityCreate(code="urgent", name="Urgent", level=5, sla_hours=1)
    created = await service.create(payload, ACTOR)
    assert created.code == "urgent"
    assert service.audit.records[0]["action"] == "priority.created"
    with pytest.raises(ConflictError):
        await service.create(payload, ACTOR)


async def test_priority_update_records_old_and_new_values_and_404s():
    service = priority_service()
    await service.create(PriorityCreate(code="low", name="Low", level=1), ACTOR)
    updated = await service.update(1, PriorityUpdate(level=2, is_active=False), ACTOR)
    assert (updated.level, updated.is_active) == (2, False)
    record = service.audit.records[-1]
    assert record["old_values"] == {"level": 1, "is_active": True}
    assert record["new_values"] == {"level": 2, "is_active": False}
    assert await service.list() == []  # inactive hidden
    assert len(await service.list(include_inactive=True)) == 1
    with pytest.raises(NotFoundError):
        await service.update(99, PriorityUpdate(name="x"), ACTOR)


@pytest.mark.parametrize("code", ["High", "1abc", "a", "with space", "x" * 21])
def test_priority_code_must_be_a_slug(code):
    with pytest.raises(ValueError):
        PriorityCreate(code=code, name="n", level=1)


def test_priority_endpoints_require_the_manage_permission(client):
    sign_in("SUPERVISOR", "maintenance.read")
    response = client.post(
        "/priorities", json={"code": "urgent", "name": "Urgent", "level": 5}
    )
    assert response.status_code == 403


# -- OpenAPI --------------------------------------------------------------------


def test_openapi_documents_tags_error_model_and_examples():
    schema = app.openapi()
    assert {t["name"] for t in schema["tags"]} >= {"maintenance", "priorities"}
    operation = schema["paths"]["/maintenance/requests"]["get"]
    assert operation["summary"] == "List maintenance tickets"
    assert {"401", "403", "422", "429"} <= set(operation["responses"])
    assert operation["responses"]["403"]["content"]["application/json"]["schema"][
        "$ref"
    ].endswith("ErrorResponse")
    assert "example" in schema["components"]["schemas"]["MaintenanceRequestCreate"]
    assert "/priorities" in schema["paths"]
