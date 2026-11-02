"""Data scope: which rows of a resource a person may see.

It is derived from *permissions*, never from role names, so a custom role works the same way:
`<recurso>:ver_todos` → everything, `<recurso>:ver_asignados` → what is assigned to them (and
what they requested), `<recurso>:ver` → only what they requested, nothing → nothing.

Repositories take a `DataScope` as a required argument and apply it to their queries, so a new
query cannot forget to filter.
"""

from dataclasses import dataclass
from enum import StrEnum


class ScopeKind(StrEnum):
    ALL = "all"
    ASSIGNED = "assigned"
    OWN = "own"
    NONE = "none"


@dataclass(frozen=True, slots=True)
class DataScope:
    kind: ScopeKind
    user_id: int | None = None
    #: Technician profile of the person, when the scope depends on assignments.
    technician_id: int | None = None

    @classmethod
    def everything(cls) -> "DataScope":
        return cls(ScopeKind.ALL)

    @classmethod
    def nothing(cls) -> "DataScope":
        return cls(ScopeKind.NONE)

    @property
    def sees_everything(self) -> bool:
        return self.kind is ScopeKind.ALL


def kind_from_permissions(
    resource: str, permissions: frozenset[str]
) -> ScopeKind | None:
    """The widest scope the permissions grant for `resource`, or `None` if they say nothing."""
    if f"{resource}:ver_todos" in permissions:
        return ScopeKind.ALL
    if f"{resource}:ver_asignados" in permissions:
        return ScopeKind.ASSIGNED
    if f"{resource}:ver" in permissions:
        return ScopeKind.OWN
    return None
