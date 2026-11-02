from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.authz import AuthContext
from app.core.config import Settings
from app.core.exceptions import ConflictError, NotFoundError, UnprocessableError
from app.jobs import JobSnapshot, job_snapshots
from app.main import app
from app.repositories.settings import AuditRow, RoleRow, UserCountRow
from app.schemas.settings import (
    CategoryCreate,
    CategoryUpdate,
    OrganizationUpdate,
)
from app.services.settings import SystemSettingsService
from tests.support import expand, perm_objects

NOW = datetime(2026, 10, 14, 12, 0, tzinfo=UTC)
ACTOR = AuthContext(
    user=SimpleNamespace(id=1, full_name="Ana"),
    roles=frozenset({"ADMIN"}),
    permissions=expand("users.manage", "priorities.manage"),
)


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


class FakeRepo:
    def __init__(self, *, ping_fails=False, usage=0):
        self.ping_fails = ping_fails
        self.usage = usage
        self.categories = {}
        self.committed = 0
        self.deleted = []
        self.organization = None

    async def ping(self):
        if self.ping_fails:
            raise RuntimeError("secret connection string")

    async def user_counts(self):
        return UserCountRow(total=10, active=8, without_role=2)

    async def role_rows(self):
        return [RoleRow(1, "ADMIN", "Admin", True, 1, 20)]

    async def audit_recent(self, limit):
        return [AuditRow(1, "x.created", "x", 5, None, NOW)]

    async def audit_since(self, since):
        return 4

    async def get_category_by_code(self, code):
        return next((c for c in self.categories.values() if c.code == code), None)

    async def get_category(self, category_id):
        return self.categories.get(category_id)

    async def add_and_flush(self, category):
        category.id = len(self.categories) + 1
        category.created_at = NOW
        self.categories[category.id] = category
        return category

    async def update_fields(self, category, changes):
        for key, value in changes.items():
            setattr(category, key, value)

    async def category_usage(self, code):
        return self.usage

    async def delete_category(self, category):
        self.deleted.append(category.id)

    async def get_organization(self):
        return self.organization

    async def save_organization(self, *, company_name, user_id):
        self.organization = SimpleNamespace(
            company_name=company_name,
            updated_at=NOW,
        )
        return self.organization

    async def commit(self):
        self.committed += 1

    async def rollback(self):
        pass


def make(repo=None, **settings):
    repo = repo or FakeRepo()
    audit = FakeAudit()
    cfg = Settings(
        _env_file=None,
        clerk_secret_key=settings.pop("secret", "sk"),
        clerk_publishable_key=settings.pop("public", "pk"),
        upload_dir=settings.pop("upload_dir", "."),
    )
    return SystemSettingsService(repo, audit, cfg), repo, audit


JOB = JobSnapshot("schedule-reminders", "Reminders", True, 60, NOW, NOW, True, "0 sent")


async def test_health_collects_users_roles_audit_jobs_and_integrations():
    service, _, _ = make()
    health = await service.health([JOB], now=NOW)
    assert health.overall == "ok"
    assert (health.users.total, health.users.inactive, health.users.without_role) == (
        10,
        2,
        2,
    )
    assert health.roles[0].users == 1 and health.audit.last_24h == 4
    assert health.jobs[0].last_status == "ok"
    assert {i.key for i in health.integrations} == {"database", "clerk", "storage"}


async def test_health_never_leaks_secrets_or_internal_errors():
    service, _, _ = make(FakeRepo(ping_fails=True), secret="super-secret")
    health = await service.health([JOB], now=NOW)
    dump = health.model_dump_json()
    assert "super-secret" not in dump and "connection string" not in dump
    assert health.overall == "error"
    database = next(i for i in health.integrations if i.key == "database")
    assert database.status == "error" and database.detail == "No responde"


async def test_missing_clerk_keys_and_failed_job_degrade_the_state():
    service, _, _ = make(secret="")
    assert (await service.health([JOB])).overall == "error"
    service, _, _ = make()
    failed = JobSnapshot("j", "J", True, 60, None, NOW, False, "OSError")
    health = await service.health([failed])
    assert health.overall == "warning" and health.jobs[0].last_status == "error"
    never = JobSnapshot("j", "J", False, None, None, None, None, None)
    assert (await service.health([never])).jobs[0].last_status == "never"


async def test_missing_upload_folder_is_a_warning():
    service, _, _ = make(upload_dir="definitely/not/here")
    health = await service.health([])
    assert health.overall == "warning"


def test_job_snapshots_without_scheduler_still_lists_the_job():
    (snapshot,) = job_snapshots(None)
    assert snapshot.running is False and snapshot.next_run_at is None


# -- categories -----------------------------------------------------------------------------


@pytest.mark.parametrize(
    "payload",
    [
        {"code": "Bad", "name": "Nombre"},
        {"code": "a", "name": "Nombre"},
        {"code": "ok_code", "name": "  a "},
        {"code": "ok_code", "name": "ab"},
    ],
)
def test_category_validation(payload):
    with pytest.raises(ValidationError):
        CategoryCreate(**payload)


