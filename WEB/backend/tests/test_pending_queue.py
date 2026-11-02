from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.api import providers
from app.api.dependencies import get_authenticated_user
from app.core.exceptions import (
    BusinessRuleError,
    ForbiddenError,
    NotFoundError,
    UnprocessableError,
)
from app.core.scope import DataScope
from app.main import app
from app.models.auth import User
from app.models.category import RequestCategory
from app.models.equipment import Equipment, EquipmentType
from app.models.maintenance import MaintenanceRequest, TicketStatusHistory
from app.models.priority import Priority
from app.repositories.dashboard import CountRow
from app.repositories.maintenance import MaintenanceRepository
from app.repositories.queue import DecisionStats, QueueRepository, WaitStats
from app.schemas.maintenance import (
    MaintenanceClassifyRequest,
    MaintenanceRejectRequest,
    MaintenanceRequestCreate,
    MaintenanceStatusTransitionRequest,
    TicketAssignmentCreateRequest,
)
from app.services.queue import QueueService
from tests.support import perm_objects
from tests.test_maintenance import (
    create_ticket,
    make_actor,
    make_technician,
    service_with_fakes,
)

NOW = datetime(2026, 10, 14, 12, 0, tzinfo=UTC)
ADMIN = make_actor(1, role_codes=("ADMIN",))


# -- schema validation ----------------------------------------------------------


@pytest.mark.parametrize("reason", ["", "    ", "abcd", "  ab  "])
def test_reject_reason_needs_five_real_characters(reason):
    with pytest.raises(ValidationError):
        MaintenanceRejectRequest(reason=reason)


def test_reject_reason_is_trimmed_and_capped():
    assert MaintenanceRejectRequest(reason="  Duplicado  ").reason == "Duplicado"
    with pytest.raises(ValidationError):
        MaintenanceRejectRequest(reason="x" * 501)


@pytest.mark.parametrize("field", ["title", "description"])
def test_create_rejects_blank_text_and_trims_the_rest(field):
    base = {"equipment_id": 1, "title": "  Pantalla  ", "description": " Rota "}
    assert MaintenanceRequestCreate(**base).title == "Pantalla"
    with pytest.raises(ValidationError):
        MaintenanceRequestCreate(**{**base, field: "   "})


@pytest.mark.parametrize("category", ["Hardware", "1net", "a", "x" * 31, "has space"])
def test_create_rejects_malformed_category_codes(category):
    with pytest.raises(ValidationError):
        MaintenanceRequestCreate(
            equipment_id=1, title="t", description="d", category=category
        )


# -- maintenance service (fake repository) --------------------------------------


async def test_create_with_a_known_category_keeps_it():
    service = service_with_fakes()
    response = await service.create_request(
        MaintenanceRequestCreate(
            equipment_id=1, title="t", description="d", category="network"
        ),
        make_actor(100),
    )
    assert response.category == "network"


async def test_create_with_an_unknown_category_is_a_404():
    service = service_with_fakes()
    with pytest.raises(NotFoundError, match="category"):
        await service.create_request(
            MaintenanceRequestCreate(
                equipment_id=1, title="t", description="d", category="unknown"
            ),
            make_actor(100),
        )


async def test_reject_cancels_with_the_reason_in_the_history_and_audit():
    service = service_with_fakes()
    created = await create_ticket(service)
    rejected = await service.reject_request(created.id, "Duplicado del TCK-1", ADMIN)
    assert rejected.status == "cancelled"
    last = rejected.status_history[-1]
    assert (last.from_status, last.to_status) == ("submitted", "cancelled")
    assert last.notes == "Rechazada: Duplicado del TCK-1"
    assert service.audit.records[-1]["action"] == "maintenance.status_changed"


