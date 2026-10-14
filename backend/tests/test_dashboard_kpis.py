from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.authz import AuthContext
from app.main import app
from app.models.auth import User
from app.models.equipment import Equipment, EquipmentStatusHistory, EquipmentType
from app.models.maintenance import MaintenanceRequest
from app.models.priority import Priority
from app.models.schedule import MaintenanceSchedule
from app.repositories.dashboard import CountRow
from app.repositories.dashboard_kpis import (
    BacklogRow,
    BucketRow,
    DashboardKpiRepository,
    DownEquipmentRow,
    ScheduleAlertRow,
    TechnicianPerformanceRow,
    TicketAlertRow,
    WindowStats,
)
from app.services.dashboard_kpis import (
    DashboardKpiService,
    change_pct,
    period_window,
    previous_window,
)

NOW = datetime(2026, 10, 11, 12, 0, tzinfo=UTC)


# -- pure helpers ---------------------------------------------------------------


def test_period_windows_are_whole_days_or_months():
    assert period_window("7d", NOW) == (
        datetime(2026, 10, 5, tzinfo=UTC),
        datetime(2026, 10, 12, tzinfo=UTC),
    )
    start, end = period_window("30d", NOW)
    assert (end - start).days == 30
    assert period_window("12m", NOW) == (
        datetime(2025, 11, 1, tzinfo=UTC),
        datetime(2026, 11, 1, tzinfo=UTC),
    )


def test_previous_window_has_the_same_length_and_ends_where_the_current_starts():
    start, end = period_window("7d", NOW)
    prev_start, prev_end = previous_window("7d", start, end)
    assert prev_end == start and (prev_end - prev_start) == (end - start)
    start, end = period_window("12m", NOW)
    assert previous_window("12m", start, end) == (
        datetime(2024, 11, 1, tzinfo=UTC),
        start,
    )


def test_change_pct_is_null_when_not_comparable():
    assert change_pct(15, 10) == 50.0
    assert change_pct(5, 10) == -50.0
    assert change_pct(None, 10) is None
    assert change_pct(10, None) is None
    assert change_pct(10, 0) is None


# -- service (fake repository) --------------------------------------------------------


def stats(**overrides):
    values = {
        "created": 10,
        "resolved_of_created": 5,
        "resolved": 8,
        "avg_resolution_hours": 12.0,
        "median_resolution_hours": 9.0,
        "p90_resolution_hours": 30.0,
        "min_resolution_hours": 1.0,
        "max_resolution_hours": 40.0,
        "stddev_resolution_hours": 11.5,
        "sla_met": 6,
        "sla_missed": 2,
        "sla_excluded": 3,
        "avg_first_assignment_hours": 1.5,
        "first_assignment_count": 9,
    }
    values.update(overrides)
    return WindowStats(**values)


EMPTY = WindowStats(0, 0, 0, None, None, None, None, None, None, 0, 0, 0, None, 0)


