"""`GET /maintenance/requests`: several statuses, priorities and items in one filter."""

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_authenticated_user
from app.api.providers import get_maintenance_service
from app.core.exceptions import UnprocessableError
from app.core.filters import MAX_FILTER_VALUES, split_filter_list
from app.core.scope import DataScope
from app.main import app
from app.models.auth import User
from app.models.equipment import Equipment, EquipmentType
from app.models.maintenance import MaintenanceRequest
from app.models.priority import Priority
from app.repositories.base import Page
from app.repositories.maintenance import MaintenanceRepository
from app.services.maintenance import MaintenanceService

# -- the splitting helper -----------------------------------------------------------------------


def test_split_filter_list_trims_drops_blanks_and_repeats():
    assert split_filter_list(" high, critical ,,high ", "priority") == [
        "high",
        "critical",
    ]
    assert split_filter_list("low", "priority") == ["low"]
    assert split_filter_list("", "priority") == []
    assert split_filter_list(None, "priority") == []


def test_the_limit_counts_distinct_values_and_has_a_specific_code():
    ok = ",".join(f"p{i}" for i in range(MAX_FILTER_VALUES))
    assert len(split_filter_list(ok, "priority")) == MAX_FILTER_VALUES
    assert len(split_filter_list(ok + ",p0,p1", "priority")) == MAX_FILTER_VALUES, (
        "repeats do not count"
    )

    with pytest.raises(UnprocessableError) as error:
        split_filter_list(ok + ",extra", "priority")
    assert error.value.code == "filter_too_many_values"
    assert "priority" in error.value.detail


# -- service and route (fake repository) --------------------------------------------------------


class FakeRepository:
    def __init__(self):
        self.calls: list[dict] = []

    async def scope_for(self, actor):
        return DataScope.everything()

    async def list_requests(self, **kwargs):
        self.calls.append(kwargs)
        params = kwargs["params"]
        return Page(items=[], total=0, page=params.page, size=params.size)


def real_service(repository: FakeRepository) -> MaintenanceService:
    return MaintenanceService(
        repository,
        SimpleNamespace(record=lambda **_: None),
        SimpleNamespace(notify=lambda **_: None),
    )


