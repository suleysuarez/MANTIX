"""What the mobile triage inbox needs from the API: several categories and a technician filter in
the ticket list, only-active technicians, and a searchable, paginated category catalog."""

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_authenticated_user
from app.api.providers import (
    get_maintenance_service,
    get_queue_service,
    get_technician_service,
)
from app.core.filters import MAX_FILTER_VALUES
from app.core.pagination import PageParams
from app.core.scope import DataScope
from app.main import app
from app.models.auth import User
from app.models.category import RequestCategory
from app.models.equipment import Equipment, EquipmentType
from app.models.maintenance import MaintenanceRequest, TicketAssignment
from app.models.priority import Priority
from app.models.technician import Technician
from app.repositories.base import Page
from app.repositories.maintenance import MaintenanceRepository
from app.repositories.queue import QueueRepository
from app.repositories.technician import TechnicianRepository
from app.services.maintenance import MaintenanceService
from app.services.queue import QueueService
from app.services.technician import TechnicianService


@pytest.fixture
def client():
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def sign_in(*codes: str) -> None:
    permissions = [SimpleNamespace(code=c, name=c, is_active=True) for c in codes]
    user = SimpleNamespace(
        id=1, roles=[SimpleNamespace(code="X", is_active=True, permissions=permissions)]
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user


# -- tickets: several categories and technicians (fake repository) ------------------------------


class FakeTicketRepository:
    def __init__(self):
        self.calls: list[dict] = []

    async def scope_for(self, actor):
        return DataScope.everything()

    async def list_requests(self, **kwargs):
        self.calls.append(kwargs)
        params = kwargs["params"]
        return Page(items=[], total=0, page=params.page, size=params.size)


def serve_tickets(repository: FakeTicketRepository) -> None:
    sign_in("tickets:ver")
    service = MaintenanceService(
        repository,
        SimpleNamespace(record=lambda **_: None),
        SimpleNamespace(notify=lambda **_: None),
    )
    app.dependency_overrides[get_maintenance_service] = lambda: service


def test_one_category_keeps_working_and_several_arrive_as_a_list(client):
    repository = FakeTicketRepository()
    serve_tickets(repository)

    assert client.get("/maintenance/requests?category=hardware").status_code == 200
    assert repository.calls[-1]["categories"] == ["hardware"]

    response = client.get("/maintenance/requests?category=hardware, network ,hardware")
    assert response.status_code == 200
    assert repository.calls[-1]["categories"] == ["hardware", "network"]

    client.get("/maintenance/requests")
    assert repository.calls[-1]["categories"] == []


def test_more_than_twenty_categories_is_a_422_with_the_stable_code(client):
    repository = FakeTicketRepository()
    serve_tickets(repository)
    many = ",".join(f"c{i}" for i in range(MAX_FILTER_VALUES + 1))
    response = client.get(f"/maintenance/requests?category={many}")

    assert response.status_code == 422
    assert response.json()["code"] == "filter_too_many_values"
    assert repository.calls == []


def test_technician_id_accepts_one_or_several_and_defaults_to_no_filter(client):
    repository = FakeTicketRepository()
    serve_tickets(repository)

    client.get("/maintenance/requests")
    assert repository.calls[-1]["technician_ids"] is None
    client.get("/maintenance/requests?technician_id=4")
    assert repository.calls[-1]["technician_ids"] == [4]
    client.get("/maintenance/requests?technician_id=4&technician_id=9&status=submitted")
    assert repository.calls[-1]["technician_ids"] == [4, 9]
    assert repository.calls[-1]["status"] == "submitted"


def test_technician_id_is_validated_as_a_number_with_at_most_twenty(client):
    repository = FakeTicketRepository()
    serve_tickets(repository)
    over = "&".join(f"technician_id={i}" for i in range(1, MAX_FILTER_VALUES + 2))

    for query in (over, "technician_id=luis"):
        response = client.get(f"/maintenance/requests?{query}")
        assert response.status_code == 422
        assert response.json()["code"] == "validation_error"
        assert any(
            "technician_id" in error["field"] for error in response.json()["errors"]
        )
    assert repository.calls == []

    exactly = "&".join(f"technician_id={i}" for i in range(1, MAX_FILTER_VALUES + 1))
    assert client.get(f"/maintenance/requests?{exactly}").status_code == 200


# -- technicians: only active accounts (fake service) --------------------------------------------


class FakeTechnicianRepository:
    def __init__(self):
        self.calls: list[dict] = []

    async def list(self, **kwargs):
        self.calls.append(kwargs)
        params = kwargs["params"]
        return Page(items=[], total=0, page=params.page, size=params.size)


def test_the_technician_list_passes_is_active_through_and_defaults_to_all(client):
    repository = FakeTechnicianRepository()
    sign_in("tecnicos:ver")
    app.dependency_overrides[get_technician_service] = lambda: TechnicianService(
        repository, SimpleNamespace(record=lambda **_: None)
    )

    client.get("/technicians")
    assert repository.calls[-1]["is_active"] is None
    client.get("/technicians?is_active=true&is_available=true&search=luis")
    assert repository.calls[-1]["is_active"] is True
    assert repository.calls[-1]["is_available"] is True
    client.get("/technicians?is_active=false")
    assert repository.calls[-1]["is_active"] is False
    assert client.get("/technicians?is_active=quizas").status_code == 422


# -- categories: search and pages (fake service) --------------------------------------------------


class FakeQueueRepository:
    def __init__(self, names: list[str]):
        self.names = names
        self.calls: list[tuple] = []

    async def active_categories(self, search=None, params=None):
        self.calls.append((search, params))
        matches = [
            SimpleNamespace(code=n.lower(), name=n)
            for n in self.names
            if not search or search.lower() in n.lower()
        ]
        start = (params.page - 1) * params.size
        return Page(
            items=matches[start : start + params.size],
            total=len(matches),
            page=params.page,
            size=params.size,
        )


def serve_categories(repository: FakeQueueRepository) -> None:
    sign_in("tickets:ver")
    app.dependency_overrides[get_queue_service] = lambda: QueueService(repository)


def test_categories_without_parameters_return_the_whole_catalog_with_page_headers(
    client,
):
    repository = FakeQueueRepository(["Hardware", "Red", "Software"])
    serve_categories(repository)
    response = client.get("/maintenance/categories")

    assert response.status_code == 200
    assert [c["name"] for c in response.json()] == ["Hardware", "Red", "Software"]
    assert response.json()[0] == {"code": "hardware", "name": "Hardware"}
    assert response.headers["X-Total-Count"] == "3"
    assert response.headers["X-Total-Pages"] == "1"
    assert repository.calls[0][0] is None


def test_categories_can_be_searched_and_paged(client):
    repository = FakeQueueRepository(["Hardware", "Red", "Software", "Redes móviles"])
    serve_categories(repository)

    searched = client.get("/maintenance/categories?search=red")
    assert [c["name"] for c in searched.json()] == ["Red", "Redes móviles"]
    assert searched.headers["X-Total-Count"] == "2"

    second = client.get("/maintenance/categories?size=2&page=2")
    assert [c["name"] for c in second.json()] == ["Software", "Redes móviles"]
    assert second.headers["X-Page"] == "2"
    assert second.headers["X-Total-Pages"] == "2"
    assert client.get("/maintenance/categories?search=" + "x" * 101).status_code == 422


# -- repositories (real PostgreSQL) ---------------------------------------------------------------


async def _world(session):
    """Three tickets (hardware, network, no category) and two technicians, one inactive."""
    owner = User(clerk_user_id="o", email="o@x.co", full_name="Owner", is_active=True)
    luis = User(clerk_user_id="l", email="l@x.co", full_name="Luis", is_active=True)
    ana = User(clerk_user_id="a", email="a@x.co", full_name="Ana", is_active=False)
    session.add_all([owner, luis, ana])
    session.add_all(
        [Priority(code="low", name="Low", level=1, is_active=True)]
        + [
            RequestCategory(code=code, name=name, is_active=active)
            for code, name, active in (
                ("hardware", "Hardware", True),
                ("network", "Red", True),
                ("software", "Software", True),
                ("old", "Red antigua", False),
            )
        ]
    )
    kind = EquipmentType(code="T", name="T", is_active=True)
    session.add(kind)
    await session.flush()
    item = Equipment(
        asset_tag="E-1",
        equipment_type_id=kind.id,
        brand="Dell",
        model="X",
        status="assigned",
    )
    tech_luis = Technician(user_id=luis.id, is_available=True)
    tech_ana = Technician(user_id=ana.id, is_available=False)
    session.add_all([item, tech_luis, tech_ana])
    await session.flush()
    tickets = {}
    for name, category in (("hw", "hardware"), ("net", "network"), ("none", None)):
        ticket = MaintenanceRequest(
            ticket_number=f"TCK-Q-{name}",
            equipment_id=item.id,
            requested_by_user_id=owner.id,
            title=name,
            description="d",
            priority="low",
            category=category,
            status="submitted",
        )
        session.add(ticket)
        tickets[name] = ticket
    await session.flush()
    now = datetime(2026, 11, 1, tzinfo=UTC)
    session.add_all(
        [
            TicketAssignment(
                request_id=tickets["hw"].id, technician_id=tech_luis.id, assigned_at=now
            ),
            # Luis worked this one in the past and was taken off it: it must not count.
            TicketAssignment(
                request_id=tickets["net"].id,
                technician_id=tech_luis.id,
                assigned_at=now,
                unassigned_at=now + timedelta(days=1),
            ),
            TicketAssignment(
                request_id=tickets["net"].id,
                technician_id=tech_ana.id,
                assigned_at=now + timedelta(days=1),
            ),
        ]
    )
    await session.flush()
    return tickets, tech_luis, tech_ana


def titles(page) -> list[str]:
    return sorted(item.title for item in page.items)


async def test_several_categories_return_the_union(db_session):
    repo = MaintenanceRepository(db_session)
    await _world(db_session)
    scope = DataScope.everything()

    both = await repo.list_requests(scope=scope, categories=["hardware", "network"])
    assert titles(both) == ["hw", "net"]
    assert titles(await repo.list_requests(scope=scope, categories=["software"])) == []
    assert (await repo.list_requests(scope=scope, categories=[])).total == 3
    assert titles(await repo.list_requests(scope=scope, category="hardware")) == ["hw"]


async def test_the_technician_filter_counts_only_current_assignments(db_session):
    repo = MaintenanceRepository(db_session)
    _, luis, ana = await _world(db_session)
    scope = DataScope.everything()

    assert titles(await repo.list_requests(scope=scope, technician_ids=[luis.id])) == [
        "hw"
    ]
    assert titles(await repo.list_requests(scope=scope, technician_ids=[ana.id])) == [
        "net"
    ]
    both = await repo.list_requests(scope=scope, technician_ids=[luis.id, ana.id])
    assert titles(both) == ["hw", "net"]
    assert (await repo.list_requests(scope=scope, technician_ids=[])).total == 3
    assert (await repo.list_requests(scope=scope, technician_ids=[9999])).total == 0


async def test_technician_category_and_unassigned_filters_combine(db_session):
    repo = MaintenanceRepository(db_session)
    _, luis, ana = await _world(db_session)
    scope = DataScope.everything()

    mixed = await repo.list_requests(
        scope=scope, technician_ids=[luis.id, ana.id], categories=["network"]
    )
    assert titles(mixed) == ["net"]
    contradictory = await repo.list_requests(
        scope=scope, technician_ids=[luis.id], unassigned=True
    )
    assert contradictory.total == 0


async def test_the_technician_repository_filters_by_account_status(db_session):
    repo = TechnicianRepository(db_session)
    await _world(db_session)

    assert sorted(t.user.full_name for t in (await repo.list()).items) == [
        "Ana",
        "Luis",
    ]
    active = await repo.list(is_active=True)
    assert [t.user.full_name for t in active.items] == ["Luis"]
    assert active.total == 1
    inactive = await repo.list(is_active=False)
    assert [t.user.full_name for t in inactive.items] == ["Ana"]
    both_filters = await repo.list(is_active=True, is_available=False)
    assert both_filters.total == 0


async def test_the_category_repository_searches_and_pages_only_active_ones(db_session):
    repo = QueueRepository(db_session)
    await _world(db_session)

    everything = await repo.active_categories()
    assert [c.name for c in everything.items] == ["Hardware", "Red", "Software"]
    assert "Red antigua" not in [c.name for c in everything.items], (
        "inactive ones are hidden"
    )

    found = await repo.active_categories("RED")
    assert [c.name for c in found.items] == ["Red"]
    assert found.total == 1

    second = await repo.active_categories(None, PageParams(page=2, size=2))
    assert [c.name for c in second.items] == ["Software"]
    assert second.total == 3
    assert second.pages == 2

    assert (await repo.active_categories("100%")).total == 0, "wildcards are literal"
