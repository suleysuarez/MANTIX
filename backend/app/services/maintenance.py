from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import BusinessRuleError, ForbiddenError, NotFoundError
from app.models.auth import User
from app.models.maintenance import MaintenanceRequest
from app.repositories.maintenance import MaintenanceRepository
from app.schemas.maintenance import (
    EquipmentSummary,
    MaintenanceRecordCreate,
    MaintenanceRecordResponse,
    MaintenanceRequestCreate,
    MaintenanceRequestListItem,
    MaintenanceRequestResponse,
    MaintenanceStatusTransitionRequest,
    TechnicianSummary,
    TicketAssignmentCreateRequest,
    TicketAssignmentResponse,
    TicketStatusHistoryEntry,
    UserSummary,
)
from app.services.audit import AuditService
from app.services.notification import NotificationService

#: Explicit ticket state machine. Keys are the current status, values are the
#: set of statuses it may move to next. `closed`/`cancelled` are terminal.
ALLOWED_TRANSITIONS: dict[str, set[str]] = {
    "submitted": {"triaged", "cancelled"},
    "triaged": {"assigned", "cancelled"},
    "assigned": {"in_progress", "cancelled"},
    "in_progress": {"waiting", "resolved", "cancelled"},
    "waiting": {"in_progress", "cancelled"},
    "resolved": {"closed", "in_progress"},
    "closed": set(),
    "cancelled": set(),
}

_ELEVATED_ROLE_CODES = {"ADMIN", "SUPERVISOR"}


