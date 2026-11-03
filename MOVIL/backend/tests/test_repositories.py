from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy.exc import IntegrityError

from app.core.pagination import PageParams
from app.models.audit import AuditLog
from app.models.auth import User
from app.models.equipment import Equipment, EquipmentType
from app.models.priority import Priority
from app.models.schedule import MaintenanceSchedule
from app.repositories.audit import AuditRepository
from app.repositories.base import BaseRepository, Page, escape_like
from app.repositories.equipment import EquipmentRepository
from app.repositories.priority import PriorityRepository
from app.repositories.schedule import ScheduleRepository


def test_escape_like_neutralises_wildcards():
    assert escape_like(" 50%_off\\ ") == "50\\%\\_off\\\\"


def test_page_computes_total_pages():
    assert Page(items=[], total=41, page=1, size=20).pages == 3
    assert Page(items=[], total=0, page=1, size=20).pages == 0


def test_apply_ordering_ignores_unknown_fields_and_uses_default():
    from sqlalchemy import select

    allowed = {"created_at": AuditLog.created_at}
    sql = str(
        BaseRepository.apply_ordering(
            select(AuditLog), "-drop_table", allowed, default=(AuditLog.id,)
        )
    )
    assert "ORDER BY audit_logs.id" in sql
    desc = str(BaseRepository.apply_ordering(select(AuditLog), "-created_at", allowed))
    assert "ORDER BY audit_logs.created_at DESC" in desc


async def _equipment(session, *, tag: str, brand: str = "Dell") -> Equipment:
    etype = EquipmentType(code=f"T-{tag}", name=f"Type {tag}", is_active=True)
    session.add(etype)
    await session.flush()
    item = Equipment(
        asset_tag=tag,
        equipment_type_id=etype.id,
        brand=brand,
        model="X1",
        status="active",
    )
    session.add(item)
    await session.flush()
    return item


async def test_paginate_returns_total_and_slices(db_session):
    repo = EquipmentRepository(db_session)
    for i in range(5):
        await _equipment(db_session, tag=f"AT-{i}")
    query = repo.apply_ordering(
        repo._equipment_query(), "asset_tag", {"asset_tag": Equipment.asset_tag}
    )
    page = await repo.paginate(query, page=2, size=2)
    assert page.total == 5
    assert [e.asset_tag for e in page.items] == ["AT-2", "AT-3"]
    assert page.pages == 3


async def test_equipment_search_treats_wildcards_literally(db_session):
    repo = EquipmentRepository(db_session)
    await _equipment(db_session, tag="AT-1", brand="100%Pure")
    await _equipment(db_session, tag="AT-2", brand="Other")
    assert [e.asset_tag for e in (await repo.list_equipment(search="%")).items] == [
        "AT-1"
    ]
    assert (await repo.list_equipment(search="at-")).total == 2


async def test_priority_fk_rejects_unknown_code(db_session):
    from app.models.maintenance import MaintenanceRequest

    eq = await _equipment(db_session, tag="AT-9")
    user = User(clerk_user_id="u1", email="a@b.co", full_name="A", is_active=True)
    db_session.add(user)
    db_session.add(Priority(code="low", name="Low", level=1, is_active=True))
    await db_session.flush()
    db_session.add(
        MaintenanceRequest(
            ticket_number="TCK-1",
            equipment_id=eq.id,
            requested_by_user_id=user.id,
            title="t",
            description="d",
            priority="nope",
            status="submitted",
        )
    )
    with pytest.raises(IntegrityError):
        await db_session.flush()


async def test_priority_repository_orders_by_level_and_filters_inactive(db_session):
    repo = PriorityRepository(db_session)
    db_session.add_all(
        [
            Priority(code="low", name="Low", level=1, is_active=True),
            Priority(code="high", name="High", level=3, is_active=True),
            Priority(code="old", name="Old", level=2, is_active=False),
        ]
    )
    await db_session.flush()
    assert [p.code for p in await repo.list()] == ["high", "low"]
    assert len(await repo.list(include_inactive=True)) == 3
    assert (await repo.get_by_code("high")).level == 3
    assert await repo.get_by_code("zzz") is None


async def test_audit_repository_records_and_filters(db_session):
    repo = AuditRepository(db_session)
    repo.record(
        user_id=None,
        action="equipment.created",
        entity_type="equipment",
        entity_id=7,
        new_values={"asset_tag": "AT-7"},
    )
    repo.record(
        user_id=None,
        action="equipment.updated",
        entity_type="equipment",
        entity_id=7,
        old_values={"status": "active"},
        new_values={"status": "retired"},
    )
    repo.record(
        user_id=None,
        action="maintenance.status_changed",
        entity_type="maintenance_request",
        entity_id=7,
    )
    await db_session.flush()
    page = await repo.search(
        entity_type="equipment", entity_id=7, params=PageParams(size=10)
    )
    assert page.total == 2
    assert page.items[0].action == "equipment.updated"  # newest first
    only = await repo.search(action="equipment.created")
    assert only.items[0].new_values == {"asset_tag": "AT-7"}
    future = await repo.search(date_from=datetime.now(UTC) + timedelta(days=1))
    assert future.total == 0


async def test_schedule_due_for_reminder_window(db_session):
    repo = ScheduleRepository(db_session)
    eq = await _equipment(db_session, tag="AT-S")
    now = datetime.now(UTC)

    def plan(title, due_in_days, **kw):
        return MaintenanceSchedule(
            equipment_id=eq.id,
            title=title,
            interval_days=30,
            remind_days_before=3,
            next_due_at=now + timedelta(days=due_in_days),
            is_active=True,
            **kw,
        )

    db_session.add_all(
        [
            plan("inside window", 2),
            plan("far away", 20),
            plan("already reminded", 2, last_reminded_at=now),
            plan(
                "inactive",
                1,
            ),
        ]
    )
    await db_session.flush()
    inactive = (await repo.search(search="inactive")).items[0]
    inactive.is_active = False
    await db_session.flush()
    due = await repo.list_due_for_reminder(now)
    assert [s.title for s in due] == ["inside window"]
    assert repo.next_due_after(now, 30) == now + timedelta(days=30)