class FakeKpiRepository:
    def __init__(self, current=None, previous=None, technician_id=None):
        self.windows = [
            current or stats(),
            previous or stats(median_resolution_hours=18.0),
        ]
        self.technician_id = technician_id
        self.scopes = []

    async def get_technician_id_for_user(self, user_id):
        return self.technician_id

    async def window_stats(self, *, start, end, technician_id=None):
        self.scopes.append(technician_id)
        return self.windows.pop(0)

    async def backlog(self, now, *, technician_id=None):
        return BacklogRow(open=9, age_0_2=4, age_3_7=3, age_over_7=2)

    async def equipment_by_status(self):
        return [
            CountRow("assigned", 6),
            CountRow("in_storage", 2),
            CountRow("in_repair", 2),
        ]

    async def technician_performance(self, *, start, end, technician_id=None):
        self.scopes.append(technician_id)
        return [
            TechnicianPerformanceRow(1, "Ana", "Redes", True, 5, 12, 6.0, 9, 1, 2, 1),
            TechnicianPerformanceRow(2, "Luis", None, False, 2, 3, 30.0, 2, 1, 0, 0),
            TechnicianPerformanceRow(3, "Marta", None, True, 0, 0, None, 0, 0, 0, 0),
        ]

    async def open_tickets_at(self, at, *, technician_id=None):
        return 6

    async def availability_at(self, at):
        return 5, 10

    async def trend_buckets(self, *, start, end, unit, technician_id=None):
        self.unit = unit
        return [
            BucketRow(
                start + timedelta(days=1) if unit == "day" else start, 3, 2, 10.0, 1, 1
            )
        ]

    async def ticket_alerts(self, now, *, limit=10, technician_id=None):
        return [
            TicketAlertRow(
                1,
                "T-1",
                "a",
                1,
                "LT-1",
                "high",
                "in_progress",
                True,
                now - timedelta(hours=1),
            ),
            TicketAlertRow(
                2,
                "T-2",
                "b",
                1,
                "LT-1",
                "critical",
                "submitted",
                False,
                now + timedelta(hours=20),
            ),
            TicketAlertRow(
                3,
                "T-3",
                "c",
                1,
                "LT-1",
                "high",
                "assigned",
                True,
                now + timedelta(hours=2),
            ),
            TicketAlertRow(
                4, "T-4", "d", 1, "LT-1", "critical", "submitted", False, None
            ),
        ]

    async def down_equipment(self, *, limit=10):
        return [
            DownEquipmentRow(
                1, "LT-1", "Dell", "X", "in_repair", NOW - timedelta(hours=30)
            ),
            DownEquipmentRow(2, "LT-2", "Dell", "X", "lost", None),
        ]

    async def schedule_alerts(
        self, now, *, within_days=7, limit=10, technician_id=None
    ):
        return [
            ScheduleAlertRow(1, 1, "LT-1", "Limpieza", now - timedelta(days=2)),
            ScheduleAlertRow(2, 1, "LT-1", "Revisión", now + timedelta(days=3)),
        ]


def actor(*roles):
    return AuthContext(user=SimpleNamespace(id=7), roles=frozenset(roles))


async def test_kpis_compare_against_the_previous_period():
    service = DashboardKpiService(FakeKpiRepository())
    kpis = await service.kpis(actor("SUPERVISOR"), period="7d", now=NOW)
    assert kpis.scope == "all" and kpis.period == "7d"
    assert (kpis.mttr_hours.value, kpis.mttr_hours.previous) == (9.0, 18.0)  # medians
    assert kpis.mttr_hours.change_pct == -50.0  # lower is better; the UI colours it
    assert kpis.sla_compliance_pct.value == 75.0  # 6 / (6 + 2)
    assert kpis.resolution_rate_pct.value == 50.0
    assert kpis.backlog.open == 9
    assert (kpis.backlog.previous_open, kpis.backlog.change_pct) == (6, 50.0)
    assert kpis.availability.value == 80.0 and kpis.availability.total == 10
    assert (kpis.availability.previous, kpis.availability.change_pct) == (50.0, 60.0)


async def test_mttr_carries_the_whole_distribution_and_the_sample_size():
    service = DashboardKpiService(FakeKpiRepository())
    mttr = (await service.kpis(actor("ADMIN"), period="7d", now=NOW)).mttr_hours
    assert mttr.value == 9.0  # the median is the headline, not the mean
    assert (mttr.average_hours, mttr.p90_hours) == (12.0, 30.0)
    assert (mttr.min_hours, mttr.max_hours, mttr.stddev_hours) == (1.0, 40.0, 11.5)
    assert mttr.sample_size == 8 and mttr.low_sample is False


@pytest.mark.parametrize(("n", "low"), [(0, False), (1, True), (4, True), (5, False)])
async def test_figures_under_five_tickets_are_flagged_as_low_sample(n, low):
    few = stats(
        resolved=n, sla_met=n, sla_missed=0, created=n, first_assignment_count=n
    )
    kpis = await DashboardKpiService(FakeKpiRepository(current=few)).kpis(
        actor("ADMIN"), period="7d", now=NOW
    )
    assert kpis.mttr_hours.low_sample is low
    assert kpis.sla_compliance_pct.low_sample is low
    assert kpis.resolution_rate_pct.low_sample is low


async def test_single_ticket_has_no_standard_deviation():
    one = stats(resolved=1, stddev_resolution_hours=None)
    mttr = (
        await DashboardKpiService(FakeKpiRepository(current=one)).kpis(
            actor("ADMIN"), period="7d", now=NOW
        )
    ).mttr_hours
    assert mttr.stddev_hours is None and mttr.value == 9.0