@pytest.fixture
def client():
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def serve(repository: FakeRepository) -> None:
    permissions = [
        SimpleNamespace(code="tickets:ver", name="tickets:ver", is_active=True)
    ]
    user = SimpleNamespace(
        id=1, roles=[SimpleNamespace(code="X", is_active=True, permissions=permissions)]
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user
    app.dependency_overrides[get_maintenance_service] = lambda: real_service(repository)


def test_one_priority_and_one_item_keep_working_as_before(client):
    repository = FakeRepository()
    serve(repository)
    assert (
        client.get(
            "/maintenance/requests?priority=high&equipment_id=12&status=submitted"
        ).status_code
        == 200
    )

    call = repository.calls[0]
    assert call["priorities"] == ["high"]
    assert call["equipment_ids"] == [12]
    assert call["status"] == "submitted"


def test_several_priorities_and_items_reach_the_repository_as_lists(client):
    repository = FakeRepository()
    serve(repository)
    response = client.get(
        "/maintenance/requests?priority=critical,high&equipment_id=1&equipment_id=2&status=submitted,triaged"
    )

    assert response.status_code == 200
    call = repository.calls[0]
    assert call["priorities"] == ["critical", "high"]
    assert call["equipment_ids"] == [1, 2]
    assert call["status"] == "submitted,triaged"
    assert response.headers["X-Total-Count"] == "0"


def test_no_filters_means_no_filters(client):
    repository = FakeRepository()
    serve(repository)
    assert client.get("/maintenance/requests").status_code == 200

    call = repository.calls[0]
    assert call["priorities"] == []
    assert call["equipment_ids"] is None


def test_too_many_priorities_or_statuses_is_a_422_with_the_new_code(client):
    repository = FakeRepository()
    serve(repository)
    many = ",".join(f"p{i}" for i in range(MAX_FILTER_VALUES + 1))

    for field in ("priority", "status"):
        response = client.get(f"/maintenance/requests?{field}={many}")
        assert response.status_code == 422, field
        body = response.json()
        assert body["code"] == "filter_too_many_values"
        assert set(body) >= {"detail", "code", "errors", "request_id"}
    assert repository.calls == [], "nothing reaches the database"


def test_too_many_items_or_a_bad_item_is_a_422_that_names_the_field(client):
    repository = FakeRepository()
    serve(repository)
    over = "&".join(f"equipment_id={i}" for i in range(1, MAX_FILTER_VALUES + 2))

    response = client.get(f"/maintenance/requests?{over}")
    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert any(
        error["field"].endswith("equipment_id") for error in response.json()["errors"]
    )

    assert client.get("/maintenance/requests?equipment_id=abc").status_code == 422
    assert repository.calls == []


def test_the_limit_is_exactly_twenty_items(client):
    repository = FakeRepository()
    serve(repository)
    exactly = "&".join(f"equipment_id={i}" for i in range(1, MAX_FILTER_VALUES + 1))

    assert client.get(f"/maintenance/requests?{exactly}").status_code == 200
    assert len(repository.calls[0]["equipment_ids"]) == MAX_FILTER_VALUES


# -- repository (real PostgreSQL) ---------------------------------------------------------------


async def _tickets(session):
    user = User(clerk_user_id="u9", email="u9@x.co", full_name="U", is_active=True)
    session.add(user)
    session.add_all(
        [
            Priority(code=code, name=code, level=level, is_active=True)
            for code, level in (("low", 1), ("high", 3), ("critical", 4))
        ]
    )
    kind = EquipmentType(code="T", name="T", is_active=True)
    session.add(kind)
    await session.flush()
    items = []
    for tag in ("E-1", "E-2", "E-3"):
        item = Equipment(
            asset_tag=tag,
            equipment_type_id=kind.id,
            brand="Dell",
            model="X",
            status="assigned",
        )
        session.add(item)
        items.append(item)
    await session.flush()
    plan = [
        (0, "low"),
        (0, "high"),
        (1, "high"),
        (1, "critical"),
        (2, "critical"),
        (2, "low"),
    ]
    for number, (index, priority) in enumerate(plan, start=1):
        session.add(
            MaintenanceRequest(
                ticket_number=f"TCK-F-{number}",
                equipment_id=items[index].id,
                requested_by_user_id=user.id,
                title=f"{items[index].asset_tag} {priority}",
                description="d",
                priority=priority,
                status="submitted",
            )
        )
    await session.flush()
    return items


def titles(page) -> list[str]:
    return sorted(item.title for item in page.items)


async def test_several_priorities_return_the_union(db_session):
    repo = MaintenanceRepository(db_session)
    await _tickets(db_session)

    both = await repo.list_requests(
        scope=DataScope.everything(), priorities=["critical", "high"]
    )
    assert titles(both) == ["E-1 high", "E-2 critical", "E-2 high", "E-3 critical"]
    assert both.total == 4

    one = await repo.list_requests(scope=DataScope.everything(), priorities=["low"])
    assert titles(one) == ["E-1 low", "E-3 low"]


async def test_several_items_return_the_union_and_combine_with_priorities(db_session):
    repo = MaintenanceRepository(db_session)
    items = await _tickets(db_session)
    scope = DataScope.everything()

    two = await repo.list_requests(
        scope=scope, equipment_ids=[items[0].id, items[2].id]
    )
    assert titles(two) == ["E-1 high", "E-1 low", "E-3 critical", "E-3 low"]

    combined = await repo.list_requests(
        scope=scope,
        equipment_ids=[items[0].id, items[2].id],
        priorities=["critical", "high"],
    )
    assert titles(combined) == ["E-1 high", "E-3 critical"]


async def test_empty_lists_and_the_single_value_parameters_still_behave(db_session):
    repo = MaintenanceRepository(db_session)
    items = await _tickets(db_session)
    scope = DataScope.everything()

    assert (await repo.list_requests(scope=scope)).total == 6
    assert (
        await repo.list_requests(scope=scope, priorities=[], equipment_ids=[])
    ).total == 6
    assert titles(await repo.list_requests(scope=scope, priority="low")) == [
        "E-1 low",
        "E-3 low",
    ]
    assert titles(await repo.list_requests(scope=scope, equipment_id=items[1].id)) == [
        "E-2 critical",
        "E-2 high",
    ]
    assert (await repo.list_requests(scope=scope, priorities=["nope"])).total == 0
