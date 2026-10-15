"""Role inheritance: a role has what it grants itself plus everything its ancestors grant.

One place resolves it, so the request path (ORM objects of the signed-in user), the roles
screen and the tests all agree. The functions here are pure and work on plain mappings
(`code -> parent code`, `code -> own permission codes`); `chain_of` adapts ORM roles.

Cycles must never exist (the API refuses to create one), but a corrupt row must not hang or
widen access either: walking stops at the first repeated role, so a cycle grants nothing extra.
"""

import logging
from collections.abc import Iterable, Mapping
from functools import lru_cache
from typing import Any

logger = logging.getLogger("mantix.rbac")

#: Deepest inheritance chain accepted when creating roles (system chain is 4 deep).
MAX_DEPTH = 6

Chain = tuple[tuple[str, frozenset[str]], ...]


class RoleCycleError(ValueError):
    """Raised when a parent assignment would make a role its own ancestor."""


def lineage(code: str, parents: Mapping[str, str | None]) -> list[str]:
    """`code` followed by its ancestors, nearest first. Raises on a cycle."""
    seen: list[str] = []
    current: str | None = code
    while current is not None:
        if current in seen:
            raise RoleCycleError(
                "la herencia de roles no puede tener ciclos: "
                + " → ".join([*seen, current])
            )
        seen.append(current)
        current = parents.get(current)
    return seen


def would_create_cycle(
    role_code: str, new_parent: str | None, parents: Mapping[str, str | None]
) -> bool:
    """Whether making `new_parent` the parent of `role_code` closes a loop."""
    if new_parent is None:
        return False
    if new_parent == role_code:
        return True
    try:
        return role_code in lineage(new_parent, parents)
    except RoleCycleError:
        return True


def depth_after(
    role_code: str, new_parent: str | None, parents: Mapping[str, str | None]
) -> int:
    """Length of the chain `role_code` would have under `new_parent` (itself included)."""
    if new_parent is None:
        return 1
    return len(lineage(new_parent, parents)) + 1


@lru_cache(maxsize=512)
def _union(chain: Chain) -> frozenset[str]:
    result: frozenset[str] = frozenset()
    for _, own in chain:
        result |= own
    return result


def effective_from_chain(chain: Chain) -> frozenset[str]:
    """Union of the permissions along a chain. Cached by *content*, so a changed grant or
    parent produces a different key: nothing can be stale, in any worker."""
    return _union(chain)


def effective(
    code: str,
    parents: Mapping[str, str | None],
    own: Mapping[str, frozenset[str]],
) -> frozenset[str]:
    chain = tuple((c, frozenset(own.get(c, ()))) for c in lineage(code, parents))
    return effective_from_chain(chain)


def provenance(
    code: str,
    parents: Mapping[str, str | None],
    own: Mapping[str, frozenset[str]],
) -> dict[str, str]:
    """For each effective permission, the nearest role in the lineage that grants it
    (the role itself for its own permissions): what the roles screen shows as "heredado de"."""
    result: dict[str, str] = {}
    for ancestor in lineage(code, parents):
        for permission in own.get(ancestor, ()):
            result.setdefault(permission, ancestor)
    return result


def chain_of(role: Any) -> Chain:
    """The `(code, own permission codes)` chain of an ORM role, nearest first.

    Inactive roles and inactive permissions grant nothing, and an inactive ancestor cuts the
    chain (its own parents are not inherited through it). Objects without a `parent`
    attribute (plain test doubles) simply have no ancestors.
    """
    chain: list[tuple[str, frozenset[str]]] = []
    seen: set[int] = set()
    current: Any = role
    while current is not None and getattr(current, "is_active", True):
        if id(current) in seen:
            logger.warning(
                "role inheritance cycle at %s; ignoring ancestors", current.code
            )
            break
        seen.add(id(current))
        own = frozenset(
            permission.code
            for permission in getattr(current, "permissions", ())
            if getattr(permission, "is_active", True)
        )
        chain.append((current.code, own))
        current = getattr(current, "parent", None)
    return tuple(chain)


def effective_for_roles(roles: Iterable[Any]) -> frozenset[str]:
    """Effective permission codes of several ORM roles (a user may hold more than one)."""
    result: frozenset[str] = frozenset()
    for role in roles:
        result |= effective_from_chain(chain_of(role))
    return result


def effective_permission_objects(roles: Iterable[Any]) -> dict[str, Any]:
    """`code -> Permission` for the roles and their ancestors (names for `/auth/me`)."""
    found: dict[str, Any] = {}
    for role in roles:
        current: Any = role
        seen: set[int] = set()
        while current is not None and getattr(current, "is_active", True):
            if id(current) in seen:
                break
            seen.add(id(current))
            for permission in getattr(current, "permissions", ()):
                if getattr(permission, "is_active", True):
                    found.setdefault(permission.code, permission)
            current = getattr(current, "parent", None)
    return found
