from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.authz import AuthContext
from app.core.config import Settings
from app.core.exceptions import BusinessRuleError, NotFoundError, UnprocessableError
from app.jobs import REMINDER_JOB_ID, build_scheduler, run_reminder_job
from app.main import app
from app.repositories.base import Page
from app.schemas.schedule import (
    ReminderRunResponse,
    ScheduleCreate,
    ScheduleResponse,
    ScheduleUpdate,
)
from app.services.reminders import ReminderService
from app.services.schedule import ScheduleService
from tests.support import perm_objects

NOW = datetime(2026, 10, 11, 12, 0, tzinfo=UTC)
ACTOR = AuthContext.for_roles(SimpleNamespace(id=9), "SUPERVISOR")


# -- payload validation -----------------------------------------------------------------


def create_payload(**overrides):
    data = {
        "equipment_id": 1,
        "title": "Clean servers",
        "interval_days": 90,
        "remind_days_before": 7,
        "first_due_at": "2026-12-01T09:00:00Z",
    }
    return ScheduleCreate(**{**data, **overrides})


@pytest.mark.parametrize(
    "overrides",
    [
        {"interval_days": 0},
        {"interval_days": 4000},
        {"remind_days_before": -1},
        {"remind_days_before": 100, "interval_days": 30},
        {"title": ""},
        {"first_due_at": "2026-12-01T09:00:00"},  # naive datetime
    ],
)
def test_schedule_payload_rejects_bad_values(overrides):
    with pytest.raises(ValidationError):
        create_payload(**overrides)


# -- ScheduleService (fakes) ----------------------------------------------------------------


class FakeScheduleRepository:
    def __init__(self):
        self.items = {}
        self.committed = 0
        self.runs = []
        self.reschedules = []

    def record_run(self, **kwargs):
        self.runs.append(kwargs)

    def record_reschedule(self, **kwargs):
        self.reschedules.append(kwargs)

    async def history(self, schedule_id, *, limit=50):
        runs = [
            SimpleNamespace(
                id=i + 1, **{k: v for k, v in run.items() if k != "user_id"}
            )
            for i, run in enumerate(self.runs)
        ]
        moves = [
            SimpleNamespace(
                id=i + 1,
                changed_at=NOW,
                **{k: v for k, v in m.items() if k != "user_id"},
            )
            for i, m in enumerate(self.reschedules)
        ]
        return runs, moves

    async def add_and_flush(self, entity):
        entity.id = len(self.items) + 1
        entity.created_at = NOW
        entity.last_reminded_at = None
        entity.equipment = SimpleNamespace(
            id=entity.equipment_id, asset_tag="SRV-1", brand="Dell", model="R450"
        )
        entity.technician = (
            SimpleNamespace(
                id=entity.technician_id,
                user_id=50,
                user=SimpleNamespace(full_name="Luis"),
            )
            if entity.technician_id
            else None
        )
        self.items[entity.id] = entity
        return entity

    async def get(self, schedule_id):
        return self.items.get(schedule_id)

    async def update_fields(self, entity, values):
        for key, value in values.items():
            setattr(entity, key, value)
        return entity

    async def search(self, **kwargs):
        self.search_kwargs = kwargs
        return Page(
            items=list(self.items.values()), total=len(self.items), page=1, size=20
        )

    def expire(self, entity, attributes):
        # the real session reloads the relationship from the new foreign key
        if "technician" in attributes:
            entity.technician = (
                SimpleNamespace(
                    id=entity.technician_id,
                    user_id=50,
                    user=SimpleNamespace(full_name="Luis"),
                )
                if entity.technician_id
                else None
            )

    async def flush(self):
        pass

    async def commit(self):
        self.committed += 1


class FakeEquipment:
    async def get(self, equipment_id):
        status = {1: "assigned", 3: "retired", 4: "lost"}.get(equipment_id)
        return SimpleNamespace(id=equipment_id, status=status) if status else None


