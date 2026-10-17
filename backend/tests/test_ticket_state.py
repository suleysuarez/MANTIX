from datetime import UTC, datetime
from types import SimpleNamespace

import pytest

from app.core.exceptions import BusinessRuleError, InvalidTransitionError
from app.domain.ticket_state import TicketState

NOW = datetime(2026, 1, 1, tzinfo=UTC)

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
        ("submitted", "cancelled"),
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
    TicketState.of(current).transition(t, target, now=NOW, has_technician=True)
    assert t.status == target


@pytest.mark.parametrize("current", ["closed", "cancelled"])
@pytest.mark.parametrize("target", ALL_STATUSES)
def test_terminal_states_reject_every_transition(current, target):
    with pytest.raises(InvalidTransitionError):
        TicketState.of(current).transition(
            ticket(current), target, now=NOW, has_technician=True
        )


def test_skipping_states_is_rejected():
    with pytest.raises(InvalidTransitionError, match="submitted' to 'closed"):
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


@pytest.mark.parametrize("status", ["closed", "cancelled"])
def test_terminal_states_refuse_assignment(status):
    with pytest.raises(InvalidTransitionError):
        TicketState.of(status).ensure_accepts_assignment()


def test_unknown_status_is_a_business_rule_error():
    with pytest.raises(BusinessRuleError):
        TicketState.of("bogus")


@pytest.mark.parametrize("current", ["submitted", "triaged"])
def test_assigned_is_an_explicit_edge_from_intake_states(current):
    assert TicketState.of(current).can_transition_to("assigned")


def test_only_assigned_requires_a_technician():
    required = {s for s in ALL_STATUSES if TicketState.of(s).requires_technician}
    assert required == {"assigned"}


@pytest.mark.parametrize("current", ["submitted", "triaged"])
def test_moving_to_assigned_without_technician_is_rejected(current):
    t = ticket(current)
    with pytest.raises(InvalidTransitionError, match="without an assigned technician"):
        TicketState.of(current).transition(t, "assigned", now=NOW)
    assert t.status == current


@pytest.mark.parametrize("current", ["submitted", "triaged"])
def test_assign_technician_goes_through_the_guarded_transition(current):
    t = ticket(current)
    new_state = TicketState.of(current).assign_technician(t, now=NOW)
    assert new_state.status == "assigned"
    assert t.status == "assigned"


@pytest.mark.parametrize("status", ["assigned", "in_progress", "waiting", "resolved"])
def test_assign_technician_keeps_status_of_later_open_states(status):
    state = TicketState.of(status)
    t = ticket(status)
    assert state.assign_technician(t, now=NOW) is state
    assert t.status == status


@pytest.mark.parametrize("status", ["closed", "cancelled"])
def test_assign_technician_rejected_on_terminal_states(status):
    with pytest.raises(InvalidTransitionError):
        TicketState.of(status).assign_technician(ticket(status), now=NOW)


# -- workflow metadata for boards ------------------------------------------------------------


def test_workflow_lists_every_state_in_order_with_what_must_be_supplied():
    flow = TicketState.workflow()
    assert [s.status for s in flow] == [
        "submitted",
        "triaged",
        "assigned",
        "in_progress",
        "waiting",
        "resolved",
        "closed",
        "cancelled",
    ]
    requires = {s.status: s.requires for s in flow}
    assert requires["triaged"] == ("category", "priority")
    assert requires["assigned"] == ("technician",)
    assert requires["resolved"] == ("resolution_summary",)
    assert requires["cancelled"] == ("reason",)
    assert requires["in_progress"] == () and requires["closed"] == ()


def test_workflow_endpoint_mirrors_the_state_machine_and_needs_read_permission():
    from types import SimpleNamespace

    from fastapi.testclient import TestClient

    from app.api.dependencies import get_authenticated_user
    from app.main import app

    def user(permissions):
        role = SimpleNamespace(
            code="ADMIN",
            is_active=True,
            permissions=[SimpleNamespace(code=c, is_active=True) for c in permissions],
        )
        return SimpleNamespace(id=1, full_name="Ana", roles=[role])

    try:
        app.dependency_overrides[get_authenticated_user] = lambda: user(
            ["maintenance.read"]
        )
        with TestClient(app) as client:
            body = client.get("/maintenance/requests/workflow").json()
        assert body[0]["status"] == "submitted"
        by_status = {s["status"]: s for s in body}
        assert by_status["submitted"]["allowed_targets"] == [
            "assigned",
            "cancelled",
            "triaged",
        ]
        assert (
            by_status["closed"]["terminal"] is True
            and by_status["cancelled"]["terminal"] is True
        )
        assert by_status["in_progress"]["terminal"] is False
        app.dependency_overrides[get_authenticated_user] = lambda: user([])
        with TestClient(app) as client:
            assert client.get("/maintenance/requests/workflow").status_code == 403
    finally:
        app.dependency_overrides.clear()
