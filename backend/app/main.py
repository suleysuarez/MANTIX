from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.routes.admin import router as admin_router
from app.api.routes.auth import router as auth_router
from app.api.routes.equipment import location_router
from app.api.routes.equipment import router as equipment_router
from app.api.routes.maintenance import router as maintenance_router
from app.api.routes.notification import router as notification_router
from app.api.routes.technician import router as technician_router
from app.core.config import get_settings
from app.core.exceptions import AppError
from app.core.middleware import (
    RateLimitMiddleware,
    RequestLoggingMiddleware,
    configure_logging,
)

settings = get_settings()
configure_logging(settings.log_level)

# La documentación interactiva solo se expone fuera de producción.
app = FastAPI(
    title="Technology Equipment Maintenance API",
    version="0.1.0",
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    expose_headers=["X-Request-ID", "Retry-After"],
)
# Se añaden después de CORS para quedar por fuera: así incluso los 429 llevan
# cabeceras CORS y el navegador puede leerlos.
app.add_middleware(RateLimitMiddleware, limit_per_minute=settings.rate_limit_per_minute)
app.add_middleware(RequestLoggingMiddleware)


@app.exception_handler(AppError)
async def app_error_handler(_: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


app.include_router(auth_router)
app.include_router(admin_router)
app.include_router(equipment_router)
app.include_router(location_router)
app.include_router(technician_router)
app.include_router(maintenance_router)
app.include_router(notification_router)


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok", "environment": settings.app_env}
