from datetime import UTC, datetime

from app.core.authz import AuthContext
from app.core.exceptions import (
    BusinessRuleError,
    ForbiddenError,
    NotFoundError,
    UnprocessableError,
)
from app.core.pagination import DEFAULT_PAGE, PageParams
from app.domain.ticket_state import TicketState
from app.models.maintenance import MaintenanceRequest
from app.repositories.base import Page
from app.repositories.maintenance import MaintenanceRepository
from app.schemas.maintenance import (
    EquipmentSummary,
    MaintenanceClassifyRequest,
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

#: Statuses from which a request can still be rejected (work has not started).
REJECTABLE_STATUSES = ("submitted", "triaged", "assigned")
CLASSIFIABLE_STATUSES = ("submitted", "triaged")


class MaintenanceService:
    def __init__(
        self,
        repository: MaintenanceRepository,
        audit: AuditService,
        notifications: NotificationService,
    ):
        self.repository = repository
        self.audit = audit
        self.notifications = notifications

    # -- Requests --------------------------------------------------------

    async def create_request(
        self, payload: MaintenanceRequestCreate, requester: AuthContext
    ) -> MaintenanceRequestResponse:
        if await self.repository.get_equipment(payload.equipment_id) is None:
            raise NotFoundError("equipment not found")
        if await self.repository.get_active_priority(payload.priority) is None:
            raise NotFoundError(f"priority '{payload.priority}' not found or inactive")
        if (
            payload.category is not None
            and await self.repository.get_active_category(payload.category) is None
        ):
            raise NotFoundError(f"category '{payload.category}' not found or inactive")
        ticket_number = await self.repository.next_ticket_number()
        request = await self.repository.create_request(
            ticket_number=ticket_number,
            equipment_id=payload.equipment_id,
            requested_by_user_id=requester.id,
            title=payload.title,
            description=payload.description,
            priority=payload.priority,
            category=payload.category,
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
        category: str | None = None,
        unassigned: bool | None = None,
        search: str | None = None,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
        params: PageParams = DEFAULT_PAGE,
        actor: AuthContext,
    ) -> Page[MaintenanceRequestListItem]:
        if date_from is not None and date_to is not None and date_from > date_to:
            raise UnprocessableError("date_from must not be after date_to")
        if date_from is not None and date_from > datetime.now(UTC):
            raise UnprocessableError("date_from cannot be in the future")
        scope = await self.repository.scope_for(actor)
        page = await self.repository.list_requests(
            scope=scope,
            status=status,
            priority=priority,
            category=category,
            unassigned=unassigned,
            equipment_id=equipment_id,
            search=search,
            date_from=date_from,
            date_to=date_to,
            params=params,
        )
        # Which cards the person may work (drag on a board): all of them for someone who sees
        # everything, otherwise those assigned to them.
        assigned: set[int] = set()
        if not scope.sees_everything and scope.technician_id is not None:
            assigned = await self.repository.assigned_among(
                scope.technician_id, [item.id for item in page.items]
            )

        def to_item(request: MaintenanceRequest) -> MaintenanceRequestListItem:
            item = MaintenanceRequestListItem.model_validate(request)
            item.can_act = scope.sees_everything or request.id in assigned
            return item

        return page.map(to_item)

    async def ensure_can_view(self, request_id: int, actor: AuthContext) -> None:
        """Raise unless `actor` may see the ticket (404 if it does not exist)."""
        await self._ensure_visible(await self._reload(request_id), actor)

    async def get_request(
        self, request_id: int, actor: AuthContext
    ) -> MaintenanceRequestResponse:
        request = await self._reload(request_id)
        await self._ensure_visible(request, actor)
        return self._response(request)

    async def transition_status(
        self,
        request_id: int,
        payload: MaintenanceStatusTransitionRequest,
        actor: AuthContext,
    ) -> MaintenanceRequestResponse:
        request = await self._reload(request_id)
        await self._require_can_act(request, actor)
        # Moving a ticket needs more than a valid transition: the role must be allowed to
        # take it to that state (e.g. only whoever assigns may assign; only a supervisor
        # rejects or cancels).
        actor.require(
            TicketState.of(payload.status).permission,
            f"Tu rol no puede mover un ticket al estado «{payload.status}».",
        )

        current, target = request.status, payload.status
        has_technician = await self.repository.get_active_assignment(request_id)
        new_state = TicketState.of(current).transition(
            request,
            target,
            now=datetime.now(UTC),
            resolution_summary=payload.resolution_summary,
            has_technician=has_technician is not None,
        )

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
        if new_state.notifies_requester:
            self.notifications.notify(
                user_id=request.requested_by_user_id,
                title=f"Ticket {request.ticket_number} {target}",
                message=f"Your maintenance request '{request.title}' is now {target}.",
                notification_type="maintenance_status",
            )
        await self.repository.commit()
        self.repository.expire_mutable_collections(request)
        return self._response(await self._reload(request_id))

    async def classify_request(
        self,
        request_id: int,
        payload: MaintenanceClassifyRequest,
        actor: AuthContext,
    ) -> MaintenanceRequestResponse:
        """Set category and priority (both must be active catalog entries) and triage."""
        request = await self._reload(request_id)
        actor.require("solicitudes:editar")
        if request.status not in CLASSIFIABLE_STATUSES:
            raise BusinessRuleError(
                "only requests waiting for triage can be classified "
                f"(current status: {request.status})"
            )
        if await self.repository.get_active_priority(payload.priority) is None:
            raise UnprocessableError(
                f"priority '{payload.priority}' not found or inactive"
            )
        if await self.repository.get_active_category(payload.category) is None:
            raise UnprocessableError(
                f"category '{payload.category}' not found or inactive"
            )
        old = {
            "status": request.status,
            "priority": request.priority,
            "category": request.category,
        }
        await self.repository.update_fields(
            request, {"priority": payload.priority, "category": payload.category}
        )
        self.audit.record(
            user_id=actor.id,
            action="maintenance.classified",
            entity_type="maintenance_request",
            entity_id=request_id,
            old_values=old,
            new_values={
                "priority": payload.priority,
                "category": payload.category,
                "notes": payload.notes,
            },
        )
        if request.status == "submitted":
            # Commits the classification together with the status change.
            return await self.transition_status(
                request_id,
                MaintenanceStatusTransitionRequest(
                    status="triaged", notes=payload.notes
                ),
                actor,
            )
        await self.repository.commit()
        self.repository.expire_mutable_collections(request)
        return self._response(await self._reload(request_id))

    async def reject_request(
        self, request_id: int, reason: str, actor: AuthContext
    ) -> MaintenanceRequestResponse:
        """Cancel a request that has not been started, recording why."""
        request = await self._reload(request_id)
        actor.require("solicitudes:aprobar")
        if request.status not in REJECTABLE_STATUSES:
            raise BusinessRuleError(
                "only requests that have not started can be rejected "
                f"(current status: {request.status})"
            )
        self.audit.record(
            user_id=actor.id,
            action="maintenance.rejected",
            entity_type="maintenance_request",
            entity_id=request_id,
            old_values={"status": request.status},
            new_values={"reason": reason},
        )
        return await self.transition_status(
            request_id,
            MaintenanceStatusTransitionRequest(
                status="cancelled", notes=f"Rechazada: {reason}"
            ),
            actor,
        )

    # -- Assignment --------------------------------------------------------

    async def assign_technician(
        self,
        request_id: int,
        payload: TicketAssignmentCreateRequest,
        actor: AuthContext,
    ) -> MaintenanceRequestResponse:
        request = await self._reload(request_id)
        actor.require("tickets:asignar")
        state = TicketState.of(request.status)
        state.ensure_accepts_assignment()  # fail before touching the repository
        technician = await self.repository.get_technician(payload.technician_id)
        if technician is None:
            raise NotFoundError("technician not found")
        if not technician.user.is_active:
            raise BusinessRuleError("cannot assign a ticket to an inactive technician")

        await self.repository.assign_technician(
            request_id=request_id,
            technician_id=technician.id,
            assigned_by_user_id=actor.id,
            notes=payload.notes,
        )
        new_state = state.assign_technician(request, now=datetime.now(UTC))
        if new_state is not state:
            self.repository.append_status_history(
                request_id=request_id,
                from_status=state.status,
                to_status=new_state.status,
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
        self, request_id: int, actor: AuthContext
    ) -> MaintenanceRequestResponse:
        request = await self.repository.get(request_id)
        if request is None:
            raise NotFoundError("maintenance request not found")
        actor.require("tickets:asignar")
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
        actor: AuthContext,
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
        self, request_id: int, actor: AuthContext
    ) -> list[MaintenanceRecordResponse]:
        request = await self._reload(request_id)
        await self._ensure_visible(request, actor)
        records = await self.repository.list_records(request_id)
        return [MaintenanceRecordResponse.model_validate(item) for item in records]

    # -- Authorization helpers ----------------------------------------------

    async def _ensure_visible(
        self, request: MaintenanceRequest, actor: AuthContext
    ) -> None:
        scope = await self.repository.scope_for(actor)
        if not self.repository.visible_to(request, scope):
            raise ForbiddenError("not authorized to view this maintenance request")

    async def _require_can_act(
        self, request: MaintenanceRequest, actor: AuthContext
    ) -> None:
        scope = await self.repository.scope_for(actor)
        if scope.sees_everything:
            return
        active = await self.repository.get_active_assignment(request.id)
        if (
            scope.technician_id is not None
            and active is not None
            and active.technician_id == scope.technician_id
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
            category=request.category,
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
            allowed_next_statuses=sorted(
                TicketState.of(request.status).allowed_targets
            ),
        )
