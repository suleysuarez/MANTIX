from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.authz import AuthContext
from app.main import app
from app.models.auth import User
from app.models.equipment import Equipment, EquipmentType
from app.models.maintenance import MaintenanceRequest, TicketAssignment
from app.models.priority import Priority
from app.models.technician import Technician
from app.repositories.dashboard import (
    CountRow,
    DashboardRepository,
    FailingEquipmentRow,
    ResolutionStats,
    WorkloadRow,
)
from app.services.dashboard import DashboardService

NOW = datetime(2026, 10, 11, 12, 0, tzinfo=UTC)


# -- real-database aggregates -------------------------------------------------


async def seed(session):
    session.add_all(
        [
            Priority(code="low", name="Low", level=1, sla_hours=100, is_active=True),
            Priority(code="high", name="High", level=3, sla_hours=24, is_active=True),
        ]
    )
    etype = EquipmentType(code="LAP", name="Laptop", is_active=True)
    users = [
        User(
            clerk_user_id=f"c{i}",
            email=f"u{i}@x.co",
            full_name=f"User {i}",
            is_active=True,
        )
        for i in range(3)
    ]
    session.add_all([etype, *users])
    await session.flush()
    techs = [
        Technician(user_id=users[1].id, is_available=True),
        Technician(user_id=users[2].id, is_available=False),
    ]
    laptops = [
        Equipment(
            asset_tag=f"LT-{i}",
            equipment_type_id=etype.id,
            brand="Dell",
            model="X",
            status="assigned" if i < 2 else "in_repair",
        )
        for i in range(3)
    ]
    session.add_all([*techs, *laptops])
    await session.flush()

    def ticket(n, equipment, priority, status, age_h, resolved_after_h=None):
        created = NOW - timedelta(hours=age_h)
        return MaintenanceRequest(
            ticket_number=f"T-{n}",
            equipment_id=equipment.id,
            requested_by_user_id=users[0].id,
            title=f"t{n}",
            description="d",
            priority=priority,
            status=status,
            created_at=created,
            resolved_at=(
                created + timedelta(hours=resolved_after_h)
                if resolved_after_h is not None
                else None
            ),
        )

    tickets = [
        ticket(1, laptops[0], "high", "in_progress", 30),  # open, overdue (SLA 24h)
        ticket(2, laptops[0], "high", "assigned", 2),  # open, on time
        ticket(3, laptops[1], "low", "waiting", 50),  # open, within SLA 100h
        ticket(4, laptops[0], "high", "resolved", 100, resolved_after_h=10),
        ticket(5, laptops[1], "low", "closed", 100, resolved_after_h=30),
        ticket(6, laptops[2], "low", "submitted", 1),  # open, unassigned
    ]
    session.add_all(tickets)
    await session.flush()
    session.add_all(
        [
            TicketAssignment(request_id=tickets[0].id, technician_id=techs[0].id),
            TicketAssignment(request_id=tickets[1].id, technician_id=techs[0].id),
            TicketAssignment(request_id=tickets[2].id, technician_id=techs[1].id),
            TicketAssignment(request_id=tickets[3].id, technician_id=techs[0].id),
            TicketAssignment(request_id=tickets[4].id, technician_id=techs[1].id),
        ]
    )
    await session.flush()
    return SimpleNamespace(techs=techs, users=users, laptops=laptops)


async def test_ticket_counts_by_status_priority_and_overdue(db_session):
    data = await seed(db_session)
    repo = DashboardRepository(db_session)
    by_status = {r.key: r.count for r in await repo.tickets_by_status()}
    assert by_status == {
        "in_progress": 1,
        "assigned": 1,
        "waiting": 1,
        "resolved": 1,
        "closed": 1,
        "submitted": 1,
    }
    # only open tickets, most urgent first
    assert await repo.tickets_by_priority() == [CountRow("high", 2), CountRow("low", 2)]
    assert await repo.count_overdue(NOW) == 1
    # scoped to technician 2: two tickets, none overdue
    scoped = await repo.tickets_by_status(technician_id=data.techs[1].id)
    assert sum(r.count for r in scoped) == 2
    assert await repo.count_overdue(NOW, technician_id=data.techs[1].id) == 0


async def test_equipment_by_status(db_session):
    await seed(db_session)
    rows = await DashboardRepository(db_session).equipment_by_status()
    assert rows == [CountRow("assigned", 2), CountRow("in_repair", 1)]


async def test_resolution_stats_overall_and_per_priority(db_session):
    await seed(db_session)
    repo = DashboardRepository(db_session)
    window = NOW - timedelta(days=30)
    (overall,) = await repo.resolution_stats(date_from=window)
    assert overall.resolved_count == 2
    assert overall.avg_hours == pytest.approx(20.0)  # (10 + 30) / 2
    assert overall.median_hours == pytest.approx(20.0)
    per_priority = await repo.resolution_stats(date_from=window, by_priority=True)
    assert [(r.key, r.resolved_count, round(r.avg_hours)) for r in per_priority] == [
        ("high", 1, 10),
        ("low", 1, 30),
    ]
    # nothing resolved inside a 1-hour window -> a single empty overall row
    empty = await repo.resolution_stats(date_from=NOW - timedelta(hours=1))
    assert empty == [ResolutionStats(None, 0, None, None)]


async def test_technician_workload(db_session):
    data = await seed(db_session)
    repo = DashboardRepository(db_session)
    rows = await repo.technician_workload(date_from=NOW - timedelta(days=30))
    by_name = {r.full_name: r for r in rows}
    first, second = by_name["User 1"], by_name["User 2"]
    assert (first.open_tickets, first.resolved_in_window) == (2, 1)
    assert (second.open_tickets, second.resolved_in_window) == (1, 1)
    assert rows[0].open_tickets >= rows[1].open_tickets  # busiest first
    only = await repo.technician_workload(
        date_from=NOW - timedelta(days=30), technician_id=data.techs[1].id
    )
    assert [r.full_name for r in only] == ["User 2"]
    assert await repo.get_technician_id_for_user(data.users[1].id) == data.techs[0].id
    assert await repo.get_technician_id_for_user(data.users[0].id) is None