class FakeTechnicians:
    async def get(self, technician_id):
        active = {2: True, 3: False}.get(technician_id)
        if active is None:
            return None
        return SimpleNamespace(id=technician_id, user=SimpleNamespace(is_active=active))


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


class ClockedScheduleService(ScheduleService):
    """Runs the service at a fixed `now` so the "not in the past" rule is deterministic."""

    async def create(self, payload, actor, *, now=None):
        return await super().create(payload, actor, now=now or NOW)

    async def update(self, schedule_id, payload, actor, *, now=None):
        return await super().update(schedule_id, payload, actor, now=now or NOW)


def schedule_service():
    return ClockedScheduleService(
        FakeScheduleRepository(), FakeEquipment(), FakeTechnicians(), FakeAudit()
    )


async def test_create_validates_references_and_audits():
    service = schedule_service()
    created = await service.create(create_payload(technician_id=2), ACTOR)
    assert created.technician.full_name == "Luis"
    assert created.next_due_at == datetime(2026, 12, 1, 9, tzinfo=UTC)
    assert service.audit.records[0]["action"] == "schedule.created"
    assert service.audit.records[0]["new_values"]["next_due_at"].startswith(
        "2026-12-01"
    )
    with pytest.raises(NotFoundError, match="equipment"):
        await service.create(create_payload(equipment_id=99), ACTOR)
    with pytest.raises(NotFoundError, match="technician"):
        await service.create(create_payload(technician_id=99), ACTOR)


async def test_update_records_old_and_new_values_and_rearms_the_reminder():
    service = schedule_service()
    created = await service.create(create_payload(), ACTOR)
    service.repository.items[created.id].last_reminded_at = NOW
    new_due = datetime(2027, 1, 15, tzinfo=UTC)
    updated = await service.update(
        created.id, ScheduleUpdate(next_due_at=new_due, title="Deep clean"), ACTOR
    )
    assert updated.title == "Deep clean" and updated.next_due_at == new_due
    assert updated.last_reminded_at is None
    record = service.audit.records[-1]
    assert record["old_values"]["title"] == "Clean servers"
    assert record["new_values"]["next_due_at"] == new_due.isoformat()


async def test_update_rejects_inconsistent_or_null_values():
    service = schedule_service()
    created = await service.create(create_payload(), ACTOR)
    with pytest.raises(UnprocessableError, match="cannot exceed"):
        await service.update(created.id, ScheduleUpdate(remind_days_before=120), ACTOR)
    with pytest.raises(UnprocessableError, match="cannot be null"):
        await service.update(created.id, ScheduleUpdate(title=None), ACTOR)
    with pytest.raises(NotFoundError):
        await service.update(404, ScheduleUpdate(title="x"), ACTOR)


async def test_update_can_clear_the_technician():
    service = schedule_service()
    created = await service.create(create_payload(technician_id=2), ACTOR)
    updated = await service.update(
        created.id, ScheduleUpdate(technician_id=None), ACTOR
    )
    assert updated.technician is None


@pytest.mark.parametrize(
    ("done_at", "expected_due"),
    [
        # early: counted from the old due date, so the interval is not shortened
        (datetime(2026, 11, 20, tzinfo=UTC), datetime(2027, 3, 1, 9, tzinfo=UTC)),
        # late: counted from now, so the plan is not left permanently overdue
        (datetime(2027, 1, 10, tzinfo=UTC), datetime(2027, 4, 10, tzinfo=UTC)),
    ],
)
async def test_complete_moves_the_due_date_one_interval_forward(done_at, expected_due):
    service = schedule_service()
    created = await service.create(create_payload(), ACTOR)
    done = await service.complete(created.id, ACTOR, now=done_at)
    assert done.next_due_at == expected_due
    assert done.last_reminded_at is None
    assert service.audit.records[-1]["action"] == "schedule.completed"


async def test_complete_rejects_inactive_plans():
    service = schedule_service()
    created = await service.create(create_payload(), ACTOR)
    await service.update(created.id, ScheduleUpdate(is_active=False), ACTOR)
    with pytest.raises(UnprocessableError, match="inactive"):
        await service.complete(created.id, ACTOR)


