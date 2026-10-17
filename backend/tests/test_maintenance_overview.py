from datetime import UTC, datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.exceptions import UnprocessableError
from app.main import app
from app.models.auth import User
from app.models.equipment import Equipment, EquipmentType
from app.models.maintenance import MaintenanceRecord
from app.models.schedule import MaintenanceSchedule, ScheduleReschedule, ScheduleRun
from app.models.technician import Technician
from app.repositories.maintenance_overview import (
    CostRow,
    DoneRow,
    DurationRow,
    MaintenanceOverviewRepository,
    MixRow,
    PlanRow,
    UpcomingRow,
    WeekRow,
)
from app.services.maintenance_overview import (
    MAX_CALENDAR_DAYS,
    MaintenanceOverviewService,
)
from tests.support import perm_objects

NOW = datetime(2026, 10, 14, 12, 0, tzinfo=UTC)  # a Wednesday
MONDAY = datetime(2026, 10, 12, tzinfo=UTC)


class FakeOverviewRepository:
    def __init__(self, **overrides):
        self.windows = {"mix": [MixRow(6, 4, 0), MixRow(2, 8, 0)]}
        self.overrides = overrides
        self.calls = {}

    def _next(self, name, default):
        values = self.overrides.get(name, default)
        self.calls[name] = self.calls.get(name, 0) + 1
        return values[self.calls[name] - 1]

    async def work_mix(self, *, start, end):
        return self._next("mix", self.windows["mix"])

    async def costs(self, *, start, end):
        return self._next(
            "costs", [CostRow(Decimal("300.50"), 6), CostRow(Decimal(200), 3)]
        )

    async def compliance_weeks(self, *, start, end, now):
        return self._next(
            "weeks",
            [
                [WeekRow(MONDAY, 5, 4), WeekRow(MONDAY - timedelta(days=7), 3, 3)],
                [WeekRow(MONDAY, 4, 2)],
            ],
        )

    async def durations(self, *, start, end):
        return self._next(
            "durations", [DurationRow(3.0, 2.0, 7), DurationRow(2.0, 2.0, 5)]
        )

    async def reschedules(self, *, start, end):
        return self._next("reschedules", [3, 6])

    async def upcoming(self, now):
        return UpcomingRow(overdue=2, next_7=4, next_30=9)

    async def plans_due_before(self, end, *, limit):
        return self.overrides.get("plans", [])

    async def runs_between(self, start, end, *, limit):
        return self.overrides.get("runs", [])


async def overview(**overrides):
    return await MaintenanceOverviewService(
        FakeOverviewRepository(**overrides)
    ).overview(period="30d", now=NOW)


# -- overview ------------------------------------------------------------------------------


async def test_work_mix_compares_the_preventive_share_with_the_previous_period():
    mix = (await overview()).mix
    assert (mix.preventive, mix.corrective, mix.sample_size) == (6, 4, 10)
    assert mix.preventive_pct == 60.0 and mix.previous_preventive_pct == 20.0
    assert mix.change_pct == 200.0 and mix.low_sample is False


async def test_everything_is_null_not_zero_when_nothing_happened():
    result = await overview(
        mix=[MixRow(0, 0, 0), MixRow(0, 0, 0)],
        costs=[CostRow(Decimal(0), 0), CostRow(Decimal(0), 0)],
        weeks=[[], []],
        durations=[DurationRow(None, None, 0), DurationRow(None, None, 0)],
        reschedules=[0, 0],
    )
    assert result.mix.preventive_pct is None and result.mix.change_pct is None
    assert result.compliance.compliance_pct is None and result.compliance.weeks == []
    assert (
        result.duration.variance_pct is None
        and result.duration.average_actual_hours is None
    )
    assert result.cost.average_per_record is None and result.cost.change_pct is None
    assert result.reschedules.change_pct is None


async def test_plan_compliance_is_per_week_with_an_overall_figure_and_trend():
    compliance = (await overview()).compliance
    assert [(w.planned, w.on_time, w.compliance_pct) for w in compliance.weeks] == [
        (5, 4, 80.0),
        (3, 3, 100.0),
    ]
    assert (compliance.planned, compliance.on_time, compliance.compliance_pct) == (
        8,
        7,
        87.5,
    )
    assert compliance.previous_compliance_pct == 50.0 and compliance.change_pct == 75.0
    assert compliance.sample_size == 8 and compliance.low_sample is False


