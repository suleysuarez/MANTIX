from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.schemas.equipment import EquipmentCreate
from app.services.equipment import EquipmentService


class FakeEquipmentRepository:
    def __init__(self):
        self.types = [
            SimpleNamespace(id=1, code="LAPTOP", name="Laptop", is_active=True)
        ]
        self.items = []
        self.committed = False

    async def list_equipment(self):
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

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


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


@pytest.mark.asyncio
async def test_equipment_list_and_create():
    repository = FakeEquipmentRepository()
    service = EquipmentService(object())
    service.repository = repository

    assert await service.list_equipment() == []
    created = await service.create(payload())

    assert created.asset_tag == "LT-001"
    assert created.equipment_type.name == "Laptop"
    assert repository.committed


@pytest.mark.asyncio
async def test_create_rejects_missing_type():
    repository = FakeEquipmentRepository()
    service = EquipmentService(object())
    service.repository = repository

    with pytest.raises(HTTPException) as error:
        await service.create(payload(equipment_type_id=99))
    assert error.value.status_code == 404


@pytest.mark.asyncio
async def test_create_rejects_duplicate_asset_tag():
    repository = FakeEquipmentRepository()
    service = EquipmentService(object())
    service.repository = repository
    await service.create(payload())

    with pytest.raises(HTTPException) as error:
        await service.create(payload(serial_number="SN-002"))
    assert error.value.status_code == 409


def test_equipment_schema_rejects_invalid_warranty_dates():
    with pytest.raises(ValueError):
        payload(
            warranty_start_date="2025-01-02",
            warranty_end_date="2025-01-01",
        )