# -- ReminderService (fakes) ---------------------------------------------------------------------


def due(schedule_id, *, technician_user=50, creator=7, due_in_days=2):
    return SimpleNamespace(
        id=schedule_id,
        title="Clean servers",
        equipment_id=1,
        equipment=SimpleNamespace(asset_tag="SRV-1", brand="Dell", model="R450"),
        technician=SimpleNamespace(user_id=technician_user)
        if technician_user
        else None,
        created_by_user_id=creator,
        next_due_at=NOW + timedelta(days=due_in_days),
        last_reminded_at=None,
    )


class FakeReminderRepository:
    def __init__(self, schedules, lock=True):
        self.schedules = schedules
        self.lock = lock
        self.committed = False
        self.rolled_back = False

    async def try_acquire_reminder_lock(self):
        return self.lock

    async def list_due_for_reminder(self, now):
        return self.schedules

    async def commit(self):
        self.committed = True

    async def rollback(self):
        self.rolled_back = True


class FakeNotifications:
    def __init__(self):
        self.sent = []

    def notify(self, **kwargs):
        self.sent.append(kwargs)


def reminder_service(schedules, lock=True):
    return ReminderService(
        FakeReminderRepository(schedules, lock), FakeNotifications(), FakeAudit()
    )


async def test_reminders_go_to_the_technician_or_else_the_creator_and_mark_the_plan():
    schedules = [due(1), due(2, technician_user=None, creator=7)]
    service = reminder_service(schedules)
    result = await service.run(NOW)
    assert (result.reminders_sent, result.skipped_without_recipient) == (2, 0)
    assert [n["user_id"] for n in service.notifications.sent] == [50, 7]
    first = service.notifications.sent[0]
    assert first["notification_type"] == "maintenance_reminder"
    assert "due soon" in first["title"] and "2026-10-13" in first["message"]
    assert first["link_url"] == "/equipment/1"
    assert all(s.last_reminded_at == NOW for s in schedules)
    assert service.repository.committed
    assert {r["action"] for r in service.audit.records} == {"schedule.reminder_sent"}
    assert all(r["user_id"] is None for r in service.audit.records)  # system action


async def test_overdue_plans_say_so():
    service = reminder_service([due(1, due_in_days=-3)])
    await service.run(NOW)
    assert "overdue" in service.notifications.sent[0]["title"]


async def test_plans_with_nobody_to_notify_are_skipped_and_not_marked():
    orphan = due(1, technician_user=None, creator=None)
    service = reminder_service([orphan])
    result = await service.run(NOW)
    assert (result.reminders_sent, result.skipped_without_recipient) == (0, 1)
    assert orphan.last_reminded_at is None and not service.notifications.sent


async def test_a_worker_that_loses_the_lock_does_nothing():
    schedules = [due(1)]
    service = reminder_service(schedules, lock=False)
    result = await service.run(NOW)
    assert result.locked_by_another_worker and result.reminders_sent == 0
    assert not service.notifications.sent and schedules[0].last_reminded_at is None
    assert service.repository.rolled_back and not service.repository.committed


# -- real database: lock, due-window and idempotence ---------------------------------------------------


async def seed_schedule(session, *, due_in_days, remind=3, technician=True):
    from app.models.auth import User
    from app.models.equipment import Equipment, EquipmentType
    from app.models.schedule import MaintenanceSchedule
    from app.models.technician import Technician

    etype = EquipmentType(code="SRV", name="Server", is_active=True)
    user = User(
        clerk_user_id="t1", email="t@x.co", full_name="Tech One", is_active=True
    )
    session.add_all([etype, user])
    await session.flush()
    tech = Technician(user_id=user.id)
    equipment = Equipment(
        asset_tag="SRV-1",
        equipment_type_id=etype.id,
        brand="Dell",
        model="R450",
        status="assigned",
    )
    session.add_all([tech, equipment])
    await session.flush()
    schedule = MaintenanceSchedule(
        equipment_id=equipment.id,
        technician_id=tech.id if technician else None,
        created_by_user_id=user.id,
        title="Clean servers",
        interval_days=30,
        remind_days_before=remind,
        next_due_at=datetime.now(UTC) + timedelta(days=due_in_days),
        is_active=True,
    )
    session.add(schedule)
    await session.flush()
    return user, schedule