@pytest.mark.parametrize(("planned", "low"), [(1, True), (4, True), (5, False)])
async def test_small_samples_are_flagged(planned, low):
    result = await overview(weeks=[[WeekRow(MONDAY, planned, planned)], []])
    assert result.compliance.low_sample is low


async def test_duration_reports_real_vs_estimated_as_a_variance():
    duration = (await overview()).duration
    assert (duration.average_actual_hours, duration.average_estimated_hours) == (
        3.0,
        2.0,
    )
    assert duration.variance_pct == 50.0  # took 50 % longer than estimated
    assert duration.previous_variance_pct == 0.0
    assert duration.sample_size == 7


async def test_cost_totals_with_an_average_and_a_trend():
    cost = (await overview()).cost
    assert cost.total == Decimal("300.50") and cost.previous_total == Decimal("200.00")
    assert (
        cost.change_pct == pytest.approx(50.25, abs=0.06)
        and cost.records_with_cost == 6
    )
    assert cost.average_per_record == Decimal("50.08")


async def test_reschedules_and_upcoming_counts():
    result = await overview()
    assert (result.reschedules.count, result.reschedules.previous) == (3, 6)
    assert result.reschedules.change_pct == -50.0
    assert (
        result.upcoming.overdue,
        result.upcoming.next_7_days,
        result.upcoming.next_30_days,
    ) == (2, 4, 9)


# -- calendar ------------------------------------------------------------------------------


def plan(schedule_id, due, interval=7, title="Limpieza"):
    return PlanRow(schedule_id, title, 1, "LT-1", "Luis", due, interval)


async def calendar(plans=(), runs=(), start=NOW, end=NOW + timedelta(days=30)):
    service = MaintenanceOverviewService(
        FakeOverviewRepository(plans=list(plans), runs=list(runs))
    )
    return await service.calendar(start=start, end=end, now=NOW)


async def test_a_plan_is_projected_one_interval_apart_inside_the_range():
    result = await calendar([plan(1, NOW + timedelta(days=2))])
    assert [e.at for e in result.events] == [
        NOW + timedelta(days=d) for d in (2, 9, 16, 23)
    ]
    assert {e.kind for e in result.events} == {"planned"}


async def test_an_overdue_plan_shows_its_overdue_date_then_continues_from_today():
    result = await calendar(
        [plan(1, NOW - timedelta(days=3))],
        start=NOW - timedelta(days=10),
        end=NOW + timedelta(days=10),
    )
    assert [(e.kind, e.at) for e in result.events] == [
        ("overdue", NOW - timedelta(days=3)),
        (
            "planned",
            NOW + timedelta(days=7),
        ),  # completing it today would set today + interval
    ]


async def test_a_long_overdue_plan_outside_the_window_still_projects_its_next_service():
    result = await calendar([plan(1, NOW - timedelta(days=90))])
    assert [e.kind for e in result.events] == [
        "planned",
        "planned",
        "planned",
        "planned",
    ]
    assert result.events[0].at == NOW + timedelta(days=7)


async def test_done_services_say_whether_they_were_on_time():
    due = NOW - timedelta(days=2)
    runs = [
        DoneRow(1, "Limpieza", 1, "LT-1", "Luis", due, due - timedelta(hours=5)),
        DoneRow(2, "Revisión", 1, "LT-2", None, due, due + timedelta(hours=5)),
    ]
    result = await calendar(
        runs=runs, start=NOW - timedelta(days=5), end=NOW + timedelta(days=1)
    )
    assert [(e.kind, e.on_time) for e in result.events] == [
        ("done", True),
        ("done", False),
    ]
    assert (
        result.events[0].completed_at is not None
        and result.events[1].technician is None
    )


async def test_events_are_sorted_and_capped():
    plans = [plan(i, NOW + timedelta(hours=i), interval=1) for i in range(1, 60)]
    result = await calendar(plans, end=NOW + timedelta(days=60))
    assert result.truncated is True and len(result.events) == 1500
    assert result.events == sorted(result.events, key=lambda e: (e.at, e.schedule_id))


