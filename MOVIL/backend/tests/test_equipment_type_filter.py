"""`GET /equipment?equipment_type_id=1&equipment_type_id=2`: several categories at once."""

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_authenticated_user
from app.api.filters import MAX_FILTER_VALUES
from app.api.providers import get_equipment_service
from app.main import app
from app.models.equipment import Equipment, EquipmentType
from app.repositories.base import Page
from app.repositories.equipment import EquipmentRepository
from app.services.equipment import EquipmentService


class FakeRepository:
    def __init__(self):
        self.calls: list[dict] = []

    async def list_equipment(self, **kwargs):
        self.calls.append(kwargs)
        params = kwargs["params"]
        return Page(items=[], total=0, page=params.page, size=params.size)

    async def current_context(self, ids):
        return {}


@pytest.fixture
def client():
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def serve(repository: FakeRepository) -> None:
    permissions = [
        SimpleNamespace(code="equipos:ver", name="equipos:ver", is_active=True)
    ]
    user = SimpleNamespace(
        id=1, roles=[SimpleNamespace(code="X", is_active=True, permissions=permissions)]
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user
    app.dependency_overrides[get_equipment_service] = lambda: EquipmentService(
        repository, audit=SimpleNamespace(record=lambda **_: None)
    )


# -- route --------------------------------------------------------------------------------------


def test_no_category_means_no_filter(client):
    repository = FakeRepository()
    serve(repository)
    assert client.get("/equipment").status_code == 200
    assert repository.calls[0]["equipment_type_ids"] is None


def test_a_single_category_keeps_working_as_before(client):
    repository = FakeRepository()
    serve(repository)
    assert client.get("/equipment?equipment_type_id=2").status_code == 200
    assert repository.calls[0]["equipment_type_ids"] == [2]


def test_a_repeated_parameter_selects_several_categories(client):
    repository = FakeRepository()
    serve(repository)
    response = client.get(
        "/equipment?equipment_type_id=1&equipment_type_id=2&equipment_type_id=5&status=assigned"
    )

    assert response.status_code == 200
    assert repository.calls[0]["equipment_type_ids"] == [1, 2, 5]
    assert repository.calls[0]["status"] == "assigned"
    assert response.headers["X-Total-Count"] == "0"


def test_the_limit_is_twenty_values(client):
    repository = FakeRepository()
    serve(repository)
    at_limit = "&".join(
        f"equipment_type_id={i}" for i in range(1, MAX_FILTER_VALUES + 1)
    )
    over_limit = at_limit + f"&equipment_type_id={MAX_FILTER_VALUES + 1}"

    assert client.get(f"/equipment?{at_limit}").status_code == 200
    assert len(repository.calls[0]["equipment_type_ids"]) == MAX_FILTER_VALUES

    response = client.get(f"/equipment?{over_limit}")
    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "validation_error"
    assert any(error["field"].endswith("equipment_type_id") for error in body["errors"])
    assert len(repository.calls) == 1, (
        "the request over the limit never reaches the service"
    )


def test_a_value_that_is_not_a_number_is_a_422_that_names_the_field(client):
    repository = FakeRepository()
    serve(repository)
    response = client.get("/equipment?equipment_type_id=1&equipment_type_id=laptop")

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert repository.calls == []


# -- repository (real PostgreSQL) ---------------------------------------------------------------


async def _types_and_items(session):
    kinds = {}
    for code in ("LAPTOP", "PRINTER", "PHONE"):
        kind = EquipmentType(code=code, name=code.title(), is_active=True)
        session.add(kind)
        kinds[code] = kind
    await session.flush()
    for tag, code, status in (
        ("L-1", "LAPTOP", "assigned"),
        ("L-2", "LAPTOP", "in_storage"),
        ("P-1", "PRINTER", "assigned"),
        ("M-1", "PHONE", "assigned"),
    ):
        session.add(
            Equipment(
                asset_tag=tag,
                equipment_type_id=kinds[code].id,
                brand="X",
                model="Y",
                status=status,
            )
        )
    await session.flush()
    return kinds


def tags(page) -> list[str]:
    return sorted(item.asset_tag for item in page.items)


async def test_several_categories_return_the_union(db_session):
    repo = EquipmentRepository(db_session)
    kinds = await _types_and_items(db_session)

    both = await repo.list_equipment(
        equipment_type_ids=[kinds["LAPTOP"].id, kinds["PRINTER"].id]
    )
    assert tags(both) == ["L-1", "L-2", "P-1"]
    assert both.total == 3

    one = await repo.list_equipment(equipment_type_ids=[kinds["PHONE"].id])
    assert tags(one) == ["M-1"]


async def test_no_categories_or_an_empty_list_means_everything(db_session):
    repo = EquipmentRepository(db_session)
    await _types_and_items(db_session)

    assert (await repo.list_equipment()).total == 4
    assert (await repo.list_equipment(equipment_type_ids=[])).total == 4
    assert (await repo.list_equipment(equipment_type_ids=None)).total == 4


async def test_the_categories_combine_with_the_other_filters(db_session):
    repo = EquipmentRepository(db_session)
    kinds = await _types_and_items(db_session)

    page = await repo.list_equipment(
        equipment_type_ids=[kinds["LAPTOP"].id, kinds["PRINTER"].id], status="assigned"
    )
    assert tags(page) == ["L-1", "P-1"]


async def test_an_unknown_category_matches_nothing_and_the_single_parameter_still_works(
    db_session,
):
    repo = EquipmentRepository(db_session)
    kinds = await _types_and_items(db_session)

    assert (await repo.list_equipment(equipment_type_ids=[9999])).total == 0
    legacy = await repo.list_equipment(equipment_type_id=kinds["PRINTER"].id)
    assert tags(legacy) == ["P-1"]
