from datetime import UTC, datetime
from types import SimpleNamespace

import pytest

from app.core.authz import AuthContext
from app.core.exceptions import ConflictError, NotFoundError
from app.repositories.base import Page
from app.schemas.technician import TechnicianCreate, TechnicianUpdate
from app.services.technician import TechnicianService


class FakeTechnicianRepository:
    def __init__(self, users=None):
        self.users = (
            users if users is not None else [SimpleNamespace(id=1, is_active=True)]
        )
        self.items: list[SimpleNamespace] = []
        self.committed = False

    async def list(self, *, is_available=None, **_kwargs):
        items = self.items
        if is_available is not None:
            items = [item for item in items if item.is_available == is_available]
        return Page(items=items, total=len(items), page=1, size=20)

    async def get(self, technician_id):
        return next((item for item in self.items if item.id == technician_id), None)

    async def get_active_user(self, user_id):
        return next(
            (user for user in self.users if user.id == user_id and user.is_active),
            None,
        )

    async def get_by_user_id(self, user_id):
        return next((item for item in self.items if item.user_id == user_id), None)

    async def create(self, payload):
        item = SimpleNamespace(
            id=len(self.items) + 1,
            is_available=True,
            is_active=True,
            created_at=datetime(2026, 10, 11, 15, 0, tzinfo=UTC),
            full_name=f"Tech {payload.user_id}",
            email=f"tech{payload.user_id}@example.com",
            employee_code=None,
            **payload.model_dump(),
        )
        self.items.append(item)
        return item

    async def update(self, technician, payload):
        for field, value in payload.model_dump(exclude_unset=True).items():
            setattr(technician, field, value)
        return technician

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


ACTOR = AuthContext.for_roles(SimpleNamespace(id=9), "ADMIN")


def service_with_fakes(users=None):
    return TechnicianService(FakeTechnicianRepository(users=users), FakeAudit())


@pytest.mark.asyncio
async def test_create_technician_profile():
    service = service_with_fakes()

    created = await service.create(
        TechnicianCreate(user_id=1, specialization="Networking"), ACTOR
    )

    assert created.user_id == 1
    assert created.is_available is True
    assert created.full_name == "Tech 1"
    assert created.email == "tech1@example.com"
    assert created.employee_code is None
    assert created.created_at.year == 2026
    assert service.repository.committed


@pytest.mark.asyncio
async def test_create_rejects_missing_user():
    service = service_with_fakes(users=[])

    with pytest.raises(NotFoundError):
        await service.create(TechnicianCreate(user_id=99), ACTOR)


@pytest.mark.asyncio
async def test_create_rejects_duplicate_profile():
    service = service_with_fakes()
    await service.create(TechnicianCreate(user_id=1), ACTOR)

    with pytest.raises(ConflictError):
        await service.create(TechnicianCreate(user_id=1), ACTOR)


@pytest.mark.asyncio
async def test_list_filters_by_availability():
    users = [
        SimpleNamespace(id=1, is_active=True),
        SimpleNamespace(id=2, is_active=True),
    ]
    service = service_with_fakes(users=users)
    await service.create(TechnicianCreate(user_id=1), ACTOR)
    second = await service.create(TechnicianCreate(user_id=2), ACTOR)
    await service.update(second.id, TechnicianUpdate(is_available=False), ACTOR)

    available = await service.list(is_available=True)

    assert [item.user_id for item in available.items] == [1]
    assert available.total == 1


@pytest.mark.asyncio
async def test_technician_writes_are_audited_with_before_and_after_values():
    service = service_with_fakes()
    created = await service.create(TechnicianCreate(user_id=1), ACTOR)
    await service.update(created.id, TechnicianUpdate(is_available=False), ACTOR)

    create_record, update_record = service.audit.records
    assert create_record["action"] == "technician.created"
    assert create_record["user_id"] == 9
    assert update_record["action"] == "technician.updated"
    assert update_record["old_values"] == {"is_available": True}
    assert update_record["new_values"] == {"is_available": False}