@pytest.mark.parametrize(
    ("start", "end", "message"),
    [
        (NOW, NOW, "after its start"),
        (NOW, NOW - timedelta(days=1), "after its start"),
        (NOW, NOW + timedelta(days=MAX_CALENDAR_DAYS + 1), "exceed"),
    ],
)
async def test_the_calendar_range_must_be_coherent_and_bounded(start, end, message):
    with pytest.raises(UnprocessableError, match=message):
        await calendar(start=start, end=end)


# -- HTTP ----------------------------------------------------------------------------------


class StubOverviewService(MaintenanceOverviewService):
    def __init__(self):
        super().__init__(FakeOverviewRepository())
        self.calls = []

    async def overview(self, *, period, now=None):
        self.calls.append(("overview", period))
        return await super().overview(period=period, now=NOW)

    async def calendar(self, *, start, end, now=None):
        self.calls.append(("calendar", start, end))
        return await super().calendar(start=start, end=end, now=NOW)


def build_client(permissions):
    stub = StubOverviewService()
    user = SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                code="SUPERVISOR",
                is_active=True,
                permissions=perm_objects(*permissions),
            )
        ],
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user
    app.dependency_overrides[providers.get_maintenance_overview_service] = lambda: stub
    return stub


@pytest.fixture
def client():
    stub = build_client(["maintenance.read"])
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


def test_overview_endpoint_returns_the_documented_shape(client):
    response = client.get("/maintenance/overview?period=7d")
    assert response.status_code == 200
    assert set(response.json()) == {
        "generated_at",
        "period",
        "window_start",
        "window_end",
        "mix",
        "upcoming",
        "compliance",
        "duration",
        "cost",
        "reschedules",
    }
    assert client.stub.calls == [("overview", "7d")]


def test_overview_defaults_to_30_days_and_rejects_unknown_periods(client):
    assert client.get("/maintenance/overview").status_code == 200
    assert client.stub.calls[-1] == ("overview", "30d")
    assert client.get("/maintenance/overview?period=1y").status_code == 422


def test_calendar_endpoint_requires_aware_datetimes_and_a_coherent_range(client):
    ok = client.get(
        "/maintenance/calendar?start=2026-10-01T00:00:00Z&end=2026-11-01T00:00:00Z"
    )
    assert ok.status_code == 200 and set(ok.json()) == {
        "generated_at",
        "start",
        "end",
        "truncated",
        "events",
    }
    assert (
        client.get(
            "/maintenance/calendar?start=2026-10-01T00:00:00&end=2026-11-01T00:00:00Z"
        ).status_code
        == 422
    )
    assert (
        client.get("/maintenance/calendar?start=2026-10-01T00:00:00Z").status_code
        == 422
    )
    inverted = client.get(
        "/maintenance/calendar?start=2026-11-01T00:00:00Z&end=2026-10-01T00:00:00Z"
    )
    assert inverted.status_code == 422 and inverted.json()["code"] == "unprocessable"
    too_long = client.get(
        "/maintenance/calendar?start=2026-01-01T00:00:00Z&end=2026-12-31T00:00:00Z"
    )
    assert too_long.status_code == 422


@pytest.mark.parametrize(
    "path", ["overview", "calendar?start=2026-10-01T00:00:00Z&end=2026-10-10T00:00:00Z"]
)
def test_endpoints_need_maintenance_read(forbidden_client, path):
    assert forbidden_client.get(f"/maintenance/{path}").status_code == 403


# -- real-database aggregates (need TEST_DATABASE_URL) ------------------------------------------