async def test_reminder_run_against_postgres_is_idempotent_and_rearms_after_completion(
    db_session,
):
    from sqlalchemy import select

    from app.jobs import build_reminder_service
    from app.models.audit import AuditLog
    from app.models.notification import Notification

    user, schedule = await seed_schedule(db_session, due_in_days=2)
    service = build_reminder_service(db_session)

    first = await service.run()
    assert (first.reminders_sent, first.locked_by_another_worker) == (1, False)
    notifications = (await db_session.execute(select(Notification))).scalars().all()
    assert [(n.user_id, n.notification_type) for n in notifications] == [
        (user.id, "maintenance_reminder")
    ]
    assert (
        await db_session.execute(select(AuditLog))
    ).scalars().one().action == "schedule.reminder_sent"

    second = await build_reminder_service(db_session).run()
    assert second.reminders_sent == 0  # already reminded for this due date

    # completing the service pushes the due date out: nothing to remind yet
    schedule.next_due_at = datetime.now(UTC) + timedelta(days=30)
    schedule.last_reminded_at = None
    await db_session.flush()
    assert (await build_reminder_service(db_session).run()).reminders_sent == 0


async def test_plans_outside_the_window_or_inactive_are_not_reminded(db_session):
    from app.jobs import build_reminder_service

    _, schedule = await seed_schedule(db_session, due_in_days=20, remind=3)
    assert (await build_reminder_service(db_session).run()).reminders_sent == 0
    schedule.next_due_at = datetime.now(UTC) + timedelta(days=1)
    schedule.is_active = False
    await db_session.flush()
    assert (await build_reminder_service(db_session).run()).reminders_sent == 0


async def test_advisory_lock_blocks_a_second_concurrent_worker(db_session):
    from sqlalchemy.ext.asyncio import AsyncSession

    from app.repositories.schedule import ScheduleRepository

    other = AsyncSession(bind=db_session.bind)
    try:
        assert await ScheduleRepository(db_session).try_acquire_reminder_lock() is True
        assert await ScheduleRepository(other).try_acquire_reminder_lock() is False
        await db_session.rollback()  # releases the transaction-scoped lock
        assert await ScheduleRepository(other).try_acquire_reminder_lock() is True
    finally:
        await other.rollback()
        await other.close()


async def test_changing_the_technician_is_reflected_in_the_response_against_postgres(
    db_session,
):
    from app.models.auth import User
    from app.models.technician import Technician
    from app.repositories.equipment import EquipmentRepository
    from app.repositories.schedule import ScheduleRepository
    from app.repositories.technician import TechnicianRepository

    _, schedule = await seed_schedule(db_session, due_in_days=5)
    other_user = User(
        clerk_user_id="t2", email="t2@x.co", full_name="Tech Two", is_active=True
    )
    db_session.add(other_user)
    await db_session.flush()
    other = Technician(user_id=other_user.id)
    db_session.add(other)
    await db_session.flush()

    service = ScheduleService(
        ScheduleRepository(db_session),
        EquipmentRepository(db_session),
        TechnicianRepository(db_session),
        FakeAudit(),
    )
    before = await service.get(schedule.id)
    assert before.technician.full_name == "Tech One"
    after = await service.update(
        schedule.id, ScheduleUpdate(technician_id=other.id), ACTOR
    )
    assert after.technician.full_name == "Tech Two"
    cleared = await service.update(
        schedule.id, ScheduleUpdate(technician_id=None), ACTOR
    )
    assert cleared.technician is None


