from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from app.core.exceptions import BusinessRuleError, ForbiddenError, NotFoundError
from app.schemas.maintenance import (
    MaintenanceRecordCreate,
    MaintenanceRequestCreate,
    MaintenanceStatusTransitionRequest,
    TicketAssignmentCreateRequest,
)
from app.services.maintenance import MaintenanceService


def make_equipment(equipment_id=1):
    return SimpleNamespace(
        id=equipment_id, asset_tag=f"EQ-{equipment_id}", brand="Acme", model="X1"
    )


def make_user(user_id, full_name="User", email="user@example.com"):
    return SimpleNamespace(id=user_id, full_name=full_name, email=email)


def make_technician(technician_id, user_id, full_name="Tech"):
    return SimpleNamespace(
        id=technician_id, user_id=user_id, user=make_user(user_id, full_name)
    )


def make_actor(user_id, role_codes=()):
    return SimpleNamespace(
        id=user_id, roles=[SimpleNamespace(code=c) for c in role_codes]
    )


class FakeAudit:
    def __init__(self):
        self.records = []

    def record(self, **kwargs):
        self.records.append(kwargs)


class FakeNotifications:
    def __init__(self):
        self.sent = []

    def notify(self, **kwargs):
        self.sent.append(kwargs)


class FakeMaintenanceRepository:
    def __init__(self, equipment=None, technicians=None):
        self.equipment = equipment or {1: make_equipment(1)}
        self.technicians = {t.id: t for t in (technicians or [])}
        self.requests: dict[int, SimpleNamespace] = {}
        self.records: list[SimpleNamespace] = []
        self._next_request_id = 1
        self._ticket_seq = 0
        self.committed = False

    async def get_equipment(self, equipment_id):
        return self.equipment.get(equipment_id)

    async def next_ticket_number(self):
        self._ticket_seq += 1
        return f"TCK-2026-{self._ticket_seq:06d}"

    async def create_request(
        self,
        *,
        ticket_number,
        equipment_id,
        requested_by_user_id,
        title,
        description,
        priority,
    ):
        request = SimpleNamespace(
            id=self._next_request_id,
            ticket_number=ticket_number,
            equipment_id=equipment_id,
            equipment=self.equipment[equipment_id],
            requested_by_user_id=requested_by_user_id,
            requested_by_user=make_user(requested_by_user_id),
            title=title,
            description=description,
            priority=priority,
            status="submitted",
            resolution_summary=None,
            resolved_at=None,
            closed_at=None,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
            ticket_assignments=[],
            status_history=[],
        )
        self._next_request_id += 1
        self.requests[request.id] = request
        return request

    def append_status_history(
        self, *, request_id, from_status, to_status, changed_by_user_id, notes
    ):
        request = self.requests[request_id]
        request.status_history.append(
            SimpleNamespace(
                id=len(request.status_history) + 1,
                from_status=from_status,
                to_status=to_status,
                changed_at=datetime.now(timezone.utc),
                notes=notes,
            )
        )

    async def get(self, request_id):
        return self.requests.get(request_id)

    def expire_mutable_collections(self, request):
        # No-op: the fake always reflects the in-memory object's current
        # state directly, there's nothing to force a refresh of.
        pass

    async def list_requests(
        self,
        *,
        status=None,
        priority=None,
        equipment_id=None,
        requested_by_user_id=None,
        technician_id=None,
        limit=200,
        offset=0,
    ):
        items = list(self.requests.values())
        if status is not None:
            items = [item for item in items if item.status == status]
        if priority is not None:
            items = [item for item in items if item.priority == priority]
        if equipment_id is not None:
            items = [item for item in items if item.equipment_id == equipment_id]
        if requested_by_user_id is not None:
            items = [
                item
                for item in items
                if item.requested_by_user_id == requested_by_user_id
            ]
        if technician_id is not None:
            items = [
                item
                for item in items
                if any(
                    a.technician_id == technician_id and a.unassigned_at is None
                    for a in item.ticket_assignments
                )
            ]
        return items[offset : offset + limit]

    async def get_technician(self, technician_id):
        return self.technicians.get(technician_id)

    async def get_technician_by_user_id(self, user_id):
        return next(
            (t for t in self.technicians.values() if t.user_id == user_id), None
        )

    async def get_active_assignment(self, request_id):
        request = self.requests[request_id]
        return next(
            (a for a in request.ticket_assignments if a.unassigned_at is None), None
        )

    async def assign_technician(
        self, *, request_id, technician_id, assigned_by_user_id, notes
    ):
        request = self.requests[request_id]
        for assignment in request.ticket_assignments:
            if assignment.unassigned_at is None:
                assignment.unassigned_at = datetime.now(timezone.utc)
        assignment = SimpleNamespace(
            id=len(request.ticket_assignments) + 1,
            request_id=request_id,
            technician_id=technician_id,
            technician=self.technicians[technician_id],
            assigned_at=datetime.now(timezone.utc),
            unassigned_at=None,
            assigned_by_user_id=assigned_by_user_id,
            notes=notes,
        )
        request.ticket_assignments.append(assignment)
        return assignment

    async def unassign_active(self, request_id):
        active = await self.get_active_assignment(request_id)
        if active is None:
            return None
        active.unassigned_at = datetime.now(timezone.utc)
        return active

    async def create_record(self, *, equipment_id, request_id, technician_id, payload):
        labor_cost = payload.labor_cost or 0
        parts_cost = payload.parts_cost or 0
        record = SimpleNamespace(
            id=len(self.records) + 1,
            equipment_id=equipment_id,
            request_id=request_id,
            technician_id=technician_id,
            work_type=payload.work_type,
            started_at=payload.started_at,
            completed_at=payload.completed_at,
            diagnosis=payload.diagnosis,
            actions_taken=payload.actions_taken,
            result=payload.result,
            labor_cost=labor_cost,
            parts_cost=parts_cost,
            total_cost=labor_cost + parts_cost,
            notes=payload.notes,
        )
        self.records.append(record)
        return record

    async def list_records(self, request_id):
        return [record for record in self.records if record.request_id == request_id]

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


