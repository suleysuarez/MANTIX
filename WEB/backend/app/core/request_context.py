"""Per-request metadata (client IP, user agent) for the audit trail.

The logging middleware stores it once per request in a `ContextVar`, so the
audit repository can stamp every row without each service passing the request
around. Outside a request (scheduled jobs) nothing is set and the columns stay
empty.
"""

from contextvars import ContextVar
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class RequestInfo:
    ip_address: str | None
    user_agent: str | None
    request_id: str | None


_current: ContextVar[RequestInfo | None] = ContextVar("request_info", default=None)


def set_request_info(info: RequestInfo | None) -> None:
    _current.set(info)


def get_request_info() -> RequestInfo | None:
    return _current.get()
