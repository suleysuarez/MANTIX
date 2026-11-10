"""`GET /equipment/{id}/maintenance-records`: the maintenance history of one item."""

from datetime import UTC, datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_authenticated_user
from app.api.providers import get_equipment_service
from app.core.exceptions import NotFoundError
from app.core.pagination import PageParams
from app.main import app
from app.models.auth import User
from app.models.equipment import Equipment, EquipmentType
from app.models.maintenance import MaintenanceRecord
from app.models.technician import Technician
from app.repositories.base import Page
from app.repositories.equipment import EquipmentRepository
from app.schemas.maintenance import MaintenanceRecordResponse
from app.services.equipment import EquipmentService

NOW = datetime(2026, 11, 1, 10, 0, tzinfo=UTC)


def record(record_id: int, *, equipment_id: int = 7, days: int = 0) -> SimpleNamespace:
    return SimpleNamespace(
        id=record_id,
        equipment_id=equipment_id,
        request_id=None,
        technician_id=3,
        work_type="corrective",
        started_at=NOW - timedelta(days=days),
        completed_at=None,
        diagnosis="Pantalla negra",
        actions_taken="Cambio de cable",
        result="resolved",
        labor_cost=Decimal("40.00"),
        parts_cost=Decimal("15.50"),
        total_cost=Decimal("55.50"),
        notes=None,
    )


class FakeRepository:
    def __init__(self, items: list[SimpleNamespace], *, known: bool = True):
        self.items = items
        self.known = known
        self.params: PageParams | None = None

    async def get(self, equipment_id):
        return SimpleNamespace(id=equipment_id) if self.known else None

    async def list_maintenance_records(self, equipment_id, params):
        self.params = params
        return Page(
            items=self.items, total=len(self.items), page=params.page, size=params.size
        )


def service(repository: FakeRepository) -> EquipmentService:
    return EquipmentService(repository, audit=SimpleNamespace(record=lambda **_: None))


# -- service ------------------------------------------------------------------------------------


async def test_the_service_maps_records_and_keeps_the_pagination():
    repository = FakeRepository([record(1), record(2, days=3)])
    page = await service(repository).list_maintenance_records(
        7, PageParams(page=1, size=20)
    )

    assert [item.id for item in page.items] == [1, 2]
    assert all(isinstance(item, MaintenanceRecordResponse) for item in page.items)
    assert page.total == 2


async def test_an_unknown_item_is_a_404_with_a_specific_code():
    with pytest.raises(NotFoundError) as error:
        await service(FakeRepository([], known=False)).list_maintenance_records(99)
    assert error.value.code == "equipment_not_found"


# -- route: who may read it -------------------------------------------------------------------


@pytest.fixture
def client():
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def person(*codes: str) -> SimpleNamespace:
    permissions = [SimpleNamespace(code=c, name=c, is_active=True) for c in codes]
    return SimpleNamespace(
        id=42,
        roles=[SimpleNamespace(code="X", is_active=True, permissions=permissions)],
    )


def serve(repository: FakeRepository, *codes: str) -> None:
    app.dependency_overrides[get_authenticated_user] = lambda: person(*codes)
    app.dependency_overrides[get_equipment_service] = lambda: service(repository)


def test_without_a_session_it_is_a_401(client):
    assert client.get("/equipment/7/maintenance-records").status_code == 401


def test_seeing_the_catalog_is_not_enough_it_is_a_403(client):
    serve(FakeRepository([record(1)]), "equipos:ver", "tickets:ver")
    response = client.get("/equipment/7/maintenance-records")

    assert response.status_code == 403
    assert response.json()["code"] == "forbidden"


def test_whoever_sees_every_ticket_gets_the_page_with_its_headers(client):
    repository = FakeRepository([record(1), record(2, days=3)])
    serve(repository, "tickets:ver_todos")
    response = client.get("/equipment/7/maintenance-records?page=1&size=5")

    assert response.status_code == 200
    assert [item["id"] for item in response.json()] == [1, 2]
    assert response.headers["X-Total-Count"] == "2"
    assert response.headers["X-Page"] == "1"
    assert response.headers["X-Page-Size"] == "5"
    assert response.headers["X-Total-Pages"] == "1"
    assert repository.params is not None and repository.params.size == 5


