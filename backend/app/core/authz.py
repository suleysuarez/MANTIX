"""Authorization context handed to services.

Routes resolve the signed-in user into an `AuthContext` (through the
`require_permission` / `require_role` dependencies) and pass it to the
service. Services ask the context questions (`is_elevated`, `has_role`) instead
of inspecting ORM role objects, so role knowledge lives in exactly one place.
"""

from dataclasses import dataclass, field

from app.core.rbac import effective_for_roles
from app.core.scope import ScopeKind, kind_from_permissions
from app.models.auth import User

ADMIN = "ADMIN"
SUPERVISOR = "SUPERVISOR"
TECHNICIAN = "TECHNICIAN"
EMPLOYEE = "EMPLOYEE"
AUDITOR = "AUDITOR"

#: Roles that see and manage every ticket, not only their own.
ELEVATED_ROLES = frozenset({ADMIN, SUPERVISOR})


@dataclass(frozen=True, slots=True)
class AuthContext:
    user: User
    roles: frozenset[str] = field(default_factory=frozenset)
    permissions: frozenset[str] = field(default_factory=frozenset)

    @classmethod
    def from_user(cls, user: User) -> "AuthContext":
        """Build the context from the user's *active* roles; each role brings its own
        permissions and those of its ancestors (see `app.core.rbac`)."""
        active_roles = [role for role in user.roles if role.is_active]
        return cls(
            user=user,
            roles=frozenset(role.code for role in active_roles),
            permissions=effective_for_roles(active_roles),
        )

    @property
    def id(self) -> int:
        return self.user.id

    @property
    def is_elevated(self) -> bool:
        return not self.roles.isdisjoint(ELEVATED_ROLES)

    def has_role(self, *codes: str) -> bool:
        return not self.roles.isdisjoint(codes)

    def has_permission(self, code: str) -> bool:
        return code in self.permissions

    def scope_kind(self, resource: str) -> ScopeKind:
        """How much of `resource` this person may see (decided by permissions)."""
        kind = kind_from_permissions(resource, self.permissions)
        if kind is not None:
            return kind
        # Legacy fallback for contexts built from the old dotted permissions only; it goes
        # away together with those permissions at the end of the RBAC rollout.
        if self.is_elevated:
            return ScopeKind.ALL
        return ScopeKind.ASSIGNED if self.has_role(TECHNICIAN) else ScopeKind.OWN