@pytest.mark.parametrize("status", ["submitted", "triaged", "assigned"])
async def test_reject_works_until_work_starts(status):
    service = service_with_fakes(technicians=[make_technician(1, user_id=10)])
    created = await create_ticket(service)
    if status == "triaged":
        await service.transition_status(
            created.id, MaintenanceStatusTransitionRequest(status="triaged"), ADMIN
        )
    if status == "assigned":
        await service.assign_technician(
            created.id, TicketAssignmentCreateRequest(technician_id=1), ADMIN
        )
    assert (
        await service.reject_request(created.id, "Fuera de alcance", ADMIN)
    ).status == "cancelled"


async def test_reject_after_work_started_is_a_409():
    service = service_with_fakes(technicians=[make_technician(1, user_id=10)])
    created = await create_ticket(service)
    await service.assign_technician(
        created.id, TicketAssignmentCreateRequest(technician_id=1), ADMIN
    )
    await service.transition_status(
        created.id, MaintenanceStatusTransitionRequest(status="in_progress"), ADMIN
    )
    with pytest.raises(BusinessRuleError, match="have not started"):
        await service.reject_request(created.id, "Ya no aplica", ADMIN)


async def test_reject_is_for_admins_and_supervisors_only():
    service = service_with_fakes(technicians=[make_technician(1, user_id=10)])
    created = await create_ticket(service)
    for roles in (("TECHNICIAN",), ("EMPLOYEE",), ()):
        with pytest.raises(ForbiddenError):
            await service.reject_request(
                created.id, "Motivo válido", make_actor(10, role_codes=roles)
            )
    supervisor = make_actor(2, role_codes=("SUPERVISOR",))
    assert (
        await service.reject_request(created.id, "Motivo válido", supervisor)
    ).status == "cancelled"


async def test_a_rejected_request_cannot_be_rejected_again():
    service = service_with_fakes()
    created = await create_ticket(service)
    await service.reject_request(created.id, "Duplicado", ADMIN)
    with pytest.raises(BusinessRuleError):
        await service.reject_request(created.id, "Duplicado", ADMIN)


async def test_assigning_an_inactive_technician_is_a_409():
    technician = make_technician(1, user_id=10)
    technician.user.is_active = False
    service = service_with_fakes(technicians=[technician])
    created = await create_ticket(service)
    with pytest.raises(BusinessRuleError, match="inactive"):
        await service.assign_technician(
            created.id, TicketAssignmentCreateRequest(technician_id=1), ADMIN
        )
    assert not service.audit.records[-1]["action"].endswith("technician_assigned")


# -- kanban moves: State Pattern, required data, history and audit -----------------


def test_queue_columns_are_the_states_waiting_for_work():
    from app.domain.ticket_state import TicketState

    queue = [s.status for s in TicketState.workflow() if s.in_queue]
    assert queue == ["submitted", "triaged", "assigned"]


async def test_a_valid_move_leaves_history_and_audit():
    service = service_with_fakes(technicians=[make_technician(1, user_id=10)])
    created = await create_ticket(service)
    moved = await service.classify_request(
        created.id,
        MaintenanceClassifyRequest(category="network", priority="high"),
        ADMIN,
    )
    assert moved.status == "triaged"
    moved = await service.assign_technician(
        created.id, TicketAssignmentCreateRequest(technician_id=1), ADMIN
    )
    assert moved.status == "assigned"
    steps = [(h.from_status, h.to_status) for h in moved.status_history]
    assert steps[-2:] == [("submitted", "triaged"), ("triaged", "assigned")]
    actions = [r["action"] for r in service.audit.records]
    assert "maintenance.classified" in actions
    assert "maintenance.technician_assigned" in actions


async def test_an_invalid_move_is_refused_and_changes_nothing():
    from app.core.exceptions import InvalidTransitionError

    service = service_with_fakes()
    created = await create_ticket(service)
    with pytest.raises(InvalidTransitionError):
        await service.transition_status(
            created.id, MaintenanceStatusTransitionRequest(status="resolved"), ADMIN
        )
    assert (await service.get_request(created.id, ADMIN)).status == "submitted"


