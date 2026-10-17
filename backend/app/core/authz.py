"""Authorization context handed to services.

Routes resolve the signed-in user into an `AuthContext` (through the
`require_permission` / `require_role` dependencies) and pass it to the
service. Services ask the context questions (`is_elevated`, `has_role`) instead
of inspecting ORM role objects, so role knowledge lives in exactly one place.
"""

from collections.abc import Iterable
from dataclasses import dataclass, field
from typing import Any

from app.core.exceptions import ForbiddenError
from app.core.rbac import effective_for_roles
from app.core.scope import ScopeKind, kind_from_permissions
from app.models.auth import User

ADMIN = "ADMIN"
SUPERVISOR = "SUPERVISOR"
TECHNICIAN = "TECHNICIAN"
EMPLOYEE = "EMPLOYEE"
AUDITOR = "AUDITOR"


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

    def has_role(self, *codes: str) -> bool:
        return not self.roles.isdisjoint(codes)

    def has_permission(self, code: str) -> bool:
        return code in self.permissions

    def scope_kind(self, resource: str) -> ScopeKind:
        """How much of `resource` this person may see (decided by permissions)."""
        return kind_from_permissions(resource, self.permissions) or ScopeKind.NONE

    def ensure_can_change_roles(
        self, roles: Iterable[Any], *, target_user_id: int | None
    ) -> None:
        """The rules for giving or taking away roles, one place for every route that does it.

        Only whoever holds `usuarios:asignar` may; nobody changes their own roles (nobody
        promotes themselves); and a role can only be given or taken away by someone who
        already has every permission it carries (a role cannot grant what its giver lacks).
        """
        self.require("usuarios:asignar", "Solo un administrador puede asignar roles.")
        if target_user_id is not None and target_user_id == self.id:
            raise ForbiddenError(
                "No puedes cambiar tus propios roles. Pídeselo a otro administrador."
            )
        for role in roles:
            if not effective_for_roles([role]) <= self.permissions:
                raise ForbiddenError(
                    f"No puedes asignar ni quitar el rol «{role.name}»: "
                    "concede permisos que tú no tienes."
                )

    def require(self, code: str, detail: str | None = None) -> None:
        """Raise a 403 unless this person holds `code` (defence in depth for services)."""
        if code not in self.permissions:
            raise ForbiddenError(
                detail or "No tienes permiso para realizar esta acción."
            )

    @classmethod
    def for_roles(cls, user: User, *role_codes: str) -> "AuthContext":
        """A context holding the default permissions of the given system roles (tests, tools)."""
        from app.core.permissions import effective_for_system_roles

        return cls(
            user=user,
            roles=frozenset(role_codes),
            permissions=effective_for_system_roles(*role_codes),
        )