async def seed(session):
    etype = EquipmentType(code="LAP", name="Laptop", is_active=True)
    user = User(clerk_user_id="c1", email="u@x.co", full_name="Luis", is_active=True)
    session.add_all([etype, user])
    await session.flush()
    laptop = Equipment(
        asset_tag="LT-1",
        equipment_type_id=etype.id,
        brand="Dell",
        model="X",
        status="assigned",
    )
    tech = Technician(user_id=user.id, is_available=True)
    session.add_all([laptop, tech])
    await session.flush()

    def plan(title, due_in_days, hours=None):
        return MaintenanceSchedule(
            equipment_id=laptop.id,
            technician_id=tech.id,
            title=title,
            interval_days=30,
            estimated_hours=hours,
            next_due_at=NOW + timedelta(days=due_in_days),
            is_active=True,
        )

    plans = [
        plan("vencido", -3, 2),
        plan("en 3 días", 3, 2),
        plan("en 20 días", 20),
        plan("lejano", 90),
    ]
    inactive = plan("inactivo", -10)
    inactive.is_active = False
    session.add_all([*plans, inactive])
    await session.flush()

    def record(work_type, days_ago, cost):
        started = NOW - timedelta(days=days_ago)
        return MaintenanceRecord(
            equipment_id=laptop.id,
            technician_id=tech.id,
            work_type=work_type,
            started_at=started,
            completed_at=started + timedelta(hours=1),
            diagnosis="d",
            actions_taken="a",
            result="ok",
            total_cost=Decimal(cost),
        )

    session.add_all(
        [
            record("preventive", 2, "100.00"),
            record("preventive", 5, "50.00"),
            record("corrective", 3, "0"),
            record("inspection", 4, "25.50"),
            record("corrective", 60, "999"),  # outside the 30-day window
        ]
    )
    due = NOW - timedelta(days=5)
    session.add_all(
        [
            ScheduleRun(
                schedule_id=plans[0].id,
                due_at=due,
                completed_at=due - timedelta(hours=1),
                actual_hours=Decimal(3),
            ),
            ScheduleRun(
                schedule_id=plans[1].id,
                due_at=due,
                completed_at=due + timedelta(hours=9),
                actual_hours=Decimal(1),
            ),
            ScheduleRun(
                schedule_id=plans[2].id, due_at=due, completed_at=due, actual_hours=None
            ),
            ScheduleReschedule(
                schedule_id=plans[0].id,
                old_due_at=due,
                new_due_at=NOW,
                changed_at=NOW - timedelta(days=1),
            ),
        ]
    )
    await session.flush()
    return plans


async def test_work_mix_and_cost_cover_only_the_window(db_session):
    await seed(db_session)
    repo = MaintenanceOverviewRepository(db_session)
    start, end = NOW - timedelta(days=30), NOW + timedelta(days=1)
    assert await repo.work_mix(start=start, end=end) == MixRow(
        preventive=2, corrective=1, other=1
    )
    cost = await repo.costs(start=start, end=end)
    assert cost.total == Decimal("175.50") and cost.with_cost == 3


async def test_upcoming_counts_active_plans_only(db_session):
    await seed(db_session)
    assert await MaintenanceOverviewRepository(db_session).upcoming(NOW) == UpcomingRow(
        1, 1, 2
    )


async def test_compliance_counts_done_runs_and_plans_still_overdue(db_session):
    await seed(db_session)
    weeks = await MaintenanceOverviewRepository(db_session).compliance_weeks(
        start=NOW - timedelta(days=30), end=NOW + timedelta(days=1), now=NOW
    )
    assert sum(w.planned for w in weeks) == 4  # 3 runs + the one plan still overdue
    assert (
        sum(w.on_time for w in weeks) == 2
    )  # early and exactly on the due date; one was late


async def test_duration_only_uses_runs_with_both_real_and_estimated_hours(db_session):
    await seed(db_session)
    row = await MaintenanceOverviewRepository(db_session).durations(
        start=NOW - timedelta(days=30), end=NOW + timedelta(days=1)
    )
    assert (
        row.count == 2
        and row.avg_actual == pytest.approx(2.0)
        and row.avg_estimated == pytest.approx(2.0)
    )


async def test_reschedules_are_counted_by_when_they_happened(db_session):
    await seed(db_session)
    repo = MaintenanceOverviewRepository(db_session)
    assert (
        await repo.reschedules(
            start=NOW - timedelta(days=7), end=NOW + timedelta(days=1)
        )
        == 1
    )
    assert (
        await repo.reschedules(
            start=NOW - timedelta(days=60), end=NOW - timedelta(days=30)
        )
        == 0
    )


async def test_calendar_queries_return_active_plans_and_the_runs_in_range(db_session):
    await seed(db_session)
    repo = MaintenanceOverviewRepository(db_session)
    plans = await repo.plans_due_before(NOW + timedelta(days=30), limit=50)
    assert [p.title for p in plans] == ["vencido", "en 3 días", "en 20 días"]
    runs = await repo.runs_between(NOW - timedelta(days=10), NOW, limit=50)
    assert len(runs) == 3 and runs[0].asset_tag == "LT-1"
