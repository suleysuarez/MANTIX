"""State pattern for the maintenance ticket lifecycle.

Each status is a `TicketState` object that owns what the service used to
encode in scattered `if` chains:

* which statuses it may move to (`allowed_targets`),
* what must hold to enter it (`requires_technician`),
* what happens to the ticket when it is entered (`on_enter`),
* how it reacts to a technician being assigned (`assign_technician`).

Every status change, including the automatic one on assignment, goes through
`transition()`; nothing mutates `ticket.status` anywhere else.

The module is pure domain logic: no database, no HTTP. Adding a status means
adding one class and registering it, without touching `MaintenanceService`.
"""

from datetime import datetime
from typing import Any, ClassVar, Protocol

from app.core.exceptions import BusinessRuleError, InvalidTransitionError


class TicketLike(Protocol):
    """The slice of `MaintenanceRequest` a state may read or mutate."""

    status: str
    resolution_summary: str | None
    resolved_at: datetime | None
    closed_at: datetime | None


class TicketState:
    status: ClassVar[str]
    allowed_targets: ClassVar[frozenset[str]] = frozenset()
    #: Whether the requester is told when a ticket enters this state.
    notifies_requester: ClassVar[bool] = False
    #: Whether entering this state needs an active technician assignment.
    requires_technician: ClassVar[bool] = False

    _registry: ClassVar[dict[str, "TicketState"]] = {}

    def __init_subclass__(cls, **kwargs: Any) -> None:
        super().__init_subclass__(**kwargs)
        if getattr(cls, "status", None):
            TicketState._registry[cls.status] = cls()

    @staticmethod
    def of(status: str) -> "TicketState":
        try:
            return TicketState._registry[status]
        except KeyError:
            raise BusinessRuleError(f"unknown ticket status '{status}'") from None

    @property
    def is_terminal(self) -> bool:
        return not self.allowed_targets

    def can_transition_to(self, target: str) -> bool:
        return target in self.allowed_targets

    def on_enter(
        self,
        ticket: TicketLike,
        *,
        now: datetime,
        resolution_summary: str | None = None,
    ) -> None:
        """Entry side-effects on the ticket. Default: none."""

    def transition(
        self,
        ticket: TicketLike,
        target: str,
        *,
        now: datetime,
        resolution_summary: str | None = None,
        has_technician: bool = False,
    ) -> "TicketState":
        """Validate and apply `self -> target`; return the new state."""
        if not self.can_transition_to(target):
            raise InvalidTransitionError(
                f"cannot transition from '{self.status}' to '{target}'"
            )
        new_state = TicketState.of(target)
        if new_state.requires_technician and not has_technician:
            raise InvalidTransitionError(
                f"cannot move to '{target}' without an assigned technician"
            )
        ticket.status = target
        new_state.on_enter(ticket, now=now, resolution_summary=resolution_summary)
        return new_state

    def assign_technician(self, ticket: TicketLike, *, now: datetime) -> "TicketState":
        """React to a technician being assigned; return the resulting state.

        States that can move to `assigned` do so through the guarded
        `transition()`. Other open states (a reassignment mid-work) keep their
        status and the same state is returned.
        """
        self.ensure_accepts_assignment()
        if self.can_transition_to("assigned"):
            return self.transition(ticket, "assigned", now=now, has_technician=True)
        return self

    def ensure_accepts_assignment(self) -> None:
        if self.is_terminal:
            raise InvalidTransitionError(
                f"cannot assign a technician to a '{self.status}' ticket"
            )


class Submitted(TicketState):
    status = "submitted"
    allowed_targets = frozenset({"triaged", "assigned", "cancelled"})


class Triaged(TicketState):
    status = "triaged"
    allowed_targets = frozenset({"assigned", "cancelled"})


class Assigned(TicketState):
    status = "assigned"
    allowed_targets = frozenset({"in_progress", "cancelled"})
    requires_technician = True


class InProgress(TicketState):
    status = "in_progress"
    allowed_targets = frozenset({"waiting", "resolved", "cancelled"})


class Waiting(TicketState):
    status = "waiting"
    allowed_targets = frozenset({"in_progress", "cancelled"})


class Resolved(TicketState):
    status = "resolved"
    allowed_targets = frozenset({"closed", "in_progress"})
    notifies_requester = True

    def on_enter(
        self,
        ticket: TicketLike,
        *,
        now: datetime,
        resolution_summary: str | None = None,
    ) -> None:
        ticket.resolved_at = now
        if resolution_summary:
            ticket.resolution_summary = resolution_summary


class Closed(TicketState):
    status = "closed"
    notifies_requester = True

    def on_enter(
        self,
        ticket: TicketLike,
        *,
        now: datetime,
        resolution_summary: str | None = None,
    ) -> None:
        ticket.closed_at = now


class Cancelled(TicketState):
    status = "cancelled"
