from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.pagination import PAGINATION_HEADERS
from app.api.routes.admin import router as admin_router
from app.api.routes.auth import router as auth_router
from app.api.routes.dashboard import router as dashboard_router
from app.api.routes.equipment import location_router
from app.api.routes.equipment import router as equipment_router
from app.api.routes.maintenance import router as maintenance_router
from app.api.routes.notification import router as notification_router
from app.api.routes.priority import router as priority_router
from app.api.routes.report import import_router
from app.api.routes.report import router as report_router
from app.api.routes.technician import router as technician_router
from app.core.config import get_settings
from app.core.errors import error_responses, register_exception_handlers
from app.core.middleware import (
    RateLimitMiddleware,
    RequestLoggingMiddleware,
    configure_logging,
)

settings = get_settings()
configure_logging(settings.log_level)

DESCRIPTION = """
REST API for **Mantix**, a technology-equipment maintenance system.

* **Authentication** is delegated to Clerk: send `Authorization: Bearer <session JWT>`.
  Clerk issues short-lived tokens and handles refresh, rotation and revocation.
* **Authorization** is role and permission based (ADMIN, SUPERVISOR, TECHNICIAN,
  EMPLOYEE); each endpoint lists the permission it needs in the README matrix.
* **Listings** accept `page`, `size`, `sort` (`field` / `-field`) and `search`, and
  report pagination in the `X-Total-Count`, `X-Page`, `X-Page-Size` and
  `X-Total-Pages` response headers.
* **Errors** always use the same JSON body (`detail`, `code`, `errors`, `request_id`).
"""

TAGS_METADATA = [
    {"name": "authentication", "description": "Current user, roles and permissions."},
    {"name": "administration", "description": "User onboarding and role assignment."},
    {"name": "equipment", "description": "Equipment catalog, locations and custody."},
    {
        "name": "maintenance",
        "description": "Tickets, their state machine, assignments and work records.",
    },
    {"name": "technicians", "description": "Technician profiles."},
    {
        "name": "dashboard",
        "description": "Aggregated operational metrics.",
    },
    {
        "name": "reports",
        "description": "Downloadable reports in CSV, Excel and PDF.",
    },
    {
        "name": "data-exchange",
        "description": "Bulk import of equipment from CSV or Excel.",
    },
    {"name": "priorities", "description": "Managed catalog of ticket priorities."},
    {"name": "notifications", "description": "In-app notification inbox."},
    {"name": "system", "description": "Health check."},
]

# La documentación interactiva solo se expone fuera de producción.
app = FastAPI(
    title="Mantix - Technology Equipment Maintenance API",
    summary="Equipment, tickets, technicians and maintenance history.",
    description=DESCRIPTION,
    version="0.2.0",
    openapi_tags=TAGS_METADATA,
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    expose_headers=[
        "X-Request-ID",
        "Retry-After",
        "Content-Disposition",
        *PAGINATION_HEADERS,
    ],
)
# Se añaden después de CORS para quedar por fuera: así incluso los 429 llevan
# cabeceras CORS y el navegador puede leerlos.
app.add_middleware(RateLimitMiddleware, limit_per_minute=settings.rate_limit_per_minute)
app.add_middleware(RequestLoggingMiddleware)

register_exception_handlers(app)

#: Documented on every protected endpoint (the body is `ErrorResponse`).
COMMON_ERRORS = error_responses(401, 403, 422, 429)

API_ROUTERS = (
    auth_router,
    admin_router,
    equipment_router,
    location_router,
    technician_router,
    maintenance_router,
    priority_router,
    dashboard_router,
    report_router,
    import_router,
    notification_router,
)

for router in API_ROUTERS:
    app.include_router(router, responses=COMMON_ERRORS)


@app.get("/health", tags=["system"], summary="Liveness check")
def health() -> dict[str, str]:
    return {"status": "ok", "environment": settings.app_env}