# -- job wiring --------------------------------------------------------------------------------------------


def test_scheduler_registers_one_non_overlapping_reminder_job():
    settings = Settings(reminder_interval_minutes=15)
    scheduler = build_scheduler(settings, lambda: None)
    (job,) = scheduler.get_jobs()
    assert job.id == REMINDER_JOB_ID
    assert job.max_instances == 1 and job.coalesce is True
    assert job.trigger.interval == timedelta(minutes=15)


async def test_job_runner_uses_its_own_session_and_swallows_errors(monkeypatch):
    seen = {}

    @asynccontextmanager
    async def fake_session():
        seen["opened"] = True
        yield "session"

    class FakeService:
        async def run(self):
            return ReminderRunResponse(
                locked_by_another_worker=False,
                reminders_sent=3,
                skipped_without_recipient=0,
            )

    monkeypatch.setattr(
        "app.jobs.build_reminder_service", lambda session: FakeService()
    )
    result = await run_reminder_job(fake_session)
    assert seen["opened"] and result.reminders_sent == 3

    class Boom:
        async def run(self):
            raise RuntimeError("db down")

    monkeypatch.setattr("app.jobs.build_reminder_service", lambda session: Boom())
    assert await run_reminder_job(fake_session) is None  # logged, not raised


def test_lifespan_starts_and_stops_the_scheduler_only_when_enabled(monkeypatch):
    events = []

    class FakeScheduler:
        def start(self):
            events.append("start")

        def shutdown(self, wait=True):
            events.append(("shutdown", wait))

    monkeypatch.setattr(
        "app.main.build_scheduler", lambda settings, factory: FakeScheduler()
    )
    monkeypatch.setattr("app.main.async_session_maker", object())

    monkeypatch.setattr("app.main.settings", Settings(scheduler_enabled=True))
    with TestClient(app):
        assert events == ["start"]
    assert events == ["start", ("shutdown", False)]

    events.clear()
    monkeypatch.setattr("app.main.settings", Settings(scheduler_enabled=False))
    with TestClient(app):
        pass
    assert events == []


# -- HTTP -----------------------------------------------------------------------------------------------------


class StubScheduleService:
    def __init__(self):
        self.calls = []

    async def list(self, **kwargs):
        self.calls.append(("list", kwargs))
        return Page(items=[], total=0, page=1, size=20)

    async def complete(self, schedule_id, actor, actual_hours=None):
        self.calls.append(("complete", schedule_id, actual_hours))
        return ScheduleResponse(
            id=schedule_id,
            equipment={"id": 1, "asset_tag": "SRV-1", "brand": "Dell", "model": "R450"},
            technician=None,
            title="Clean servers",
            description=None,
            interval_days=90,
            remind_days_before=7,
            next_due_at=NOW,
            last_reminded_at=None,
            is_active=True,
            created_at=NOW,
        )


class StubReminderService:
    async def run(self):
        return ReminderRunResponse(
            locked_by_another_worker=False,
            reminders_sent=2,
            skipped_without_recipient=1,
        )


@pytest.fixture
def client():
    schedules = StubScheduleService()
    user = SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                code="SUPERVISOR",
                is_active=True,
                permissions=perm_objects("maintenance.read", "schedules.manage"),
            )
        ],
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user
    app.dependency_overrides[providers.get_schedule_service] = lambda: schedules
    app.dependency_overrides[providers.get_reminder_service] = lambda: (
        StubReminderService()
    )
    with TestClient(app, raise_server_exceptions=False) as test_client:
        test_client.schedules = schedules
        yield test_client
    app.dependency_overrides.clear()


def test_list_endpoint_forwards_filters_and_sets_page_headers(client):
    response = client.get(
        "/maintenance/schedules?equipment_id=3&is_active=true&search=clean&sort=title"
    )
    assert response.status_code == 200
    assert response.headers["X-Total-Count"] == "0"
    kwargs = client.schedules.calls[0][1]
    assert (kwargs["equipment_id"], kwargs["is_active"], kwargs["search"]) == (
        3,
        True,
        "clean",
    )
    assert kwargs["params"].sort == "title"