async def test_sla_leaves_out_priorities_without_sla_and_reports_how_many():
    service = DashboardKpiService(FakeKpiRepository())
    sla = (await service.kpis(actor("ADMIN"), period="30d", now=NOW)).sla_compliance_pct
    assert (sla.met, sla.missed, sla.excluded_no_sla) == (6, 2, 3)
    assert sla.sample_size == 8  # the 3 excluded tickets are in neither side


async def test_kpis_are_null_instead_of_zero_when_there_is_no_data():
    service = DashboardKpiService(FakeKpiRepository(current=EMPTY, previous=EMPTY))
    kpis = await service.kpis(actor("ADMIN"), period="7d", now=NOW)
    assert kpis.mttr_hours.value is None and kpis.mttr_hours.sample_size == 0
    assert kpis.mttr_hours.p90_hours is None and kpis.mttr_hours.average_hours is None
    assert kpis.sla_compliance_pct.value is None
    assert kpis.sla_compliance_pct.change_pct is None
    assert kpis.resolution_rate_pct.value is None


async def test_sla_with_only_excluded_tickets_has_no_value():
    only_excluded = stats(sla_met=0, sla_missed=0, sla_excluded=4)
    service = DashboardKpiService(FakeKpiRepository(current=only_excluded))
    sla = (await service.kpis(actor("ADMIN"), period="7d", now=NOW)).sla_compliance_pct
    assert sla.value is None and sla.excluded_no_sla == 4


async def test_technician_kpis_are_scoped_to_their_profile():
    repo = FakeKpiRepository(technician_id=42)
    kpis = await DashboardKpiService(repo).kpis(
        actor("TECHNICIAN"), period="7d", now=NOW
    )
    assert kpis.scope == "own" and repo.scopes == [42, 42]


@pytest.mark.parametrize(
    ("period", "size", "unit"),
    [("7d", 7, "day"), ("30d", 30, "day"), ("12m", 12, "month")],
)
async def test_trends_are_zero_filled_for_every_bucket(period, size, unit):
    repo = FakeKpiRepository()
    trends = await DashboardKpiService(repo).trends(
        actor("ADMIN"), period=period, now=NOW
    )
    assert trends.granularity == unit == repo.unit
    assert len(trends.points) == size
    busy = [p for p in trends.points if p.created]
    assert len(busy) == 1 and busy[0].sla_compliance_pct == 50.0
    empty = next(p for p in trends.points if not p.created)
    assert (empty.resolved, empty.mttr_hours, empty.sla_compliance_pct) == (
        0,
        None,
        None,
    )


async def test_alerts_label_each_ticket_with_its_reason():
    alerts = await DashboardKpiService(FakeKpiRepository()).alerts(
        actor("ADMIN"), now=NOW
    )
    assert [t.reason for t in alerts.tickets] == [
        "sla_breached",
        "unassigned_critical",
        "sla_at_risk",
        "unassigned_critical",
    ]
    assert alerts.down_equipment[0].down_hours == 30.0
    assert alerts.down_equipment[1].down_hours is None
    assert [s.overdue for s in alerts.schedules] == [True, False]


async def test_technician_rows_keep_the_load_order_and_flag_small_samples():
    service = DashboardKpiService(FakeKpiRepository())
    result = await service.technicians(actor("SUPERVISOR"), period="30d", now=NOW)
    assert [t.full_name for t in result.technicians] == [
        "Ana",
        "Luis",
        "Marta",
    ]  # as returned: by load
    ana, luis, _ = result.technicians
    assert (ana.open_tickets, ana.resolved, ana.mttr_median_hours) == (5, 12, 6.0)
    assert ana.sample_size == 12 and ana.low_sample is False
    assert ana.sla_compliance_pct == 90.0 and ana.sla_sample_size == 10
    assert ana.sla_excluded_no_sla == 2 and ana.reopened == 1
    assert luis.low_sample is True and luis.sla_low_sample is True  # n = 3
    assert luis.sla_compliance_pct == pytest.approx(66.7)


async def test_technician_without_resolved_tickets_has_no_values_not_zeros():
    result = await DashboardKpiService(FakeKpiRepository()).technicians(
        actor("ADMIN"), period="7d", now=NOW
    )
    marta = result.technicians[2]
    assert marta.mttr_median_hours is None and marta.sla_compliance_pct is None
    assert marta.low_sample is False and marta.sample_size == 0