class MaintenanceService:
    def __init__(self, session: AsyncSession):
        self.repository = MaintenanceRepository(session)
        self.audit = AuditService(session)
        self.notifications = NotificationService(session)

    # -- Requests --------------------------------------------------------

    async def create_request(
        self, payload: MaintenanceRequestCreate, requester: User
    ) -> MaintenanceRequestResponse:
        if await self.repository.get_equipment(payload.equipment_id) is None:
            raise NotFoundError("equipment not found")
        ticket_number = await self.repository.next_ticket_number()
        request = await self.repository.create_request(
            ticket_number=ticket_number,
            equipment_id=payload.equipment_id,
            requested_by_user_id=requester.id,
            title=payload.title,
            description=payload.description,
            priority=payload.priority,
        )
        self.repository.append_status_history(
            request_id=request.id,
            from_status=None,
            to_status="submitted",
            changed_by_user_id=requester.id,
            notes=None,
        )
        self.audit.record(
            user_id=requester.id,
            action="maintenance.request_created",
            entity_type="maintenance_request",
            entity_id=request.id,
            new_values={
                "ticket_number": ticket_number,
                "equipment_id": payload.equipment_id,
            },
        )
        await self.repository.commit()
        self.repository.expire_mutable_collections(request)
        return self._response(await self._reload(request.id))

    async def list_requests(
        self,
        *,
        status: str | None,
        priority: str | None,
        equipment_id: int | None,
        limit: int,
        offset: int,
        actor: User,
    ) -> list[MaintenanceRequestListItem]:
        requested_by_user_id = None
        technician_id = None
        if not self._is_elevated(actor):
            technician = await self.repository.get_technician_by_user_id(actor.id)
            if technician is not None:
                technician_id = technician.id
            else:
                requested_by_user_id = actor.id
        items = await self.repository.list_requests(
            status=status,
            priority=priority,
            equipment_id=equipment_id,
            requested_by_user_id=requested_by_user_id,
            technician_id=technician_id,
            limit=min(limit, 500),
            offset=offset,
        )
        return [MaintenanceRequestListItem.model_validate(item) for item in items]

    async def get_request(
        self, request_id: int, actor: User
    ) -> MaintenanceRequestResponse:
        request = await self._reload(request_id)
        await self._ensure_visible(request, actor)
        return self._response(request)

    async def transition_status(
        self,
        request_id: int,
        payload: MaintenanceStatusTransitionRequest,
        actor: User,
    ) -> MaintenanceRequestResponse:
        request = await self._reload(request_id)
        await self._require_can_act(request, actor)

        current, target = request.status, payload.status
        if target not in ALLOWED_TRANSITIONS.get(current, set()):
            raise BusinessRuleError(f"cannot transition from '{current}' to '{target}'")

        now = datetime.now(timezone.utc)
        request.status = target
        if target == "resolved":
            request.resolved_at = now
            if payload.resolution_summary:
                request.resolution_summary = payload.resolution_summary
        if target == "closed":
            request.closed_at = now

        self.repository.append_status_history(
            request_id=request.id,
            from_status=current,
            to_status=target,
            changed_by_user_id=actor.id,
            notes=payload.notes,
        )
        self.audit.record(
            user_id=actor.id,
            action="maintenance.status_changed",
            entity_type="maintenance_request",
            entity_id=request.id,
            old_values={"status": current},
            new_values={"status": target},
        )
        if target in {"resolved", "closed"}:
            self.notifications.notify(
                user_id=request.requested_by_user_id,
                title=f"Ticket {request.ticket_number} {target}",
                message=f"Your maintenance request '{request.title}' is now {target}.",
                notification_type="maintenance_status",
            )
        await self.repository.commit()
        self.repository.expire_mutable_collections(request)
        return self._response(await self._reload(request_id))

    # -- Assignment --------------------------------------------------------

    async def assign_technician(
        self,
        request_id: int,
        payload: TicketAssignmentCreateRequest,
        actor: User,
    ) -> MaintenanceRequestResponse:
        request = await self._reload(request_id)
        self._require_elevated(actor)
        if request.status in {"closed", "cancelled"}:
            raise BusinessRuleError(
                f"cannot assign a technician to a '{request.status}' ticket"
            )
        technician = await self.repository.get_technician(payload.technician_id)
        if technician is None:
            raise NotFoundError("technician not found")

        await self.repository.assign_technician(
            request_id=request_id,
            technician_id=technician.id,
            assigned_by_user_id=actor.id,
            notes=payload.notes,
        )
        previous_status = request.status
        if previous_status in {"submitted", "triaged"}:
            request.status = "assigned"
            self.repository.append_status_history(
                request_id=request_id,
                from_status=previous_status,
                to_status="assigned",
                changed_by_user_id=actor.id,
                notes="technician assigned",
            )
        self.audit.record(
            user_id=actor.id,
            action="maintenance.technician_assigned",
            entity_type="maintenance_request",
            entity_id=request_id,
            new_values={"technician_id": technician.id},
        )
        self.notifications.notify(
            user_id=technician.user_id,
            title=f"Assigned to ticket {request.ticket_number}",
            message=f"You were assigned to '{request.title}'.",
            notification_type="ticket_assigned",
        )
        await self.repository.commit()
        self.repository.expire_mutable_collections(request)
        return self._response(await self._reload(request_id))

    async def unassign_technician(
        self, request_id: int, actor: User
    ) -> MaintenanceRequestResponse:
        request = await self.repository.get(request_id)
        if request is None:
            raise NotFoundError("maintenance request not found")
        self._require_elevated(actor)
        closed = await self.repository.unassign_active(request_id)
        if closed is None:
            raise NotFoundError("no active technician assignment")
        self.audit.record(
            user_id=actor.id,
            action="maintenance.technician_unassigned",
            entity_type="maintenance_request",
            entity_id=request_id,
            old_values={"technician_id": closed.technician_id},
        )
        await self.repository.commit()
        self.repository.expire_mutable_collections(request)
        return self._response(await self._reload(request_id))

    # -- Maintenance records -----------------------------------------------

    async def add_maintenance_record(
        self,
        request_id: int,
        payload: MaintenanceRecordCreate,
        actor: User,
    ) -> MaintenanceRecordResponse:
        request = await self._reload(request_id)
        await self._require_can_act(request, actor)

        technician = await self.repository.get_technician_by_user_id(actor.id)
        technician_id = technician.id if technician is not None else None
        if technician_id is None:
            active = await self.repository.get_active_assignment(request_id)
            if active is None:
                raise BusinessRuleError(
                    "this ticket has no assigned technician to attribute the record to"
                )
            technician_id = active.technician_id

        record = await self.repository.create_record(
            equipment_id=request.equipment_id,
            request_id=request_id,
            technician_id=technician_id,
            payload=payload,
        )
        self.audit.record(
            user_id=actor.id,
            action="maintenance.record_logged",
            entity_type="maintenance_record",
            entity_id=record.id,
            new_values={"request_id": request_id, "work_type": payload.work_type},
        )
        await self.repository.commit()
        return MaintenanceRecordResponse.model_validate(record)

    async def list_records(
        self, request_id: int, actor: User
    ) -> list[MaintenanceRecordResponse]:
        request = await self._reload(request_id)
        await self._ensure_visible(request, actor)
        records = await self.repository.list_records(request_id)
        return [MaintenanceRecordResponse.model_validate(item) for item in records]

    # -- Authorization helpers ----------------------------------------------

    @staticmethod
    def _is_elevated(actor: User) -> bool:
        return any(role.code in _ELEVATED_ROLE_CODES for role in actor.roles)

    def _require_elevated(self, actor: User) -> None:
        if not self._is_elevated(actor):
            raise ForbiddenError("only ADMIN or SUPERVISOR can perform this action")

    async def _ensure_visible(self, request: MaintenanceRequest, actor: User) -> None:
        if self._is_elevated(actor):
            return
        technician = await self.repository.get_technician_by_user_id(actor.id)
        if technician is not None and any(
            assignment.technician_id == technician.id
            for assignment in request.ticket_assignments
        ):
            return
        if request.requested_by_user_id == actor.id:
            return
        raise ForbiddenError("not authorized to view this maintenance request")

    async def _require_can_act(self, request: MaintenanceRequest, actor: User) -> None:
        if self._is_elevated(actor):
            return
        technician = await self.repository.get_technician_by_user_id(actor.id)
        active = await self.repository.get_active_assignment(request.id)
        if (
            technician is not None
            and active is not None
            and active.technician_id == technician.id
        ):
            return
        raise ForbiddenError(
            "only the assigned technician or a supervisor can act on this ticket"
        )

    # -- Assembly -------------------------------------------------------

    async def _reload(self, request_id: int) -> MaintenanceRequest:
        request = await self.repository.get(request_id)
        if request is None:
            raise NotFoundError("maintenance request not found")
        return request

    @staticmethod
    def _response(request: MaintenanceRequest) -> MaintenanceRequestResponse:
        active_assignment = next(
            (a for a in request.ticket_assignments if a.unassigned_at is None), None
        )
        current_assignment = None
        if active_assignment is not None:
            current_assignment = TicketAssignmentResponse(
                id=active_assignment.id,
                technician=TechnicianSummary(
                    id=active_assignment.technician.id,
                    user_id=active_assignment.technician.user_id,
                    full_name=active_assignment.technician.user.full_name,
                ),
                assigned_at=active_assignment.assigned_at,
                unassigned_at=active_assignment.unassigned_at,
                notes=active_assignment.notes,
            )
        return MaintenanceRequestResponse(
            id=request.id,
            ticket_number=request.ticket_number,
            equipment=EquipmentSummary.model_validate(request.equipment),
            requested_by=UserSummary.model_validate(request.requested_by_user),
            title=request.title,
            description=request.description,
            priority=request.priority,
            status=request.status,
            resolution_summary=request.resolution_summary,
            resolved_at=request.resolved_at,
            closed_at=request.closed_at,
            created_at=request.created_at,
            updated_at=request.updated_at,
            current_assignment=current_assignment,
            status_history=[
                TicketStatusHistoryEntry.model_validate(entry)
                for entry in sorted(request.status_history, key=lambda h: h.changed_at)
            ],
        )
