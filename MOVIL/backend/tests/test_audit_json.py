"""Audit values reach a JSONB column: money, dates and enums must be converted, not crash.

Regression: editing equipment with a purchase cost or a date, or a technician with an hourly
rate, answered 500 because the audit row could not store a `Decimal` or a `date`.
"""

from datetime import UTC, date, datetime
from decimal import Decimal
from enum import StrEnum

from sqlalchemy import select

from app.models.audit import AuditLog
from app.models.auth import User
from app.repositories.audit import AuditRepository, _as_json


class Kind(StrEnum):
    A = "a"


def test_money_dates_and_enums_become_plain_json():
    values = {
        "purchase_cost": Decimal("999.99"),
        "purchase_date": date(2026, 2, 1),
        "when": datetime(2026, 10, 15, 12, 0, tzinfo=UTC),
        "kind": Kind.A,
        "nested": {"rate": Decimal("30.25")},
        "plain": "x",
        "none": None,
    }
    assert _as_json(values) == {
        "purchase_cost": 999.99,
        "purchase_date": "2026-02-01",
        "when": "2026-10-15T12:00:00+00:00",
        "kind": "a",
        "nested": {"rate": 30.25},
        "plain": "x",
        "none": None,
    }


def test_nothing_stays_nothing():
    assert _as_json(None) is None
    assert _as_json({}) == {}


async def test_an_audit_row_with_a_cost_and_a_date_is_stored_and_read_back(db_session):
    user = User(email="a@x.co", full_name="Ana", is_active=True)
    db_session.add(user)
    await db_session.flush()

    AuditRepository(db_session).record(
        user_id=user.id,
        action="equipment.updated",
        entity_type="equipment",
        entity_id=3,
        old_values={"status": "in_storage"},
        new_values={
            "purchase_cost": Decimal("999.99"),
            "purchase_date": date(2026, 2, 1),
        },
    )
    await db_session.flush()

    row = (await db_session.execute(select(AuditLog))).scalar_one()
    assert row.new_values == {"purchase_cost": 999.99, "purchase_date": "2026-02-01"}
    assert row.old_values == {"status": "in_storage"}
