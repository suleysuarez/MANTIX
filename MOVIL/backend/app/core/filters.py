"""Shared handling of list filters that accept several values."""

from app.core.exceptions import UnprocessableError

#: Most values a single filter may carry (`equipment_type_id=1&equipment_type_id=2…`, `status=a,b`).
MAX_FILTER_VALUES = 20


def split_filter_list(value: str | None, field: str) -> list[str]:
    """`"a, b,,a"` -> `["a", "b"]`: comma-separated, trimmed, without blanks or repeats.

    More than `MAX_FILTER_VALUES` distinct values is a 422 with a stable code.
    """
    items = list(
        dict.fromkeys(item.strip() for item in (value or "").split(",") if item.strip())
    )
    if len(items) > MAX_FILTER_VALUES:
        raise UnprocessableError(
            f"the filter '{field}' accepts at most {MAX_FILTER_VALUES} values",
            code="filter_too_many_values",
        )
    return items