async def test_moving_to_assigned_without_a_technician_is_refused():
    from app.core.exceptions import InvalidTransitionError

    service = service_with_fakes()
    created = await create_ticket(service)
    with pytest.raises(InvalidTransitionError, match="without an assigned technician"):
        await service.transition_status(
            created.id, MaintenanceStatusTransitionRequest(status="assigned"), ADMIN
        )


@pytest.mark.parametrize("missing", ["category", "priority"])
def test_classifying_without_the_required_data_is_a_validation_error(missing):
    body = {"category": "network", "priority": "high"}
    body.pop(missing)
    with pytest.raises(ValidationError):
        MaintenanceClassifyRequest(**body)


def test_assigning_without_a_technician_is_a_validation_error():
    with pytest.raises(ValidationError):
        TicketAssignmentCreateRequest()


async def test_moving_a_card_needs_an_elevated_role():
    service = service_with_fakes(technicians=[make_technician(1, user_id=10)])
    created = await create_ticket(service)
    with pytest.raises(ForbiddenError):
        await service.assign_technician(
            created.id,
            TicketAssignmentCreateRequest(technician_id=1),
            make_actor(50, role_codes=("EMPLOYEE",)),
        )


# -- queue service (fake repository) ----------------------------------------------


class FakeQueueRepository:
    def __init__(self, current=None, previous=None):
        self.windows = [
            current or DecisionStats(10, 2, 3.0, 2.0),
            previous or DecisionStats(8, 4, 6.0, 5.0),
        ]

    async def wait_stats(self, now):
        return WaitStats(pending=7, unassigned=5, oldest_hours=50.0, median_hours=9.5)

    async def pending_by_priority(self):
        return [CountRow("critical", 1), CountRow("low", 6)]

    async def pending_by_category(self):
        return [CountRow("network", 4), CountRow("uncategorized", 3)]

    async def decision_stats(self, *, start, end):
        return self.windows.pop(0)

    async def active_categories(self):
        return [SimpleNamespace(code="network", name="Red")]


async def summary(repo=None, actor=ADMIN, period="30d"):
    return await QueueService(repo or FakeQueueRepository()).summary(
        actor, period=period, now=NOW
    )


async def test_summary_reports_the_queue_and_compares_with_the_previous_period():
    result = await summary()
    assert (result.pending_total, result.unassigned) == (7, 5)
    assert (result.oldest_wait_hours, result.median_wait_hours) == (50.0, 9.5)
    assert [(i.key, i.count) for i in result.by_priority] == [
        ("critical", 1),
        ("low", 6),
    ]
    assert result.by_category[1].key == "uncategorized"
    triage = result.triage_time
    assert (triage.value, triage.previous, triage.median_hours) == (3.0, 6.0, 2.0)
    assert triage.change_pct == -50.0 and triage.sample_size == 10
    decisions = result.decisions
    assert (decisions.approved, decisions.rejected, decisions.sample_size) == (8, 2, 10)
    assert (decisions.approval_rate_pct, decisions.rejection_rate_pct) == (80.0, 20.0)
    assert decisions.previous_approval_rate_pct == 50.0 and decisions.change_pct == 60.0


async def test_summary_has_no_values_instead_of_zeros_when_nothing_was_decided():
    empty = DecisionStats(0, 0, None, None)
    result = await summary(FakeQueueRepository(current=empty, previous=empty))
    assert result.triage_time.value is None and result.triage_time.median_hours is None
    assert result.decisions.approval_rate_pct is None
    assert result.decisions.rejection_rate_pct is None
    assert result.decisions.change_pct is None


@pytest.mark.parametrize(("n", "low"), [(1, True), (4, True), (5, False)])
async def test_summary_flags_few_decisions(n, low):
    few = DecisionStats(n, 0, 1.0, 1.0)
    result = await summary(FakeQueueRepository(current=few))
    assert result.decisions.low_sample is low and result.triage_time.low_sample is low


@pytest.mark.parametrize("roles", [("TECHNICIAN",), ("EMPLOYEE",), ()])
async def test_summary_is_closed_to_non_triage_roles(roles):
    with pytest.raises(ForbiddenError):
        await summary(actor=make_actor(9, role_codes=roles))


