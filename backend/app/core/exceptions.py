"""Domain exceptions raised by the service layer.

Services should raise these instead of `fastapi.HTTPException` directly, so
that business logic stays decoupled from HTTP concerns. `app.main` registers
a single exception handler that maps each of these to the appropriate status
code, which keeps error handling centralized instead of repeated per route.
"""

from fastapi import status


class AppError(Exception):
    """Base class for all domain errors. Carries the HTTP status to map to."""

    status_code: int = status.HTTP_500_INTERNAL_SERVER_ERROR

    def __init__(self, detail: str):
        self.detail = detail
        super().__init__(detail)


class NotFoundError(AppError):
    status_code = status.HTTP_404_NOT_FOUND


class ConflictError(AppError):
    status_code = status.HTTP_409_CONFLICT


class ForbiddenError(AppError):
    status_code = status.HTTP_403_FORBIDDEN


class BusinessRuleError(AppError):
    """A request is well-formed but violates a domain/workflow rule."""

    status_code = status.HTTP_409_CONFLICT
