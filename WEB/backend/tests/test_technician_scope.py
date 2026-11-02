"""A technician sees the maintenance figures and plans of their own work only; a supervisor sees all."""

from datetime import UTC, datetime, timedelta

import pytest

from app.core.authz import SUPERVISOR, TECHNICIAN, AuthContext
from app.core.exceptions import NotFoundError
from app.core.permissions import effective_for_system_roles
from app.models.auth import User
from app.models.equipment import Equipment, EquipmentType
from app.models.maintenance import MaintenanceRecord
from app.models.schedule import MaintenanceSchedule
from app.models.technician import Technician
from app.repositories.audit import AuditRepository
from app.repositories.equipment import EquipmentRepository
from app.repositories.maintenance_overview import MaintenanceOverviewRepository
from app.repositories.schedule import ScheduleRepository
from app.repositories.technician import TechnicianRepository
from app.services.audit import AuditService
from app.services.maintenance_overview import MaintenanceOverviewService
from app.services.schedule import ScheduleService

NOW = datetime(2026, 10, 15, 12, tzinfo=UTC)


@pytest.fixture
async def world(db_session):
    session = db_session
    etype = EquipmentType(code="LAP", name="Laptop", is_active=True)
    ana = User(email="ana@x.co", full_name="Ana", is_active=True)
    beto = User(email="beto@x.co", full_name="Beto", is_active=True)
    boss = User(email="boss@x.co", full_name="Jefe", is_active=True)
    nobody = User(email="nadie@x.co", full_name="Nadie", is_active=True)
    session.add_all([etype, ana, beto, boss, nobody])
    await session.flush()
    laptop = Equipment(
        asset_tag="LT-1",
        equipment_type_id=etype.id,
        brand="D",
        model="X",
        status="assigned",
    )
    t_ana, t_beto = Technician(user_id=ana.id), Technician(user_id=beto.id)
    session.add_all([laptop, t_ana, t_beto])
    await session.flush()

    def plan(title, technician, days):
        return MaintenanceSchedule(
            equipment_id=laptop.id,
            technician_id=technician.id,
            title=title,
            interval_days=30,
            next_due_at=NOW + timedelta(days=days),
            remind_days_before=3,
            is_active=True,
        )

    plans = [
        plan("Plan de Ana", t_ana, 3),
        plan("Plan de Beto", t_beto, 4),
        plan("Vencido de Beto", t_beto, -2),
    ]
    session.add_all(plans)
    session.add_all(
        [
            MaintenanceRecord(
                equipment_id=laptop.id,
                technician_id=t.id,
                work_type="preventive",
                started_at=NOW - timedelta(days=2),
                diagnosis="d",
                actions_taken="a",
                result="ok",
                total_cost=cost,
            )
            for t, cost in [(t_ana, 10), (t_beto, 100), (t_beto, 200)]
        ]
    )
    await session.commit()
    overview = MaintenanceOverviewService(MaintenanceOverviewRepository(session))
    schedules = ScheduleService(
        ScheduleRepository(session),
        EquipmentRepository(session),
        TechnicianRepository(session),
        AuditService(AuditRepository(session)),
    )
    return (
        overview,
        schedules,
        plans,
        {"ana": ana, "beto": beto, "boss": boss, "nobody": nobody},
    )


def as_tech(user):
    return AuthContext(
        user=user,
        roles=frozenset({TECHNICIAN}),
        permissions=effective_for_system_roles(TECHNICIAN),
    )


def as_boss(user):
    return AuthContext.for_roles(user, SUPERVISOR)


async def test_the_overview_counts_only_the_technicians_own_work(world):
    overview, _, _, users = world
    mine = await overview.technician_scope(as_tech(users["ana"]))
    assert mine is not None
    figures = await overview.overview(period="30d", now=NOW, technician_id=mine)
    assert figures.mix.sample_size == 1
    assert float(figures.cost.total) == 10
    assert figures.upcoming.overdue == 0

    other = await overview.technician_scope(as_tech(users["beto"]))
    theirs = await overview.overview(period="30d", now=NOW, technician_id=other)
    assert theirs.mix.sample_size == 2 and float(theirs.cost.total) == 300
    assert theirs.upcoming.overdue == 1


async def test_a_supervisor_is_not_restricted(world):
    overview, _, _, users = world
    assert await overview.technician_scope(as_boss(users["boss"])) is None
    figures = await overview.overview(period="30d", now=NOW, technician_id=None)
    assert figures.mix.sample_size == 3 and float(figures.cost.total) == 310


async def test_a_technician_without_a_profile_sees_nothing(world):
    overview, _, _, users = world
    scope = await overview.technician_scope(as_tech(users["nobody"]))
    figures = await overview.overview(period="30d", now=NOW, technician_id=scope)
    assert figures.mix.sample_size == 0 and float(figures.cost.total) == 0


async def test_the_calendar_shows_only_the_technicians_plans(world):
    overview, _, _, users = world
    mine = await overview.technician_scope(as_tech(users["ana"]))
    start, end = NOW - timedelta(days=10), NOW + timedelta(days=20)
    own = await overview.calendar(start=start, end=end, now=NOW, technician_id=mine)
    assert {e.title for e in own.events} == {"Plan de Ana"}
    everyone = await overview.calendar(start=start, end=end, now=NOW)
    assert {"Plan de Ana", "Plan de Beto"} <= {e.title for e in everyone.events}


async def test_the_plan_list_and_detail_are_limited_to_the_technician(world):
    _, schedules, plans, users = world
    ana = as_tech(users["ana"])
    page = await schedules.list(actor=ana)
    assert [item.title for item in page.items] == ["Plan de Ana"]
    # asking for someone else's plans through the filter does not widen the result
    page = await schedules.list(actor=ana, technician_id=plans[1].technician_id)
    assert [item.title for item in page.items] == ["Plan de Ana"]

    assert (await schedules.get(plans[0].id, ana)).title == "Plan de Ana"
    with pytest.raises(NotFoundError):
        await schedules.get(plans[1].id, ana)
    with pytest.raises(NotFoundError):
        await schedules.history(plans[1].id, ana)

    boss = as_boss(users["boss"])
    assert len((await schedules.list(actor=boss)).items) == 3
    assert (await schedules.get(plans[1].id, boss)).title == "Plan de Beto"


def test_the_technician_no_longer_has_the_technicians_list_but_the_supervisor_does():
    assert "tecnicos:ver" not in effective_for_system_roles(TECHNICIAN)
    assert "tecnicos:ver" in effective_for_system_roles(SUPERVISOR)


def test_a_technician_exports_tickets_but_cannot_create_them_or_export_other_reports():
    from types import SimpleNamespace

    from app.core.exceptions import ForbiddenError
    from app.services.export import ExportService

    tech = AuthContext.for_roles(SimpleNamespace(id=1), TECHNICIAN)
    service = ExportService(None, None)  # type: ignore[arg-type]
    assert service.options("tickets", tech).report == "tickets"
    with pytest.raises(ForbiddenError):
        service.options("technicians", tech)
    assert "solicitudes:crear" not in tech.permissions
