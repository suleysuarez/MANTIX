import io
from types import SimpleNamespace

import pytest
from fastapi import UploadFile
from fastapi.testclient import TestClient

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.authz import AuthContext
from app.core.exceptions import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    PayloadTooLargeError,
    UnsupportedMediaTypeError,
)
from app.core.storage import LocalFileStorage
from app.main import app
from app.schemas.attachment import AttachmentResponse
from app.services.attachment import (
    MAX_ATTACHMENTS_PER_PARENT,
    AttachmentService,
    DownloadedFile,
)
from tests.support import expand, perm_objects

PDF = b"%PDF-1.7 fake"
PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 20


def upload(content=PDF, name="report.pdf"):
    return UploadFile(file=io.BytesIO(content), filename=name)


def actor(user_id=1, *roles, permissions=()):
    from app.core.permissions import effective_for_system_roles

    return AuthContext(
        user=SimpleNamespace(id=user_id),
        roles=frozenset(roles),
        permissions=expand(*permissions) | effective_for_system_roles(*roles),
    )


# -- local storage ---------------------------------------------------------------


async def test_local_storage_round_trip_and_delete(tmp_path):
    storage = LocalFileStorage(tmp_path)
    await storage.save("requests/1/a.pdf", b"data")
    assert await storage.read("requests/1/a.pdf") == b"data"
    await storage.delete("requests/1/a.pdf")
    await storage.delete("requests/1/a.pdf")  # idempotent
    with pytest.raises(NotFoundError):
        await storage.read("requests/1/a.pdf")


@pytest.mark.parametrize(
    "key", ["../outside.txt", "a/../../outside.txt", "/etc/passwd", ""]
)
async def test_local_storage_refuses_keys_that_escape_the_base_dir(tmp_path, key):
    storage = LocalFileStorage(tmp_path / "base")
    with pytest.raises(ValueError):
        await storage.save(key, b"x")
    assert not (tmp_path / "outside.txt").exists()


# -- service (fakes) -----------------------------------------------------------------


class FakeStorage:
    def __init__(self):
        self.files = {}

    async def save(self, key, content):
        self.files[key] = content

    async def read(self, key):
        return self.files[key]

    async def delete(self, key):
        self.files.pop(key, None)


class FakeAttachmentRepository:
    def __init__(self, fail_commit=False):
        self.items = []
        self.fail_commit = fail_commit
        self.rolled_back = False

    async def list_for_parent(self, *, request_id=None, equipment_id=None, **_):
        return [
            i
            for i in self.items
            if (request_id is not None and i.request_id == request_id)
            or (equipment_id is not None and i.equipment_id == equipment_id)
        ]

    async def get(self, attachment_id):
        return next((i for i in self.items if i.id == attachment_id), None)

    async def add_and_flush(self, entity):
        entity.id = len(self.items) + 1
        entity.created_at = "2026-10-11T12:00:00Z"
        self.items.append(entity)
        return entity

    async def delete(self, entity):
        self.items.remove(entity)

    async def commit(self):
        if self.fail_commit:
            raise RuntimeError("db down")

    async def rollback(self):
        self.rolled_back = True


class FakeMaintenance:
    """Stands in for MaintenanceService.ensure_can_view."""

    def __init__(self, visible_to=()):
        self.visible_to = set(visible_to)

    async def ensure_can_view(self, request_id, actor):
        if request_id != 1:
            raise NotFoundError("maintenance request not found")
        if actor.id not in self.visible_to and not actor.has_permission(
            "tickets:ver_todos"
        ):
            raise ForbiddenError("not authorized to view this maintenance request")


class FakeEquipmentRepository:
    async def get(self, equipment_id):
        return SimpleNamespace(id=equipment_id) if equipment_id == 5 else None


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


def make_service(*, visible_to=(10,), fail_commit=False, max_bytes=1024):
    repository = FakeAttachmentRepository(fail_commit)
    service = AttachmentService(
        repository,
        FakeStorage(),
        FakeMaintenance(visible_to),
        FakeEquipmentRepository(),
        FakeAudit(),
        max_bytes=max_bytes,
    )
    return service, repository


async def test_requester_can_attach_to_their_ticket_and_file_is_stored_safely():
    service, repo = make_service()
    result = await service.add_to_request(
        1, upload(PDF, "../../evil name?.pdf"), actor(10)
    )
    assert result.file_name == "evil name.pdf"
    assert result.mime_type == "application/pdf" and result.file_size == len(PDF)
    stored_key = repo.items[0].file_path
    assert stored_key.startswith("requests/1/") and stored_key.endswith(".pdf")
    assert "evil" not in stored_key  # server-generated key, not the client name
    assert service.storage.files[stored_key] == PDF
    assert service.audit.records[0]["action"] == "attachment.uploaded"


async def test_strangers_cannot_attach_or_list_and_missing_tickets_are_404():
    service, _ = make_service()
    with pytest.raises(ForbiddenError):
        await service.add_to_request(1, upload(), actor(99))
    with pytest.raises(ForbiddenError):
        await service.list_for_request(1, actor(99))
    with pytest.raises(NotFoundError):
        await service.add_to_request(2, upload(), actor(10))
    await service.add_to_request(1, upload(), actor(99, "SUPERVISOR"))  # elevated