async def test_technician_performance_is_scoped_for_technicians():
    repo = FakeKpiRepository(technician_id=42)
    result = await DashboardKpiService(repo).technicians(
        actor("TECHNICIAN"), period="7d", now=NOW
    )
    assert result.scope == "own" and repo.scopes == [42]


# -- HTTP ---------------------------------------------------------------------------


class StubKpiService:
    def __init__(self):
        self.calls = []

    async def kpis(self, actor, *, period):
        self.calls.append(("kpis", period))
        return await DashboardKpiService(FakeKpiRepository()).kpis(
            actor, period=period, now=NOW
        )

    async def trends(self, actor, *, period):
        self.calls.append(("trends", period))
        return await DashboardKpiService(FakeKpiRepository()).trends(
            actor, period=period, now=NOW
        )

    async def technicians(self, actor, *, period):
        self.calls.append(("technicians", period))
        return await DashboardKpiService(FakeKpiRepository()).technicians(
            actor, period=period, now=NOW
        )

    async def alerts(self, actor):
        self.calls.append(("alerts",))
        return await DashboardKpiService(FakeKpiRepository()).alerts(actor, now=NOW)


def build_client(permissions):
    stub = StubKpiService()
    user = SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                code="SUPERVISOR",
                is_active=True,
                permissions=[
                    SimpleNamespace(code=code, is_active=True) for code in permissions
                ],
            )
        ],
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user
    app.dependency_overrides[providers.get_dashboard_service] = lambda: stub
    return stub


@pytest.fixture
def client():
    stub = build_client(["dashboard.read"])
    with TestClient(app, raise_server_exceptions=False) as test_client:
        test_client.stub = stub
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def forbidden_client():
    build_client([])
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_kpis_endpoint_returns_the_documented_shape(client):
    response = client.get("/dashboard/kpis?period=12m")
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {
        "generated_at",
        "scope",
        "period",
        "window_start",
        "window_end",
        "mttr_hours",
        "first_assignment_hours",
        "sla_compliance_pct",
        "resolution_rate_pct",
        "backlog",
        "availability",
    }
    assert set(body["sla_compliance_pct"]) >= {
        "value",
        "met",
        "missed",
        "excluded_no_sla",
    }
    assert client.stub.calls == [("kpis", "12m")]


def test_period_defaults_to_30_days(client):
    assert client.get("/dashboard/trends").status_code == 200
    assert client.stub.calls == [("trends", "30d")]


def test_trends_and_alerts_endpoints(client):
    trends = client.get("/dashboard/trends?period=7d").json()
    assert trends["granularity"] == "day" and len(trends["points"]) == 7
    alerts = client.get("/dashboard/alerts").json()
    assert set(alerts) == {
        "generated_at",
        "scope",
        "tickets",
        "down_equipment",
        "schedules",
    }


def test_technicians_endpoint_returns_the_documented_shape(client):
    response = client.get("/dashboard/technicians?period=7d")
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {
        "generated_at",
        "scope",
        "period",
        "window_start",
        "window_end",
        "technicians",
    }
    assert set(body["technicians"][0]) == {
        "technician_id",
        "full_name",
        "specialization",
        "is_available",
        "open_tickets",
        "resolved",
        "mttr_median_hours",
        "sample_size",
        "low_sample",
        "sla_compliance_pct",
        "sla_sample_size",
        "sla_low_sample",
        "sla_excluded_no_sla",
        "reopened",
    }
    assert client.stub.calls == [("technicians", "7d")]


@pytest.mark.parametrize("path", ["kpis", "trends", "technicians"])
@pytest.mark.parametrize("period", ["1d", "90d", "year", ""])
def test_unknown_periods_are_rejected(client, path, period):
    assert client.get(f"/dashboard/{path}?period={period}").status_code == 422


@pytest.mark.parametrize("path", ["kpis", "trends", "alerts", "technicians"])
def test_endpoints_require_the_dashboard_permission(forbidden_client, path):
    assert forbidden_client.get(f"/dashboard/{path}").status_code == 403


# -- real-database aggregates (need TEST_DATABASE_URL) -------------------------------