async def test_top_failing_equipment(db_session):
    await seed(db_session)
    repo = DashboardRepository(db_session)
    rows = await repo.top_failing_equipment(date_from=NOW - timedelta(days=30), limit=2)
    assert [(r.asset_tag, r.tickets) for r in rows] == [("LT-0", 3), ("LT-1", 2)]
    short = await repo.top_failing_equipment(
        date_from=NOW - timedelta(hours=3), limit=5
    )
    assert [r.asset_tag for r in short] == ["LT-0", "LT-2"]


# -- service scoping (fake repository) -------------------------------------------


class FakeDashboardRepository:
    def __init__(self, technician_id=None):
        self.technician_id = technician_id
        self.scopes = []

    async def get_technician_id_for_user(self, user_id):
        return self.technician_id

    async def tickets_by_status(self, *, technician_id=None):
        self.scopes.append(technician_id)
        return [CountRow("submitted", 2), CountRow("closed", 3), CountRow("waiting", 1)]

    async def tickets_by_priority(self, *, technician_id=None):
        return [CountRow("high", 1)]

    async def count_overdue(self, now, *, technician_id=None):
        return 1

    async def equipment_by_status(self):
        return [CountRow("assigned", 5)]

    async def resolution_stats(
        self, *, date_from, by_priority=False, technician_id=None
    ):
        if by_priority:
            return [ResolutionStats("high", 2, 4.0, 3.0)]
        return [ResolutionStats(None, 2, 4.123, 3.0)]

    async def technician_workload(self, *, date_from, technician_id=None):
        self.scopes.append(technician_id)
        return [WorkloadRow(1, "Ana", True, 2, 5)]

    async def top_failing_equipment(self, *, date_from, limit):
        return [FailingEquipmentRow(1, "LT-1", "Dell", "X", 4, NOW)]


def actor(*roles):
    return AuthContext(user=SimpleNamespace(id=7), roles=frozenset(roles))


async def test_supervisor_sees_everything_unscoped():
    repo = FakeDashboardRepository()
    summary = await DashboardService(repo).summary(
        actor("SUPERVISOR"), days=30, now=NOW
    )
    assert summary.scope == "all" and repo.scopes == [None]
    assert summary.tickets.total == 6
    assert summary.tickets.open == 3  # submitted + waiting
    assert summary.tickets.overdue == 1
    assert summary.resolution.avg_hours == 4.12
    assert summary.equipment_by_status[0].count == 5


async def test_technician_is_scoped_to_their_own_profile():
    repo = FakeDashboardRepository(technician_id=42)
    service = DashboardService(repo)
    summary = await service.summary(actor("TECHNICIAN"), days=7, now=NOW)
    workload = await service.workload(actor("TECHNICIAN"), days=7, now=NOW)
    assert summary.scope == workload.scope == "own"
    assert repo.scopes == [42, 42]


async def test_technician_without_profile_matches_no_technician():
    repo = FakeDashboardRepository(technician_id=None)
    await DashboardService(repo).summary(actor("TECHNICIAN"), days=7, now=NOW)
    assert repo.scopes == [0]


async def test_resolution_times_and_top_equipment_shapes():
    service = DashboardService(FakeDashboardRepository())
    times = await service.resolution_times(actor("ADMIN"), days=30, now=NOW)
    assert times.overall.priority is None
    assert times.by_priority[0].priority == "high"
    top = await service.top_failing_equipment(days=30, limit=5, now=NOW)
    assert top.equipment[0].asset_tag == "LT-1"


# -- HTTP -------------------------------------------------------------------------


class StubDashboardService:
    def __init__(self):
        self.calls = []

    async def summary(self, actor, *, days):
        self.calls.append(("summary", days))
        return await DashboardService(FakeDashboardRepository()).summary(
            actor, days=days, now=NOW
        )

    async def top_failing_equipment(self, *, days, limit):
        self.calls.append(("top", days, limit))
        return await DashboardService(FakeDashboardRepository()).top_failing_equipment(
            days=days, limit=limit, now=NOW
        )


@pytest.fixture
def client():
    stub = StubDashboardService()
    user = SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                code="SUPERVISOR",
                is_active=True,
                permissions=[SimpleNamespace(code="dashboard.read", is_active=True)],
            )
        ],
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user
    app.dependency_overrides[providers.get_dashboard_service] = lambda: stub
    with TestClient(app, raise_server_exceptions=False) as test_client:
        test_client.stub = stub
        yield test_client
    app.dependency_overrides.clear()


def test_summary_endpoint_returns_the_documented_shape(client):
    response = client.get("/dashboard/summary?days=14")
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {
        "generated_at",
        "scope",
        "window_days",
        "tickets",
        "equipment_by_status",
        "resolution",
    }
    assert body["window_days"] == 14
    assert client.stub.calls == [("summary", 14)]


def test_top_failing_equipment_endpoint_passes_filters(client):
    response = client.get("/dashboard/top-failing-equipment?days=90&limit=3")
    assert response.status_code == 200
    assert client.stub.calls == [("top", 90, 3)]


@pytest.mark.parametrize("query", ["days=0", "days=366", "limit=0", "limit=51"])
def test_dashboard_rejects_out_of_range_params(client, query):
    path = "top-failing-equipment" if "limit" in query else "summary"
    assert client.get(f"/dashboard/{path}?{query}").status_code == 422