def service_with_fakes(**repo_kwargs):
    service = MaintenanceService(object())
    service.repository = FakeMaintenanceRepository(**repo_kwargs)
    service.audit = FakeAudit()
    service.notifications = FakeNotifications()
    return service


async def create_ticket(service, requester_id=100):
    return await service.create_request(
        MaintenanceRequestCreate(
            equipment_id=1, title="Broken screen", description="Cracked display"
        ),
        make_actor(requester_id),
    )


@pytest.mark.asyncio
async def test_create_request_starts_submitted_with_history():
    service = service_with_fakes()
    response = await create_ticket(service)

    assert response.status == "submitted"
    assert response.ticket_number.startswith("TCK-")
    assert [entry.to_status for entry in response.status_history] == ["submitted"]
    assert service.repository.committed


@pytest.mark.asyncio
async def test_valid_transition_succeeds():
    service = service_with_fakes()
    created = await create_ticket(service)
    admin = make_actor(1, role_codes=("ADMIN",))

    updated = await service.transition_status(
        created.id, MaintenanceStatusTransitionRequest(status="triaged"), admin
    )

    assert updated.status == "triaged"
    assert [entry.to_status for entry in updated.status_history] == [
        "submitted",
        "triaged",
    ]


@pytest.mark.asyncio
async def test_invalid_transition_is_rejected():
    service = service_with_fakes()
    created = await create_ticket(service)
    admin = make_actor(1, role_codes=("ADMIN",))

    with pytest.raises(BusinessRuleError):
        await service.transition_status(
            created.id, MaintenanceStatusTransitionRequest(status="closed"), admin
        )


@pytest.mark.asyncio
async def test_assigning_technician_auto_transitions_to_assigned():
    technician = make_technician(1, user_id=10)
    service = service_with_fakes(technicians=[technician])
    created = await create_ticket(service)
    admin = make_actor(1, role_codes=("ADMIN",))

    updated = await service.assign_technician(
        created.id, TicketAssignmentCreateRequest(technician_id=1), admin
    )

    assert updated.status == "assigned"
    assert updated.current_assignment.technician.id == 1
    assert len(service.notifications.sent) == 1


@pytest.mark.asyncio
async def test_technician_can_only_transition_own_assigned_ticket():
    tech_a = make_technician(1, user_id=10, full_name="Tech A")
    tech_b = make_technician(2, user_id=20, full_name="Tech B")
    service = service_with_fakes(technicians=[tech_a, tech_b])
    created = await create_ticket(service)
    admin = make_actor(1, role_codes=("ADMIN",))
    await service.assign_technician(
        created.id, TicketAssignmentCreateRequest(technician_id=1), admin
    )

    actor_a = make_actor(10, role_codes=("TECHNICIAN",))
    actor_b = make_actor(20, role_codes=("TECHNICIAN",))

    # Tech A is assigned, so they may transition the ticket.
    updated = await service.transition_status(
        created.id, MaintenanceStatusTransitionRequest(status="in_progress"), actor_a
    )
    assert updated.status == "in_progress"

    # Tech B is not assigned to this ticket.
    with pytest.raises(ForbiddenError):
        await service.transition_status(
            created.id,
            MaintenanceStatusTransitionRequest(status="waiting"),
            actor_b,
        )


@pytest.mark.asyncio
async def test_unassign_clears_active_assignment():
    technician = make_technician(1, user_id=10)
    service = service_with_fakes(technicians=[technician])
    created = await create_ticket(service)
    admin = make_actor(1, role_codes=("ADMIN",))
    await service.assign_technician(
        created.id, TicketAssignmentCreateRequest(technician_id=1), admin
    )

    updated = await service.unassign_technician(created.id, admin)

    assert updated.current_assignment is None


@pytest.mark.asyncio
async def test_unassign_without_active_assignment_raises_not_found():
    service = service_with_fakes()
    created = await create_ticket(service)
    admin = make_actor(1, role_codes=("ADMIN",))

    with pytest.raises(NotFoundError):
        await service.unassign_technician(created.id, admin)


@pytest.mark.asyncio
async def test_maintenance_record_total_cost_is_labor_plus_parts():
    technician = make_technician(1, user_id=10)
    service = service_with_fakes(technicians=[technician])
    created = await create_ticket(service)
    admin = make_actor(1, role_codes=("ADMIN",))
    await service.assign_technician(
        created.id, TicketAssignmentCreateRequest(technician_id=1), admin
    )

    record = await service.add_maintenance_record(
        created.id,
        MaintenanceRecordCreate(
            work_type="corrective",
            started_at=datetime.now(timezone.utc),
            diagnosis="Screen cracked",
            actions_taken="Replaced panel",
            result="resolved",
            labor_cost=100,
            parts_cost=50,
        ),
        admin,
    )

    assert record.total_cost == 150
    assert record.technician_id == 1


@pytest.mark.asyncio
async def test_employee_only_lists_own_tickets():
    service = service_with_fakes()
    own_ticket = await create_ticket(service, requester_id=100)
    await create_ticket(service, requester_id=200)

    employee = make_actor(100)
    result = await service.list_requests(
        status=None,
        priority=None,
        equipment_id=None,
        limit=200,
        offset=0,
        actor=employee,
    )

    assert len(result) == 1
    assert result[0].ticket_number == own_ticket.ticket_number
