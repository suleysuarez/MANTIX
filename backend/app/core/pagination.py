"""Framework-agnostic pagination value object shared by services and repos."""

from dataclasses import dataclass

DEFAULT_SIZE = 20
MAX_SIZE = 500


@dataclass(frozen=True, slots=True)
class PageParams:
    page: int = 1
    size: int = DEFAULT_SIZE
    sort: str | None = None
    #: Legacy `offset` (wins over `page` when given), kept for older clients.
    offset: int | None = None


DEFAULT_PAGE = PageParams()
