"""Query-string pagination for listings.

Every listing returns a plain JSON array and describes the page in headers, so
existing clients keep working while new ones can page through results:

    X-Total-Count, X-Page, X-Page-Size, X-Total-Pages

Parameters: `page` + `size` (preferred), `sort` (`field` or `-field`), and the
deprecated `limit` / `offset` pair.
"""

from collections.abc import Callable
from typing import Any

from fastapi import Query, Response

from app.core.pagination import DEFAULT_SIZE, MAX_SIZE, PageParams
from app.repositories.base import Page

PAGINATION_HEADERS = ["X-Total-Count", "X-Page", "X-Page-Size", "X-Total-Pages"]


def page_params(default_size: int = DEFAULT_SIZE) -> Callable[..., PageParams]:
    """Dependency factory; `default_size` lets legacy listings keep their default."""

    def dependency(
        page: int = Query(default=1, ge=1, description="1-based page number"),
        size: int | None = Query(
            default=None, ge=1, le=MAX_SIZE, description="Items per page"
        ),
        sort: str | None = Query(
            default=None,
            max_length=50,
            pattern=r"^[-+]?[a-z_]+$",
            description="Sort field; prefix with `-` for descending",
        ),
        limit: int | None = Query(
            default=None, ge=1, le=MAX_SIZE, deprecated=True, description="Use `size`"
        ),
        offset: int | None = Query(
            default=None, ge=0, deprecated=True, description="Use `page`"
        ),
    ) -> PageParams:
        return PageParams(
            page=page,
            size=limit or size or default_size,
            sort=sort,
            offset=offset,
        )

    return dependency


def set_page_headers(response: Response, page: Page[Any]) -> None:
    response.headers["X-Total-Count"] = str(page.total)
    response.headers["X-Page"] = str(page.page)
    response.headers["X-Page-Size"] = str(page.size)
    response.headers["X-Total-Pages"] = str(page.pages)