def test_run_reminders_is_not_shadowed_by_the_id_route(client):
    response = client.post("/maintenance/schedules/run-reminders")
    assert response.status_code == 200
    assert response.json() == {
        "locked_by_another_worker": False,
        "reminders_sent": 2,
        "skipped_without_recipient": 1,
    }


def test_complete_endpoint_and_validation_errors(client):
    assert client.post("/maintenance/schedules/4/complete").status_code == 200
    assert client.schedules.calls[-1] == ("complete", 4, None)
    bad = client.post(
        "/maintenance/schedules",
        json={
            "equipment_id": 1,
            "title": "x",
            "interval_days": 0,
            "first_due_at": "2026-12-01T00:00:00Z",
        },
    )
    assert bad.status_code == 422
    assert any(e["field"] == "interval_days" for e in bad.json()["errors"])


# -- phase 2: validations, runs and reschedules ----------------------------------------------


@pytest.mark.parametrize(
    "overrides",
    [
        {"estimated_hours": "0"},
        {"estimated_hours": "-1"},
        {"estimated_hours": "1000"},
        {"estimated_hours": "1.234"},
        {"title": "   "},
    ],
)
def test_create_rejects_bad_hours_and_blank_titles(overrides):
    with pytest.raises(ValidationError):
        create_payload(**overrides)


def test_create_trims_text_and_keeps_two_decimals():
    payload = create_payload(
        title="  Limpieza  ", description="   ", estimated_hours="1.5"
    )
    assert payload.title == "Limpieza" and payload.description is None
    assert str(payload.estimated_hours) == "1.5"


async def test_cannot_schedule_in_the_past_but_right_now_is_fine():
    service = schedule_service()
    with pytest.raises(UnprocessableError, match="in the past"):
        await service.create(create_payload(first_due_at="2026-10-11T11:59:00Z"), ACTOR)
    created = await service.create(
        create_payload(first_due_at="2026-10-11T12:00:00Z"), ACTOR
    )
    assert created.next_due_at == NOW


@pytest.mark.parametrize("equipment_id", [3, 4])
async def test_no_plan_for_retired_or_lost_equipment(equipment_id):
    with pytest.raises(BusinessRuleError, match="cannot schedule"):
        await schedule_service().create(
            create_payload(equipment_id=equipment_id), ACTOR
        )


async def test_cannot_assign_a_plan_to_an_inactive_technician():
    with pytest.raises(BusinessRuleError, match="inactive"):
        await schedule_service().create(create_payload(technician_id=3), ACTOR)


async def test_moving_the_due_date_is_recorded_with_its_reason():
    service = schedule_service()
    created = await service.create(create_payload(), ACTOR)
    new_due = datetime(2027, 2, 1, 9, tzinfo=UTC)
    await service.update(
        created.id,
        ScheduleUpdate(next_due_at=new_due, reschedule_reason="  Equipo en uso  "),
        ACTOR,
    )
    (move,) = service.repository.reschedules
    assert move["old_due_at"] == datetime(2026, 12, 1, 9, tzinfo=UTC)
    assert move["new_due_at"] == new_due and move["reason"] == "Equipo en uso"
    assert move["user_id"] == ACTOR.id


async def test_a_reason_without_a_new_date_is_rejected_and_the_same_date_is_not_a_move():
    service = schedule_service()
    created = await service.create(create_payload(), ACTOR)
    with pytest.raises(UnprocessableError, match="needs a new next_due_at"):
        await service.update(
            created.id, ScheduleUpdate(reschedule_reason="porque sí"), ACTOR
        )
    await service.update(
        created.id,
        ScheduleUpdate(next_due_at=datetime(2026, 12, 1, 9, tzinfo=UTC)),
        ACTOR,
    )
    assert service.repository.reschedules == []


