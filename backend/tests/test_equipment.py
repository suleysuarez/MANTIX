from types import SimpleNamespace

import pytest

from app.core.exceptions import ConflictError, NotFoundError
from app.schemas.equipment import EquipmentCreate, EquipmentUpdate
from app.services.equipment import EquipmentService


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


class FakeEquipmentRepository:
    def __init__(self):
        self.types = [
            SimpleNamespace(id=1, code="LAPTOP", name="Laptop", is_active=True)
        ]
        self.items = []
        self.status_history = []
        self.committed = False

    async def list_equipment(self, **_kwargs):
        return self.items

    async def list_types(self):
        return self.types

    async def get(self, equipment_id):
        return next((item for item in self.items if item.id == equipment_id), None)

    async def get_type(self, equipment_type_id):
        return next(
            (
                item
                for item in self.types
                if item.id == equipment_type_id and item.is_active
            ),
            None,
        )

    async def create(self, payload):
        if any(item.asset_tag == payload.asset_tag for item in self.items):
            from sqlalchemy.exc import IntegrityError

            raise IntegrityError("duplicate", {}, None)
        item = SimpleNamespace(
            id=len(self.items) + 1,
            equipment_type=self.types[0],
            **payload.model_dump(),
        )
        self.items.append(item)
        return item

    async def update(self, equipment, payload):
        for field, value in payload.model_dump(exclude_unset=True).items():
            setattr(equipment, field, value)
        return equipment

    def record_status_change(self, **kwargs):
        self.status_history.append(kwargs)

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


def actor(user_id=1):
    return SimpleNamespace(id=user_id)


def payload(**overrides):
    values = {
        "asset_tag": "LT-001",
        "serial_number": "SN-001",
        "equipment_type_id": 1,
        "brand": "Acme",
        "model": "Pro",
        "status": "in_storage",
    }
    values.update(overrides)
    return EquipmentCreate(**values)


def service_with_fakes():
    return EquipmentService(FakeEquipmentRepository(), FakeAudit())


@pytest.mark.asyncio
async def test_equipment_list_and_create():
    service = service_with_fakes()

    assert await service.list_equipment() == []
    created = await service.create(payload(), actor())

    assert created.asset_tag == "LT-001"
    assert created.equipment_type.name == "Laptop"
    assert service.repository.committed
    # Registration writes an initial status-history row and an audit entry.
    assert service.repository.status_history == [
        {
            "equipment_id": 1,
            "from_status": None,
            "to_status": "in_storage",
            "changed_by_user_id": 1,
            "reason": "equipment registered",
        }
    ]
    assert len(service.audit.records) == 1


@pytest.mark.asyncio
async def test_create_rejects_missing_type():
    service = service_with_fakes()

    with pytest.raises(NotFoundError) as error:
        await service.create(payload(equipment_type_id=99), actor())
    assert error.value.status_code == 404


@pytest.mark.asyncio
async def test_create_rejects_duplicate_asset_tag():
    service = service_with_fakes()
    await service.create(payload(), actor())

    with pytest.raises(ConflictError) as error:
        await service.create(payload(serial_number="SN-002"), actor())
    assert error.value.status_code == 409


@pytest.mark.asyncio
async def test_update_status_change_records_history_and_audit():
    service = service_with_fakes()
    created = await service.create(payload(), actor())
    service.repository.status_history.clear()
    service.audit.records.clear()

    await service.update(created.id, EquipmentUpdate(status="in_repair"), actor(2))

    assert service.repository.status_history == [
        {
            "equipment_id": created.id,
            "from_status": "in_storage",
            "to_status": "in_repair",
            "changed_by_user_id": 2,
            "reason": None,
        }
    ]
    assert len(service.audit.records) == 1


@pytest.mark.asyncio
async def test_update_missing_equipment_raises_not_found():
    service = service_with_fakes()

    with pytest.raises(NotFoundError):
        await service.update(999, EquipmentUpdate(status="in_repair"), actor())


def test_equipment_schema_rejects_invalid_warranty_dates():
    with pytest.raises(ValueError):
        payload(
            warranty_start_date="2025-01-02",
            warranty_end_date="2025-01-01",
        )