# -- HTTP -----------------------------------------------------------------------------


class StubQueueService(QueueService):
    def __init__(self):
        super().__init__(FakeQueueRepository())
        self.calls = []

    async def summary(self, actor, *, period, now=None):
        self.calls.append(period)
        return await super().summary(actor, period=period, now=NOW)


def build_client(role, permissions):
    stub = StubQueueService()
    user = SimpleNamespace(
        id=1,
        roles=[
            SimpleNamespace(
                code=role,
                is_active=True,
                permissions=perm_objects(*permissions),
            )
        ],
    )
    app.dependency_overrides[get_authenticated_user] = lambda: user
    app.dependency_overrides[providers.get_queue_service] = lambda: stub
    return stub


@pytest.fixture
def client():
    stub = build_client(
        "SUPERVISOR",
        ["maintenance.read", "maintenance.manage", "solicitudes:ver_todos"],
    )
    with TestClient(app, raise_server_exceptions=False) as test_client:
        test_client.stub = stub
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def technician_client():
    build_client("TECHNICIAN", ["maintenance.read", "maintenance.manage"])
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_summary_endpoint_returns_the_documented_shape(client):
    response = client.get("/maintenance/queue/summary?period=7d")
    assert response.status_code == 200
    assert set(response.json()) == {
        "generated_at",
        "period",
        "window_start",
        "window_end",
        "pending_total",
        "unassigned",
        "oldest_wait_hours",
        "median_wait_hours",
        "by_priority",
        "by_category",
        "triage_time",
        "decisions",
    }
    assert client.stub.calls == ["7d"]


def test_summary_defaults_to_30_days_and_rejects_unknown_periods(client):
    assert client.get("/maintenance/queue/summary").status_code == 200
    assert client.stub.calls == ["30d"]
    assert client.get("/maintenance/queue/summary?period=1d").status_code == 422


def test_a_technician_cannot_read_the_queue_summary_even_with_manage(technician_client):
    assert technician_client.get("/maintenance/queue/summary").status_code == 403


def test_categories_endpoint_lists_the_active_catalog(client):
    assert client.get("/maintenance/categories").json() == [
        {"code": "network", "name": "Red"}
    ]


def test_reject_endpoint_validates_the_reason_before_anything_else(client):
    assert client.post("/maintenance/requests/1/reject", json={}).status_code == 422
    assert (
        client.post(
            "/maintenance/requests/1/reject", json={"reason": "   "}
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/maintenance/requests/1/reject", json={"reason": "abc"}
        ).status_code
        == 422
    )


# -- real-database aggregates (need TEST_DATABASE_URL) -------------------------------


