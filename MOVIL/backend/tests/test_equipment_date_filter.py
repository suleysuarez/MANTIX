"""`GET /equipment?date_from=&date_to=`: filter the catalog by registration date."""

from datetime import UTC, datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_authenticated_user
from app.api.providers import get_equipment_service
from app.core.exceptions import UnprocessableError
from app.main import app
from app.models.equipment import Equipment, EquipmentType
from app.repositories.base import Page
from app.repositories.equipment import EquipmentRepository
from app.services.equipment import EquipmentService

NOON = datetime(2026, 10, 15, 12, 0, tzinfo=UTC)


class FakeRepository:
    def __init__(self):
        self.calls: list[dict] = []

    async def list_equipment(self, **kwargs):
        self.calls.append(kwargs)
        params = kwargs.get("params")
        return Page(
            items=[],
            total=0,
            page=params.page if params else 1,
            size=params.size if params else 20,
        )

    async def current_context(self, ids):
        return {}


def service(repository: FakeRepository) -> EquipmentService:
    return EquipmentService(repository, audit=SimpleNamespace(record=lambda **_: None))


# -- service ------------------------------------------------------------------------------------


async def test_a_range_with_from_after_to_is_rejected_with_a_specific_code():
    repository = FakeRepository()
    with pytest.raises(UnprocessableError) as error:
        await service(repository).list_equipment(
            date_from=NOON + timedelta(days=1), date_to=NOON
        )

    assert error.value.code == "invalid_date_range"
    assert repository.calls == [], "nothing reaches the database"


async def test_the_same_instant_on_both_ends_is_a_valid_range():
    repository = FakeRepository()
    await service(repository).list_equipment(date_from=NOON, date_to=NOON)
    assert repository.calls[0]["date_from"] == NOON
    assert repository.calls[0]["date_to"] == NOON


async def test_one_open_end_is_fine_and_no_dates_means_no_filter():
    repository = FakeRepository()
    await service(repository).list_equipment(date_from=NOON)
    await service(repository).list_equipment(date_to=NOON)
    await service(repository).list_equipment()

    assert (repository.calls[0]["date_from"], repository.calls[0]["date_to"]) == (
        NOON,
        None,
    )
    assert (repository.calls[1]["date_from"], repository.calls[1]["date_to"]) == (
        None,
        NOON,
    )
    assert (repository.calls[2]["date_from"], repository.calls[2]["date_to"]) == (
        None,
        None,
    )


async def test_a_date_time_without_a_zone_is_read_as_utc():
    repository = FakeRepository()
    await service(repository).list_equipment(
        date_from=datetime(2026, 10, 1), date_to=datetime(2026, 10, 2, 23, 59)
    )

    assert repository.calls[0]["date_from"] == datetime(2026, 10, 1, tzinfo=UTC)
    assert repository.calls[0]["date_to"] == datetime(2026, 10, 2, 23, 59, tzinfo=UTC)


async def test_the_range_is_compared_after_converting_zones():
    repository = FakeRepository()
    plus_five = timezone(timedelta(hours=5))
    # 2026-10-15 03:00 at +05:00 is 2026-10-14 22:00 UTC: before the UTC end below.
    await service(repository).list_equipment(
        date_from=datetime(2026, 10, 15, 3, 0, tzinfo=plus_five),
        date_to=datetime(2026, 10, 14, 23, 0, tzinfo=UTC),
    )
    assert len(repository.calls) == 1


# -- route --------------------------------------------------------------------------------------


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
    app.dependency_overrides[get_equipment_service] = lambda: service(repository)


def test_from_after_to_is_a_422_with_the_stable_code_and_the_error_body(client):
    serve(FakeRepository())
    response = client.get(
        "/equipment?date_from=2026-10-20T00:00:00Z&date_to=2026-10-01T00:00:00Z"
    )

    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "invalid_date_range"
    assert set(body) >= {"detail", "code", "errors", "request_id"}


def test_an_invalid_format_is_a_422_that_names_the_field(client):
    repository = FakeRepository()
    serve(repository)
    response = client.get("/equipment?date_from=ayer")

    assert response.status_code == 422
    body = response.json()
    assert body["code"] == "validation_error"
    assert any(error["field"].endswith("date_from") for error in body["errors"])
    assert repository.calls == []


def test_a_plain_date_and_a_date_time_with_zone_are_accepted(client):
    repository = FakeRepository()
    serve(repository)

    assert (
        client.get(
            "/equipment?date_from=2026-10-01&date_to=2026-10-31T23:59:59Z"
        ).status_code
        == 200
    )
    assert repository.calls[0]["date_from"] == datetime(2026, 10, 1, tzinfo=UTC)
    assert repository.calls[0]["date_to"] == datetime(
        2026, 10, 31, 23, 59, 59, tzinfo=UTC
    )


def test_the_other_filters_and_the_pagination_headers_keep_working(client):
    repository = FakeRepository()
    serve(repository)
    response = client.get(
        "/equipment?status=assigned&search=dell&date_from=2026-10-01&size=5"
    )

    assert response.status_code == 200
    assert response.headers["X-Total-Count"] == "0"
    assert response.headers["X-Page-Size"] == "5"
    assert repository.calls[0]["status"] == "assigned"
    assert repository.calls[0]["search"] == "dell"


# -- repository (real PostgreSQL) ---------------------------------------------------------------


async def _registered(
    session, tag: str, when: datetime, *, status: str = "active"
) -> Equipment:
    kind = EquipmentType(code=f"T-{tag}", name=f"Type {tag}", is_active=True)
    session.add(kind)
    await session.flush()
    item = Equipment(
        asset_tag=tag,
        equipment_type_id=kind.id,
        brand="Dell",
        model="X1",
        status=status,
        created_at=when,
    )
    session.add(item)
    await session.flush()
    return item


async def test_the_repository_filters_by_registration_date_with_both_ends_included(
    db_session,
):
    repo = EquipmentRepository(db_session)
    for tag, days in (
        ("OLD", -30),
        ("EDGE-FROM", -10),
        ("MID", -5),
        ("EDGE-TO", 0),
        ("NEW", 5),
    ):
        await _registered(db_session, tag, NOON + timedelta(days=days))

    inside = await repo.list_equipment(
        date_from=NOON - timedelta(days=10), date_to=NOON
    )
    assert sorted(e.asset_tag for e in inside.items) == ["EDGE-FROM", "EDGE-TO", "MID"]
    assert inside.total == 3

    only_from = await repo.list_equipment(date_from=NOON)
    assert sorted(e.asset_tag for e in only_from.items) == ["EDGE-TO", "NEW"]

    only_to = await repo.list_equipment(date_to=NOON - timedelta(days=10))
    assert sorted(e.asset_tag for e in only_to.items) == ["EDGE-FROM", "OLD"]

    everything = await repo.list_equipment()
    assert everything.total == 5


async def test_the_date_filter_combines_with_the_other_filters(db_session):
    repo = EquipmentRepository(db_session)
    await _registered(db_session, "A-ASSIGNED", NOON, status="assigned")
    await _registered(db_session, "A-ACTIVE", NOON, status="active")
    await _registered(db_session, "A-OLD", NOON - timedelta(days=60), status="assigned")

    page = await repo.list_equipment(
        status="assigned", date_from=NOON - timedelta(days=1)
    )
    assert [e.asset_tag for e in page.items] == ["A-ASSIGNED"]
