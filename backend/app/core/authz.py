"""Authorization context handed to services.

Routes resolve the signed-in user into an `AuthContext` (through the
`require_permission` / `require_role` dependencies) and pass it to the
service. Services ask the context questions (`is_elevated`, `has_role`) instead
of inspecting ORM role objects, so role knowledge lives in exactly one place.
"""

from dataclasses import dataclass, field

from app.models.auth import User

ADMIN = "ADMIN"
SUPERVISOR = "SUPERVISOR"
TECHNICIAN = "TECHNICIAN"
EMPLOYEE = "EMPLOYEE"

#: Roles that see and manage every ticket, not only their own.
ELEVATED_ROLES = frozenset({ADMIN, SUPERVISOR})


@dataclass(frozen=True, slots=True)
class AuthContext:
    user: User
    roles: frozenset[str] = field(default_factory=frozenset)
    permissions: frozenset[str] = field(default_factory=frozenset)

    @classmethod
    def from_user(cls, user: User) -> "AuthContext":
        """Build the context from the user's *active* roles and permissions."""
        active_roles = [role for role in user.roles if role.is_active]
        return cls(
            user=user,
            roles=frozenset(role.code for role in active_roles),
            permissions=frozenset(
                permission.code
                for role in active_roles
                for permission in role.permissions
                if permission.is_active
            ),
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