async def seed(session):
    session.add_all(
        [
            Priority(
                code="critical", name="Critical", level=4, sla_hours=4, is_active=True
            ),
            Priority(code="high", name="High", level=3, sla_hours=24, is_active=True),
            Priority(code="low", name="Low", level=1, sla_hours=None, is_active=True),
        ]
    )
    etype = EquipmentType(code="LAP", name="Laptop", is_active=True)
    user = User(clerk_user_id="c1", email="u@x.co", full_name="U", is_active=True)
    session.add_all([etype, user])
    await session.flush()
    laptop = Equipment(
        asset_tag="LT-1",
        equipment_type_id=etype.id,
        brand="Dell",
        model="X",
        status="in_repair",
    )
    working = Equipment(
        asset_tag="LT-2",
        equipment_type_id=etype.id,
        brand="Dell",
        model="X",
        status="assigned",
    )
    session.add_all([laptop, working])
    await session.flush()

    def ticket(n, priority, status, created_ago_h, resolved_after_h=None):
        created = NOW - timedelta(hours=created_ago_h)
        return MaintenanceRequest(
            ticket_number=f"T-{n}",
            equipment_id=laptop.id,
            requested_by_user_id=user.id,
            title=f"t{n}",
            description="d",
            priority=priority,
            status=status,
            created_at=created,
            resolved_at=None
            if resolved_after_h is None
            else created + timedelta(hours=resolved_after_h),
        )

    tickets = [
        ticket(1, "high", "resolved", 48, 10),  # met (10h <= 24h)
        ticket(2, "high", "resolved", 48, 30),  # missed (30h > 24h)
        ticket(3, "low", "closed", 48, 5),  # no SLA: excluded
        ticket(4, "critical", "submitted", 5),  # open, unassigned, breached (5h > 4h)
        ticket(5, "high", "in_progress", 22),  # open, at risk (2h left of 24h)
        ticket(6, "high", "cancelled", 40, 1),  # never counts
        ticket(7, "high", "waiting", 24 * 10),  # open, old backlog
    ]
    session.add_all(tickets)
    await session.flush()
    session.add(
        EquipmentStatusHistory(
            equipment_id=laptop.id,
            from_status="assigned",
            to_status="in_repair",
            changed_at=NOW - timedelta(hours=12),
        )
    )
    session.add(
        MaintenanceSchedule(
            equipment_id=laptop.id,
            title="Limpieza",
            interval_days=30,
            next_due_at=NOW - timedelta(days=1),
            is_active=True,
        )
    )
    await session.flush()
    return SimpleNamespace(laptop=laptop, working=working)


async def test_window_stats_excludes_priorities_without_sla_and_cancelled(db_session):
    await seed(db_session)
    result = await DashboardKpiRepository(db_session).window_stats(
        start=NOW - timedelta(days=30), end=NOW + timedelta(hours=1)
    )
    assert result.resolved == 3  # cancelled ticket 6 does not count
    assert (result.sla_met, result.sla_missed, result.sla_excluded) == (1, 1, 1)
    assert result.avg_resolution_hours == pytest.approx((10 + 30 + 5) / 3)
    assert result.median_resolution_hours == pytest.approx(10)
    assert result.p90_resolution_hours == pytest.approx(26)  # 10 + 0.8 * (30 - 10)
    assert (result.min_resolution_hours, result.max_resolution_hours) == (5, 30)
    assert result.stddev_resolution_hours == pytest.approx(12.58, abs=0.01)
    assert result.created == 6


async def test_window_stats_of_an_empty_window_are_zero_and_null(db_session):
    await seed(db_session)
    result = await DashboardKpiRepository(db_session).window_stats(
        start=NOW - timedelta(days=400), end=NOW - timedelta(days=399)
    )
    assert result == EMPTY


async def test_open_tickets_at_a_past_moment_ignore_later_resolutions(db_session):
    await seed(db_session)
    repo = DashboardKpiRepository(db_session)
    # 3 are open now; at NOW - 60h only T-7 (created 240h ago) exists and is open
    assert await repo.open_tickets_at(NOW) == 3
    assert await repo.open_tickets_at(NOW - timedelta(hours=60)) == 1
    # at NOW - 40h: T-1, T-2, T-3 (created 48h ago) are open too, T-6 is cancelled
    assert await repo.open_tickets_at(NOW - timedelta(hours=46)) == 4


async def test_availability_at_rebuilds_the_past_from_the_status_history(db_session):
    await seed(db_session)
    repo = DashboardKpiRepository(db_session)
    # LT-1 went in_repair 12h ago; LT-2 never changed
    assert await repo.availability_at(NOW) == (1, 2)
    before_repair = await repo.availability_at(NOW - timedelta(hours=24))
    assert before_repair == (2, 2)