@pytest.mark.parametrize(
    ("content", "name", "error"),
    [
        (b"MZ" + b"0" * 10, "tool.exe", UnsupportedMediaTypeError),
        (
            b"<html>",
            "page.pdf",
            UnsupportedMediaTypeError,
        ),  # extension/content mismatch
        (b"x" * 2000, "big.txt", PayloadTooLargeError),
    ],
)
async def test_invalid_files_are_rejected_before_anything_is_stored(
    content, name, error
):
    service, repo = make_service()
    with pytest.raises(error):
        await service.add_to_request(1, upload(content, name), actor(10))
    assert not repo.items and not service.storage.files


async def test_attachment_count_per_ticket_is_capped():
    service, repo = make_service()
    for _ in range(MAX_ATTACHMENTS_PER_PARENT):
        await service.add_to_request(1, upload(), actor(10))
    with pytest.raises(ConflictError):
        await service.add_to_request(1, upload(), actor(10))
    assert len(repo.items) == MAX_ATTACHMENTS_PER_PARENT


async def test_stored_file_is_removed_when_the_commit_fails():
    service, repo = make_service(fail_commit=True)
    with pytest.raises(RuntimeError):
        await service.add_to_request(1, upload(), actor(10))
    assert repo.rolled_back
    assert service.storage.files == {}


async def test_equipment_attachments_need_equipment_manage():
    service, _ = make_service()
    with pytest.raises(ForbiddenError):
        await service.add_to_equipment(5, upload(PNG, "photo.png"), actor(10))
    manager = actor(2, permissions={"equipment.manage"})
    created = await service.add_to_equipment(5, upload(PNG, "photo.png"), manager)
    assert created.equipment_id == 5 and created.mime_type == "image/png"
    with pytest.raises(NotFoundError):
        await service.add_to_equipment(6, upload(PNG, "photo.png"), manager)
    assert [a.id for a in await service.list_for_equipment(5)] == [created.id]


async def test_download_follows_parent_visibility():
    service, _ = make_service()
    created = await service.add_to_request(1, upload(), actor(10))
    file = await service.download(created.id, actor(10))
    assert file == DownloadedFile(PDF, "report.pdf", "application/pdf")
    with pytest.raises(ForbiddenError):
        await service.download(created.id, actor(99))
    with pytest.raises(NotFoundError):
        await service.download(404, actor(10))


async def test_only_uploader_or_supervisor_can_delete():
    service, repo = make_service(visible_to=(10, 11))
    created = await service.add_to_request(1, upload(), actor(10))
    key = repo.items[0].file_path
    with pytest.raises(ForbiddenError):
        await service.delete(created.id, actor(11))  # can view, did not upload
    assert service.storage.files
    await service.delete(created.id, actor(10))
    assert not repo.items and key not in service.storage.files
    assert service.audit.records[-1]["action"] == "attachment.deleted"

    again = await service.add_to_request(1, upload(), actor(10))
    await service.delete(again.id, actor(50, "SUPERVISOR"))
    assert not repo.items


# -- HTTP ---------------------------------------------------------------------------------


class StubAttachmentService:
    def __init__(self):
        self.calls = []

    async def add_to_request(self, request_id, file, actor):
        self.calls.append(("add", request_id, file.filename, await file.read()))
        return AttachmentResponse(
            id=1,
            file_name="r.pdf",
            mime_type="application/pdf",
            file_size=3,
            equipment_id=None,
            request_id=request_id,
            uploaded_by_user_id=actor.id,
            created_at="2026-10-11T12:00:00Z",
        )

    async def download(self, attachment_id, actor):
        return DownloadedFile(b"%PDF-x", "infórme final.pdf", "application/pdf")

    async def delete(self, attachment_id, actor):
        self.calls.append(("delete", attachment_id))


@pytest.fixture
def client():
    stub = StubAttachmentService()
    user = SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                code="EMPLOYEE",
                is_active=True,
                permissions=perm_objects("attachments.write", "maintenance.read"),
            )
        ],
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user
    app.dependency_overrides[providers.get_attachment_service] = lambda: stub
    with TestClient(app, raise_server_exceptions=False) as test_client:
        test_client.stub = stub
        yield test_client
    app.dependency_overrides.clear()


def test_upload_endpoint_returns_201_with_metadata(client):
    response = client.post(
        "/maintenance/requests/9/attachments",
        files={"file": ("r.pdf", PDF, "application/pdf")},
    )
    assert response.status_code == 201
    assert response.json()["request_id"] == 9
    assert client.stub.calls[0] == ("add", 9, "r.pdf", PDF)


def test_upload_without_a_file_is_a_validation_error(client):
    response = client.post("/maintenance/requests/9/attachments")
    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"


def test_download_sets_attachment_and_nosniff_headers(client):
    response = client.get("/attachments/3/download")
    assert response.status_code == 200
    assert response.content == b"%PDF-x"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["content-disposition"].startswith(
        "attachment; filename*=UTF-8''inf%C3%B3rme%20final.pdf"
    )
    assert response.headers["cache-control"] == "private, no-store"


def test_delete_returns_204(client):
    response = client.delete("/attachments/3")
    assert response.status_code == 204
    assert client.stub.calls == [("delete", 3)]