async def seed(session):
    session.add_all(
        [
            Priority(code="low", name="Low", level=1, sla_hours=100, is_active=True),
            Priority(
                code="critical", name="Critical", level=4, sla_hours=4, is_active=True
            ),
            RequestCategory(code="network", name="Red"),
            RequestCategory(code="hardware", name="Hardware"),
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
        status="assigned",
    )
    session.add(laptop)
    await session.flush()

    def ticket(n, priority, status, hours_ago, category=None):
        return MaintenanceRequest(
            ticket_number=f"T-{n}",
            equipment_id=laptop.id,
            requested_by_user_id=user.id,
            title=f"t{n}",
            description="d",
            priority=priority,
            category=category,
            status=status,
            created_at=NOW - timedelta(hours=hours_ago),
        )

    tickets = [
        ticket(1, "critical", "submitted", 10, "network"),
        ticket(2, "low", "triaged", 20, "network"),
        ticket(3, "low", "assigned", 30, None),
        ticket(4, "low", "in_progress", 40, "hardware"),  # not pending
        ticket(5, "low", "cancelled", 50, "hardware"),  # rejected
        ticket(6, "low", "cancelled", 60, "hardware"),  # approved, later cancelled
    ]
    session.add_all(tickets)
    await session.flush()

    def moved(n, from_status, to_status, hours_after_creation):
        ticket_ = tickets[n - 1]
        return TicketStatusHistory(
            request_id=ticket_.id,
            from_status=from_status,
            to_status=to_status,
            changed_at=ticket_.created_at + timedelta(hours=hours_after_creation),
        )

    session.add_all(
        [
            moved(2, "submitted", "triaged", 2),
            moved(3, "submitted", "assigned", 4),
            moved(5, "submitted", "cancelled", 6),
            moved(6, "submitted", "triaged", 8),
            moved(6, "triaged", "cancelled", 9),  # not a second decision
        ]
    )
    await session.flush()
    return tickets


async def test_wait_stats_count_the_pending_queue(db_session):
    await seed(db_session)
    waits = await QueueRepository(db_session).wait_stats(NOW)
    assert (waits.pending, waits.unassigned) == (3, 2)  # submitted, triaged, assigned
    assert waits.oldest_hours == pytest.approx(30)
    assert waits.median_hours == pytest.approx(20)


async def test_pending_breakdowns(db_session):
    await seed(db_session)
    repo = QueueRepository(db_session)
    assert await repo.pending_by_priority() == [
        CountRow("critical", 1),
        CountRow("low", 2),
    ]
    by_category = {r.key: r.count for r in await repo.pending_by_category()}
    assert by_category == {"network": 2, "uncategorized": 1}


async def test_each_request_is_decided_once_on_its_first_exit_from_submitted(
    db_session,
):
    await seed(db_session)
    stats = await QueueRepository(db_session).decision_stats(
        start=NOW - timedelta(days=30), end=NOW + timedelta(hours=1)
    )
    assert stats.decisions == 4  # T-2, T-3, T-5 and T-6 (once)
    assert stats.rejected == 1  # T-5
    assert stats.avg_triage_hours == pytest.approx((2 + 4 + 6 + 8) / 4)
    assert stats.median_triage_hours == pytest.approx(5)
    empty = await QueueRepository(db_session).decision_stats(
        start=NOW - timedelta(days=400), end=NOW - timedelta(days=399)
    )
    assert empty == DecisionStats(0, 0, None, None)


async def test_list_filters_by_status_list_category_and_assignment(db_session):
    await seed(db_session)
    repo = MaintenanceRepository(db_session)
    pending = await repo.list_requests(
        scope=DataScope.everything(), status="submitted, triaged ,assigned"
    )
    assert sorted(r.ticket_number for r in pending.items) == ["T-1", "T-2", "T-3"]
    network = await repo.list_requests(
        scope=DataScope.everything(), status="submitted,triaged", category="network"
    )
    assert sorted(r.ticket_number for r in network.items) == ["T-1", "T-2"]
    unassigned = await repo.list_requests(scope=DataScope.everything(), unassigned=True)
    assert len(unassigned.items) == 6  # nobody has an assignment in this seed
    assigned = await repo.list_requests(scope=DataScope.everything(), unassigned=False)
    assert assigned.items == []


# -- classification (triage) -------------------------------------------------------


@pytest.mark.parametrize(
    "payload",
    [
        {"category": "Hardware", "priority": "high"},
        {"category": "hardware", "priority": "1"},
        {"category": "hardware", "priority": "high", "notes": "x" * 501},
        {"category": "", "priority": "high"},
        {"priority": "high"},
    ],
)
def test_classify_validates_the_body(payload):
    with pytest.raises(ValidationError):
        MaintenanceClassifyRequest(**payload)


def test_classify_notes_are_trimmed_and_blank_means_none():
    assert (
        MaintenanceClassifyRequest(
            category="hardware", priority="high", notes="  visita  "
        ).notes
        == "visita"
    )
    assert (
        MaintenanceClassifyRequest(
            category="hardware", priority="high", notes="   "
        ).notes
        is None
    )


def test_assignment_and_transition_notes_are_bounded():
    with pytest.raises(ValidationError):
        TicketAssignmentCreateRequest(technician_id=1, notes="x" * 501)
    with pytest.raises(ValidationError):
        TicketAssignmentCreateRequest(technician_id=0)
    with pytest.raises(ValidationError):
        MaintenanceStatusTransitionRequest(status="triaged", notes="x" * 501)
    assert TicketAssignmentCreateRequest(technician_id=1, notes="  ").notes is None


async def test_classify_sets_category_and_priority_and_triages():
    service = service_with_fakes()
    created = await create_ticket(service)
    response = await service.classify_request(
        created.id,
        MaintenanceClassifyRequest(
            category="network", priority="high", notes="Visita en sitio"
        ),
        ADMIN,
    )
    assert (response.status, response.category, response.priority) == (
        "triaged",
        "network",
        "high",
    )
    assert response.status_history[-1].notes == "Visita en sitio"
    classified = next(
        r for r in service.audit.records if r["action"] == "maintenance.classified"
    )
    assert classified["old_values"]["status"] == "submitted"
    assert classified["new_values"] == {
        "priority": "high",
        "category": "network",
        "notes": "Visita en sitio",
    }
    assert service.repository.committed


async def test_a_triaged_request_can_be_reclassified_without_a_new_status_change():
    service = service_with_fakes()
    created = await create_ticket(service)
    body = MaintenanceClassifyRequest(category="network", priority="high")
    await service.classify_request(created.id, body, ADMIN)
    history = len(
        (await service.classify_request(created.id, body, ADMIN)).status_history
    )
    again = await service.classify_request(
        created.id,
        MaintenanceClassifyRequest(category="hardware", priority="low"),
        ADMIN,
    )
    assert (again.category, again.priority, again.status) == (
        "hardware",
        "low",
        "triaged",
    )
    assert len(again.status_history) == history


async def test_classify_rejects_unknown_catalog_entries_with_422():
    service = service_with_fakes()
    created = await create_ticket(service)
    with pytest.raises(UnprocessableError, match="category"):
        await service.classify_request(
            created.id,
            MaintenanceClassifyRequest(category="unknown", priority="high"),
            ADMIN,
        )
    with pytest.raises(UnprocessableError, match="priority"):
        await service.classify_request(
            created.id,
            MaintenanceClassifyRequest(category="network", priority="unknown"),
            ADMIN,
        )


async def test_classify_only_works_before_assignment_and_for_elevated_roles():
    service = service_with_fakes(technicians=[make_technician(1, user_id=10)])
    created = await create_ticket(service)
    body = MaintenanceClassifyRequest(category="network", priority="high")
    with pytest.raises(ForbiddenError):
        await service.classify_request(created.id, body, make_actor(100))
    await service.assign_technician(
        created.id, TicketAssignmentCreateRequest(technician_id=1), ADMIN
    )
    with pytest.raises(BusinessRuleError, match="waiting for triage"):
        await service.classify_request(created.id, body, ADMIN)
    with pytest.raises(NotFoundError):
        await service.classify_request(999, body, ADMIN)


async def test_reject_is_audited_with_its_reason():
    service = service_with_fakes()
    created = await create_ticket(service)
    await service.reject_request(created.id, "Duplicado del TCK-1", ADMIN)
    rejected = next(
        r for r in service.audit.records if r["action"] == "maintenance.rejected"
    )
    assert rejected["new_values"] == {"reason": "Duplicado del TCK-1"}
    assert rejected["old_values"] == {"status": "submitted"}


@pytest.mark.parametrize(
    ("date_from", "date_to"),
    [
        (NOW + timedelta(days=400), None),
        (NOW, NOW - timedelta(days=1)),
    ],
)
async def test_list_rejects_incoherent_date_filters(date_from, date_to):
    service = service_with_fakes()
    with pytest.raises(UnprocessableError):
        await service.list_requests(
            status=None,
            priority=None,
            equipment_id=None,
            date_from=date_from,
            date_to=date_to,
            actor=ADMIN,
        )
