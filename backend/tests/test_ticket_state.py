from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from app.core.exceptions import BusinessRuleError
from app.domain.ticket_state import TicketState

NOW = datetime(2026, 1, 1, tzinfo=timezone.utc)

ALL_STATUSES = [
    "submitted", "triaged", "assigned", "in_progress",
    "waiting", "resolved", "closed", "cancelled",
]  # fmt: skip


def ticket(status):
    return SimpleNamespace(
        status=status, resolution_summary=None, resolved_at=None, closed_at=None
    )


@pytest.mark.parametrize(
    ("current", "target"),
    [
        ("submitted", "triaged"),
        ("triaged", "assigned"),
        ("assigned", "in_progress"),
        ("in_progress", "waiting"),
        ("in_progress", "resolved"),
        ("waiting", "in_progress"),
        ("resolved", "closed"),
        ("resolved", "in_progress"),
        ("waiting", "cancelled"),
    ],
)
def test_allowed_transitions(current, target):
    t = ticket(current)
    TicketState.of(current).transition(t, target, now=NOW)
    assert t.status == target


@pytest.mark.parametrize("current", ["closed", "cancelled"])
@pytest.mark.parametrize("target", ALL_STATUSES)
def test_terminal_states_reject_every_transition(current, target):
    with pytest.raises(BusinessRuleError):
        TicketState.of(current).transition(ticket(current), target, now=NOW)


def test_skipping_states_is_rejected():
    with pytest.raises(BusinessRuleError, match="submitted' to 'closed"):
        TicketState.of("submitted").transition(ticket("submitted"), "closed", now=NOW)


def test_resolved_entry_stamps_time_and_summary():
    t = ticket("in_progress")
    TicketState.of("in_progress").transition(
        t, "resolved", now=NOW, resolution_summary="Replaced PSU"
    )
    assert t.resolved_at == NOW
    assert t.resolution_summary == "Replaced PSU"
    assert t.closed_at is None


def test_closed_entry_stamps_closed_at():
    t = ticket("resolved")
    TicketState.of("resolved").transition(t, "closed", now=NOW)
    assert t.closed_at == NOW


def test_only_resolved_and_closed_notify_requester():
    notifying = {s for s in ALL_STATUSES if TicketState.of(s).notifies_requester}
    assert notifying == {"resolved", "closed"}


def test_assignment_auto_advances_only_from_intake_states():
    advancing = {s: TicketState.of(s).status_after_assignment() for s in ALL_STATUSES}
    assert advancing["submitted"] == "assigned"
    assert advancing["triaged"] == "assigned"
    assert all(
        v is None for s, v in advancing.items() if s not in {"submitted", "triaged"}
    )


@pytest.mark.parametrize("status", ["closed", "cancelled"])
def test_terminal_states_refuse_assignment(status):
    with pytest.raises(BusinessRuleError):
        TicketState.of(status).ensure_accepts_assignment()


def test_unknown_status_is_a_business_rule_error():
    with pytest.raises(BusinessRuleError):
        TicketState.of("bogus")


def test_assign_technician_advances_intake_states_outside_the_transition_graph():
    t = ticket("submitted")
    assert TicketState.of("submitted").assign_technician(t, now=NOW) == "assigned"
    assert t.status == "assigned"


def test_assign_technician_leaves_active_states_untouched():
    t = ticket("in_progress")
    assert TicketState.of("in_progress").assign_technician(t, now=NOW) is None
    assert t.status == "in_progress"