async def test_cannot_reschedule_into_the_past():
    service = schedule_service()
    created = await service.create(create_payload(), ACTOR)
    with pytest.raises(UnprocessableError, match="in the past"):
        await service.update(
            created.id,
            ScheduleUpdate(next_due_at=datetime(2026, 10, 1, tzinfo=UTC)),
            ACTOR,
        )
    assert service.repository.reschedules == []


async def test_other_edits_do_not_create_reschedules():
    service = schedule_service()
    created = await service.create(create_payload(), ACTOR)
    await service.update(
        created.id, ScheduleUpdate(title="Otro", estimated_hours="2"), ACTOR
    )
    assert service.repository.reschedules == []


async def test_completing_records_a_run_with_the_old_due_date_and_real_hours():
    service = schedule_service()
    created = await service.create(create_payload(), ACTOR)
    done_at = datetime(2026, 11, 20, tzinfo=UTC)
    await service.complete(created.id, ACTOR, actual_hours="1.75", now=done_at)
    (run,) = service.repository.runs
    assert run["due_at"] == datetime(2026, 12, 1, 9, tzinfo=UTC)
    assert run["completed_at"] == done_at and run["actual_hours"] == "1.75"
    history = await service.history(created.id)
    assert history.runs[0].on_time is True  # done before it was due


async def test_a_late_completion_is_not_on_time():
    service = schedule_service()
    created = await service.create(create_payload(), ACTOR)
    await service.complete(created.id, ACTOR, now=datetime(2026, 12, 5, tzinfo=UTC))
    assert (await service.history(created.id)).runs[0].on_time is False


async def test_history_of_a_missing_plan_is_a_404():
    with pytest.raises(NotFoundError):
        await schedule_service().history(404)


@pytest.mark.parametrize(
    ("due_from", "due_to", "message"),
    [
        (datetime(2026, 11, 1, tzinfo=UTC), datetime(2026, 10, 1, tzinfo=UTC), "after"),
        (datetime(2026, 11, 1, tzinfo=UTC), datetime(2026, 11, 1, tzinfo=UTC), "after"),
        (datetime(2025, 1, 1, tzinfo=UTC), datetime(2026, 11, 1, tzinfo=UTC), "exceed"),
    ],
)
async def test_list_rejects_inverted_or_huge_due_ranges(due_from, due_to, message):
    with pytest.raises(UnprocessableError, match=message):
        await schedule_service().list(due_from=due_from, due_to=due_to)


async def test_list_passes_the_new_filters_and_the_overdue_moment():
    service = schedule_service()
    await service.list(technician_id=2, overdue=True, now=NOW)
    kwargs = service.repository.search_kwargs
    assert kwargs["technician_id"] == 2 and kwargs["overdue_at"] == NOW
    await service.list(now=NOW)
    assert service.repository.search_kwargs["overdue_at"] is None


def test_complete_accepts_the_real_hours_and_rejects_bad_ones(client):
    ok = client.post("/maintenance/schedules/4/complete", json={"actual_hours": "1.50"})
    assert ok.status_code == 200
    assert str(client.schedules.calls[-1][2]) == "1.50"
    for bad in ("0", "-2", "1000", "1.234", "abc"):
        response = client.post(
            "/maintenance/schedules/4/complete", json={"actual_hours": bad}
        )
        assert response.status_code == 422, bad


def test_list_endpoint_forwards_the_new_filters(client):
    response = client.get(
        "/maintenance/schedules?technician_id=2&overdue=true"
        "&due_from=2026-10-01T00:00:00Z&due_to=2026-11-01T00:00:00Z"
    )
    assert response.status_code == 200
    kind, kwargs = client.schedules.calls[-1]
    assert kind == "list"
    assert kwargs["technician_id"] == 2 and kwargs["overdue"] is True
    assert kwargs["due_from"] == datetime(2026, 10, 1, tzinfo=UTC)
    assert (
        client.get("/maintenance/schedules?due_from=2026-10-01T00:00:00").status_code
        == 422
    )  # naive
