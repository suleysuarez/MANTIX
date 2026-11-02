"""Global exception handlers: one error shape for every failure.

{
  "detail": "human readable message",      # kept for existing clients
  "code": "not_found",                      # stable machine-readable code
  "errors": [{"field": "title", "message": "...", "type": "..."}],  # 422 only
  "request_id": "3f2c..."                   # matches the X-Request-ID header
}
"""

import logging
from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy.exc import IntegrityError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.access_audit import record_denial
from app.core.exceptions import AppError

logger = logging.getLogger("mantix.errors")

_STATUS_CODES = {
    status.HTTP_400_BAD_REQUEST: "bad_request",
    status.HTTP_401_UNAUTHORIZED: "unauthorized",
    status.HTTP_403_FORBIDDEN: "forbidden",
    status.HTTP_404_NOT_FOUND: "not_found",
    status.HTTP_405_METHOD_NOT_ALLOWED: "method_not_allowed",
    status.HTTP_409_CONFLICT: "conflict",
    413: "payload_too_large",
    status.HTTP_415_UNSUPPORTED_MEDIA_TYPE: "unsupported_media_type",
    422: "validation_error",
    status.HTTP_429_TOO_MANY_REQUESTS: "rate_limited",
}


class FieldError(BaseModel):
    field: str = Field(examples=["title"])
    message: str = Field(examples=["String should have at least 1 character"])
    type: str = Field(examples=["string_too_short"])


class ErrorResponse(BaseModel):
    """Uniform error body returned by every endpoint."""

    detail: str = Field(examples=["maintenance request not found"])
    code: str = Field(examples=["not_found"])
    errors: list[FieldError] | None = None
    request_id: str | None = Field(default=None, examples=["3f2c9d1e0b7a4c58"])


def error_responses(*codes: int) -> dict[int | str, dict[str, Any]]:
    """`responses=` mapping documenting the shared error body in OpenAPI."""
    return {
        code: {"model": ErrorResponse, "description": _describe(code)} for code in codes
    }


def _describe(code: int) -> str:
    return _STATUS_CODES.get(code, "error").replace("_", " ").capitalize()


def _request_id(request: Request) -> str | None:
    return getattr(request.state, "request_id", None) or request.headers.get(
        "X-Request-ID"
    )


def error_body(
    request: Request,
    *,
    detail: str,
    code: str,
    errors: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    return {
        "detail": detail,
        "code": code,
        "errors": errors,
        "request_id": _request_id(request),
    }


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(request: Request, exc: AppError) -> JSONResponse:
        if exc.status_code == status.HTTP_403_FORBIDDEN:
            await record_denial(request, exc.detail)
        return JSONResponse(
            status_code=exc.status_code,
            content=error_body(request, detail=exc.detail, code=exc.code),
        )

    @app.exception_handler(StarletteHTTPException)
    async def handle_http_exception(
        request: Request, exc: StarletteHTTPException
    ) -> JSONResponse:
        detail = exc.detail if isinstance(exc.detail, str) else "request failed"
        if exc.status_code == status.HTTP_403_FORBIDDEN:
            await record_denial(request, detail)
        return JSONResponse(
            status_code=exc.status_code,
            content=error_body(
                request,
                detail=detail,
                code=_STATUS_CODES.get(exc.status_code, "http_error"),
            ),
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        # Never echo `input`/`ctx`: they can contain the submitted values.
        errors = [
            {
                "field": ".".join(str(part) for part in error["loc"][1:])
                or str(error["loc"][0]),
                "message": str(error["msg"]),
                "type": str(error["type"]),
            }
            for error in exc.errors()
        ]
        return JSONResponse(
            status_code=422,
            content=error_body(
                request,
                detail="request validation failed",
                code="validation_error",
                errors=errors,
            ),
        )

    @app.exception_handler(IntegrityError)
    async def handle_integrity_error(
        request: Request, exc: IntegrityError
    ) -> JSONResponse:
        logger.warning("integrity_error id=%s", _request_id(request), exc_info=exc)
        return JSONResponse(
            status_code=status.HTTP_409_CONFLICT,
            content=error_body(
                request,
                detail="the operation conflicts with existing data",
                code="conflict",
            ),
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("unhandled_error id=%s", _request_id(request), exc_info=exc)
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content=error_body(
                request, detail="internal server error", code="internal_error"
            ),
        )