async def test_backlog_buckets_open_tickets_by_age(db_session):
    await seed(db_session)
    backlog = await DashboardKpiRepository(db_session).backlog(NOW)
    assert (backlog.open, backlog.age_0_2, backlog.age_3_7, backlog.age_over_7) == (
        3,
        2,
        0,
        1,
    )


async def test_trend_buckets_group_by_day(db_session):
    await seed(db_session)
    rows = await DashboardKpiRepository(db_session).trend_buckets(
        start=NOW - timedelta(days=30), end=NOW + timedelta(days=1), unit="day"
    )
    assert sum(r.created for r in rows) == 6
    assert sum(r.resolved for r in rows) == 3
    assert sum(r.sla_met for r in rows) == 1 and sum(r.sla_missed for r in rows) == 1


async def test_ticket_alerts_flag_breached_at_risk_and_unassigned_critical(db_session):
    await seed(db_session)
    rows = await DashboardKpiRepository(db_session).ticket_alerts(NOW)
    assert [r.ticket_number for r in rows] == ["T-7", "T-4", "T-5"]
    assert rows[0].assigned is False


async def test_down_equipment_reports_when_it_went_down(db_session):
    await seed(db_session)
    rows = await DashboardKpiRepository(db_session).down_equipment()
    assert [(r.asset_tag, r.status) for r in rows] == [("LT-1", "in_repair")]
    assert rows[0].down_since == NOW - timedelta(hours=12)


async def test_schedule_alerts_include_overdue_plans(db_session):
    await seed(db_session)
    rows = await DashboardKpiRepository(db_session).schedule_alerts(NOW)
    assert [r.title for r in rows] == ["Limpieza"]


async def test_technician_performance_attributes_by_assignment_and_excludes_no_sla(
    db_session,
):
    from app.models.maintenance import TicketAssignment, TicketStatusHistory
    from app.models.technician import Technician

    data = await seed(db_session)
    users = [
        User(
            clerk_user_id=f"t{i}",
            email=f"t{i}@x.co",
            full_name=f"Tech {i}",
            is_active=True,
        )
        for i in range(2)
    ]
    db_session.add_all(users)
    await db_session.flush()
    techs = [Technician(user_id=u.id, is_available=True) for u in users]
    db_session.add_all(techs)
    await db_session.flush()
    rows = (
        await db_session.execute(
            MaintenanceRequest.__table__.select().order_by(
                MaintenanceRequest.ticket_number
            )
        )
    ).all()
    by_number = {r.ticket_number: r.id for r in rows}
    start = NOW - timedelta(days=30)

    def assign(number, tech, *, unassigned=None):
        return TicketAssignment(
            request_id=by_number[number],
            technician_id=tech.id,
            assigned_at=start,
            unassigned_at=unassigned,
        )

    db_session.add_all(
        [
            assign("T-1", techs[0]),  # resolved in 10h, SLA 24h: met
            assign("T-2", techs[0]),  # resolved in 30h: missed
            assign("T-3", techs[0]),  # low priority, no SLA: excluded
            assign("T-4", techs[1]),  # open critical
            assign("T-5", techs[1]),  # open
            TicketStatusHistory(
                request_id=by_number["T-1"],
                from_status="resolved",
                to_status="in_progress",
                changed_at=NOW - timedelta(hours=3),
            ),
        ]
    )
    await db_session.flush()
    result = await DashboardKpiRepository(db_session).technician_performance(
        start=start, end=NOW + timedelta(hours=1)
    )
    first, second = result  # busiest (open) first: Tech 1 has 2 open, Tech 0 none
    assert (first.full_name, first.open_tickets, first.resolved) == ("Tech 1", 2, 0)
    assert (second.full_name, second.open_tickets, second.resolved) == ("Tech 0", 0, 3)
    assert second.median_resolution_hours == pytest.approx(10)
    assert (second.sla_met, second.sla_missed, second.sla_excluded) == (1, 1, 1)
    assert second.reopened == 1 and first.reopened == 0
    only = await DashboardKpiRepository(db_session).technician_performance(
        start=start, end=NOW + timedelta(hours=1), technician_id=techs[0].id
    )
    assert [r.full_name for r in only] == ["Tech 0"]
    assert data.laptop.id
