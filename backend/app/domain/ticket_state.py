"""State pattern for the maintenance ticket lifecycle.

Each status is a `TicketState` object that owns three things the service used
to encode in scattered `if` chains:

* which statuses it may move to (`allowed_targets`),
* what happens to the ticket when it is entered (`on_enter`),
* how it reacts to a technician being assigned (`status_after_assignment`).

The module is pure domain logic: no database, no HTTP. Adding a status means
adding one class and registering it, without touching `MaintenanceService`.
"""

from datetime import datetime
from typing import ClassVar, Protocol

from app.core.exceptions import BusinessRuleError


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

    _registry: ClassVar[dict[str, "TicketState"]] = {}

    def __init_subclass__(cls, **kwargs) -> None:
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

    def status_after_assignment(self) -> str | None:
        """Status the ticket auto-advances to when a technician is assigned."""
        return None

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
    ) -> "TicketState":
        """Validate and apply `self -> target`; return the new state."""
        if not self.can_transition_to(target):
            raise BusinessRuleError(
                f"cannot transition from '{self.status}' to '{target}'"
            )
        new_state = TicketState.of(target)
        ticket.status = target
        new_state.on_enter(ticket, now=now, resolution_summary=resolution_summary)
        return new_state

    def assign_technician(self, ticket: TicketLike, *, now: datetime) -> str | None:
        """Apply the assignment side-effect on the ticket's status.

        Assignment is a domain event, not a user-driven transition: intake
        states jump straight to `assigned` even though that edge is not in
        `allowed_targets`. Returns the new status, or None if unchanged.
        """
        # NOTE (design trade-off): assignment deliberately jumps
        # Submitted/Triaged -> Assigned *outside* the guarded `transition()`
        # graph. Submitted's only graph edges are triaged/cancelled, so the
        # jump would be rejected if routed through it. It lives in this
        # separate method to preserve the pre-existing behaviour (and the unit
        # tests that pin it: assigning a technician auto-moves a ticket to
        # 'assigned') rather than widening the graph for every caller.
        # TODO: if intake should be enforceable, add "assigned" to Submitted's
        # allowed_targets and route this through `transition()`; that would
        # also let users POST /status directly to 'assigned', so decide
        # deliberately.
        self.ensure_accepts_assignment()
        target = self.status_after_assignment()
        if target is None:
            return None
        ticket.status = target
        TicketState.of(target).on_enter(ticket, now=now)
        return target

    def ensure_accepts_assignment(self) -> None:
        if self.is_terminal:
            raise BusinessRuleError(
                f"cannot assign a technician to a '{self.status}' ticket"
            )


class Submitted(TicketState):
    status = "submitted"
    allowed_targets = frozenset({"triaged", "cancelled"})

    def status_after_assignment(self) -> str | None:
        return "assigned"


class Triaged(TicketState):
    status = "triaged"
    allowed_targets = frozenset({"assigned", "cancelled"})

    def status_after_assignment(self) -> str | None:
        return "assigned"


class Assigned(TicketState):
    status = "assigned"
    allowed_targets = frozenset({"in_progress", "cancelled"})


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

    def on_enter(self, ticket, *, now, resolution_summary=None) -> None:
        ticket.resolved_at = now
        if resolution_summary:
            ticket.resolution_summary = resolution_summary


class Closed(TicketState):
    status = "closed"
    notifies_requester = True

    def on_enter(self, ticket, *, now, resolution_summary=None) -> None:
        ticket.closed_at = now


class Cancelled(TicketState):
    status = "cancelled"