def test_costs_are_hidden_unless_the_person_also_edits_equipment(client):
    serve(FakeRepository([record(1)]), "tickets:ver_todos")
    hidden = client.get("/equipment/7/maintenance-records").json()[0]
    assert hidden["labor_cost"] is None
    assert hidden["parts_cost"] is None
    assert hidden["total_cost"] is None
    assert hidden["diagnosis"] == "Pantalla negra"

    serve(FakeRepository([record(1)]), "tickets:ver_todos", "equipos:editar")
    shown = client.get("/equipment/7/maintenance-records").json()[0]
    assert shown["labor_cost"] == "40.00"
    assert shown["total_cost"] == "55.50"


def test_an_unknown_item_is_a_404_with_the_error_body(client):
    serve(FakeRepository([], known=False), "tickets:ver_todos")
    response = client.get("/equipment/99/maintenance-records")

    assert response.status_code == 404
    body = response.json()
    assert body["code"] == "equipment_not_found"
    assert set(body) >= {"detail", "code", "errors", "request_id"}


# -- repository (real PostgreSQL) ---------------------------------------------------------------


async def _item(session, tag: str) -> Equipment:
    kind = EquipmentType(code=f"T-{tag}", name=f"Type {tag}", is_active=True)
    session.add(kind)
    await session.flush()
    item = Equipment(
        asset_tag=tag,
        equipment_type_id=kind.id,
        brand="Dell",
        model="X1",
        status="active",
    )
    session.add(item)
    await session.flush()
    return item


async def _technician(session) -> Technician:
    user = User(clerk_user_id="t1", email="t@x.co", full_name="Tec", is_active=True)
    session.add(user)
    await session.flush()
    technician = Technician(user_id=user.id, is_available=True)
    session.add(technician)
    await session.flush()
    return technician


def _row(
    equipment: Equipment, technician: Technician, *, days: int
) -> MaintenanceRecord:
    return MaintenanceRecord(
        equipment_id=equipment.id,
        technician_id=technician.id,
        work_type="corrective",
        started_at=NOW - timedelta(days=days),
        diagnosis=f"d{days}",
        actions_taken="a",
        result="resolved",
    )


async def test_the_repository_lists_only_that_item_newest_work_first(db_session):
    repo = EquipmentRepository(db_session)
    mine, other = await _item(db_session, "A-1"), await _item(db_session, "A-2")
    technician = await _technician(db_session)
    db_session.add_all(
        [
            _row(mine, technician, days=10),
            _row(mine, technician, days=1),
            _row(mine, technician, days=5),
            _row(other, technician, days=0),
        ]
    )
    await db_session.flush()

    page = await repo.list_maintenance_records(mine.id)

    assert page.total == 3
    assert [r.diagnosis for r in page.items] == ["d1", "d5", "d10"]


async def test_the_repository_paginates_and_honors_the_sort_field(db_session):
    repo = EquipmentRepository(db_session)
    item = await _item(db_session, "B-1")
    technician = await _technician(db_session)
    db_session.add_all([_row(item, technician, days=d) for d in (1, 2, 3, 4, 5)])
    await db_session.flush()

    second = await repo.list_maintenance_records(item.id, PageParams(page=2, size=2))
    assert second.total == 5
    assert second.pages == 3
    assert [r.diagnosis for r in second.items] == ["d3", "d4"]

    oldest_first = await repo.list_maintenance_records(
        item.id, PageParams(page=1, size=2, sort="started_at")
    )
    assert [r.diagnosis for r in oldest_first.items] == ["d5", "d4"]

    ignored = await repo.list_maintenance_records(
        item.id, PageParams(page=1, size=1, sort="-drop_table")
    )
    assert [r.diagnosis for r in ignored.items] == ["d1"], (
        "an unknown sort field falls back to the default"
    )


async def test_an_item_without_records_gives_an_empty_page(db_session):
    repo = EquipmentRepository(db_session)
    item = await _item(db_session, "C-1")
    page = await repo.list_maintenance_records(item.id)
    assert page.total == 0
    assert page.items == []
