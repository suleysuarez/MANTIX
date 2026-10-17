"""Fields only some roles may read (money): hidden, not merely left out of the screen.

The screens also hide them, but the API is the barrier: a Solicitante who calls the endpoint
directly gets `null` for the purchase cost of equipment and the hourly rate of technicians.
"""

from typing import TypeVar

from pydantic import BaseModel

from app.core.authz import AuthContext

T = TypeVar("T", bound=BaseModel)


def hide_unless(
    actor: AuthContext, permission: str, items: list[T], field: str
) -> list[T]:
    """`items` with `field` set to `None` unless `actor` holds `permission`."""
    if actor.has_permission(permission):
        return items
    return [item.model_copy(update={field: None}) for item in items]


def hide_one_unless(actor: AuthContext, permission: str, item: T, field: str) -> T:
    return hide_unless(actor, permission, [item], field)[0]
