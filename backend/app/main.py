from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.routes.admin import router as admin_router
from app.api.routes.auth import router as auth_router
from app.api.routes.equipment import location_router
from app.api.routes.equipment import router as equipment_router
from app.api.routes.maintenance import router as maintenance_router
from app.api.routes.technician import router as technician_router
from app.core.config import get_settings
from app.core.exceptions import AppError

settings = get_settings()
app = FastAPI(title="Technology Equipment Maintenance API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(AppError)
async def app_error_handler(_: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


app.include_router(auth_router)
app.include_router(admin_router)
app.include_router(equipment_router)
app.include_router(location_router)
app.include_router(technician_router)
app.include_router(maintenance_router)


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok", "environment": settings.app_env}