async def test_create_category_audits_and_rejects_duplicates():
    service, repo, audit = make()
    created = await service.create_category(
        CategoryCreate(code="printers", name=" Impresoras "), ACTOR
    )
    assert created.name == "Impresoras" and created.usage == 0
    assert audit.records[0]["action"] == "category.created" and repo.committed == 1
    with pytest.raises(ConflictError):
        await service.create_category(
            CategoryCreate(code="printers", name="Otra"), ACTOR
        )


async def test_update_category_requires_a_value_and_audits_old_and_new():
    service, _repo, audit = make()
    category = await service.create_category(
        CategoryCreate(code="printers", name="Impresoras"), ACTOR
    )
    with pytest.raises(UnprocessableError):
        await service.update_category(category.id, CategoryUpdate(), ACTOR)
    with pytest.raises(UnprocessableError):
        await service.update_category(
            category.id, CategoryUpdate.model_construct(is_active=None), ACTOR
        )
    updated = await service.update_category(
        category.id, CategoryUpdate(name="Impresión", is_active=False), ACTOR
    )
    assert updated.name == "Impresión" and updated.is_active is False
    last = audit.records[-1]
    assert (
        last["old_values"]["name"] == "Impresoras"
        and last["new_values"]["is_active"] is False
    )
    with pytest.raises(NotFoundError):
        await service.update_category(99, CategoryUpdate(name="Nuevo nombre"), ACTOR)


async def test_used_category_cannot_be_deleted_but_unused_can():
    service, repo, audit = make(FakeRepo(usage=3))
    category = await service.create_category(
        CategoryCreate(code="printers", name="Impresoras"), ACTOR
    )
    with pytest.raises(ConflictError, match="3 request"):
        await service.delete_category(category.id, ACTOR)
    repo.usage = 0
    await service.delete_category(category.id, ACTOR)
    assert repo.deleted == [category.id]
    assert audit.records[-1]["action"] == "category.deleted"
    with pytest.raises(NotFoundError):
        await service.delete_category(999, ACTOR)


# -- routes ---------------------------------------------------------------------------------


@pytest.fixture
def client():
    yield TestClient(app)
    app.dependency_overrides.clear()


def as_user(permissions):
    user = SimpleNamespace(
        id=1,
        full_name="Ana",
        roles=[
            SimpleNamespace(
                code="ADMIN",
                is_active=True,
                permissions=perm_objects(*permissions),
            )
        ],
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user


def test_settings_routes_need_the_right_permission(client):
    as_user({"reports.read"})
    assert client.get("/settings/health").status_code == 403
    assert client.get("/settings/categories").status_code == 403
    assert client.post("/settings/categories", json={}).status_code == 403
    assert client.delete("/settings/categories/1").status_code == 403


def test_settings_health_route_returns_the_panel(client):
    service, _, _ = make()
    app.dependency_overrides[providers.get_system_settings_service] = lambda: service
    as_user({"users.manage"})
    response = client.get("/settings/health")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["users"]["total"] == 10 and body["overall"] in {"ok", "warning"}
    assert "secret" not in str(body).lower()


# -- organization (report header) -----------------------------------------------------------


@pytest.mark.parametrize(
    "payload",
    [
        {"company_name": "A"},
        {"company_name": "   "},
        {"company_name": "x" * 151},
        {"company_name": "Mantix", "tax_id": "900.123.456-7"},  # not asked any more
        {"company_name": "Mantix", "legal_name": "Mantix S.A.S."},
        {},
    ],
)
def test_organization_validation(payload):
    with pytest.raises(ValidationError):
        OrganizationUpdate(**payload)


def test_organization_collapses_spaces():
    assert (
        OrganizationUpdate(company_name="  Majesa    Café  ").company_name
        == "Majesa Café"
    )


async def test_organization_defaults_until_it_is_configured_then_audits_changes():
    service, _, audit = make()
    default = await service.organization()
    assert (default.company_name, default.configured) == ("Mantix", False)
    saved = await service.update_organization(
        OrganizationUpdate(company_name="Majesa"), ACTOR
    )
    assert saved.configured and saved.company_name == "Majesa"
    assert audit.records[-1]["action"] == "organization.updated"
    assert audit.records[-1]["old_values"] is None
    await service.update_organization(
        OrganizationUpdate(company_name="Majesa Café"), ACTOR
    )
    assert audit.records[-1]["old_values"] == {"company_name": "Majesa"}
    assert (await service.organization()).company_name == "Majesa Café"


def test_organization_routes_need_users_manage(client):
    as_user({"reports.read"})
    assert client.get("/settings/organization").status_code == 403
    assert (
        client.put(
            "/settings/organization", json={"company_name": "Mantix"}
        ).status_code
        == 403
    )


def test_organization_route_returns_and_saves(client):
    service, _, _ = make()
    app.dependency_overrides[providers.get_system_settings_service] = lambda: service
    as_user({"users.manage"})
    assert client.get("/settings/organization").json()["configured"] is False
    assert (
        client.put("/settings/organization", json={"company_name": "M"}).status_code
        == 422
    )
    ok = client.put("/settings/organization", json={"company_name": "Mantix"})
    assert ok.status_code == 200 and ok.json()["company_name"] == "Mantix"
    legacy = client.put(
        "/settings/organization",
        json={"company_name": "Mantix", "tax_id": "900.123.456-7"},
    )
    assert legacy.status_code == 422
