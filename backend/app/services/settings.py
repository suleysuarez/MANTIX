import os
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from sqlalchemy.exc import IntegrityError

from app.core.authz import AuthContext
from app.core.config import Settings
from app.core.exceptions import ConflictError, NotFoundError, UnprocessableError
from app.jobs import JobSnapshot
from app.models.category import RequestCategory
from app.repositories.settings import SettingsRepository
from app.schemas.settings import (
    DEFAULT_COMPANY,
    AuditEntry,
    AuditHealth,
    CategoryAdmin,
    CategoryCreate,
    CategoryUpdate,
    EnvironmentInfo,
    IntegrationHealth,
    JobHealth,
    OrganizationResponse,
    OrganizationUpdate,
    RoleHealth,
    SystemHealth,
    UserCounts,
)
from app.services.audit import AuditService

API_VERSION = "0.2.0"
#: A slower database answer than this is reported as a warning.
SLOW_DATABASE_MS = 500.0
_ORDER = {"ok": 0, "disabled": 0, "warning": 1, "error": 2}


class SystemSettingsService:
    """Health panel (users, roles, audit, jobs, integrations) and the category catalog."""

    def __init__(
        self,
        repository: SettingsRepository,
        audit: AuditService,
        settings: Settings,
    ):
        self.repository = repository
        self.audit = audit
        self.settings = settings

    # -- health ------------------------------------------------------------------------

    async def health(
        self, jobs: list[JobSnapshot], *, now: datetime | None = None
    ) -> SystemHealth:
        now = now or datetime.now(UTC)
        counts = await self.repository.user_counts()
        integrations = [
            await self._database(),
            self._clerk(),
            self._storage(),
        ]
        job_health = [self._job(job) for job in jobs]
        worst = max(
            [_ORDER[i.status] for i in integrations]
            + [1 for j in job_health if j.last_status == "error"]
            + [0]
        )
        return SystemHealth(
            generated_at=now,
            overall=("ok", "warning", "error")[worst],
            environment=EnvironmentInfo(
                name=self.settings.app_env,
                version=API_VERSION,
                rate_limit_per_minute=self.settings.rate_limit_per_minute,
                max_upload_mb=self.settings.max_upload_mb,
                reminder_interval_minutes=self.settings.reminder_interval_minutes,
                log_level=self.settings.log_level,
                scheduler_enabled=self.settings.scheduler_enabled,
            ),
            users=UserCounts(
                total=counts.total,
                active=counts.active,
                inactive=counts.total - counts.active,
                without_role=counts.without_role,
            ),
            roles=[
                RoleHealth(
                    id=r.id,
                    code=r.code,
                    name=r.name,
                    is_active=r.is_active,
                    users=r.users,
                    permissions=r.permissions,
                )
                for r in await self.repository.role_rows()
            ],
            audit=AuditHealth(
                last_24h=await self.repository.audit_since(now - timedelta(hours=24)),
                recent=[
                    AuditEntry(
                        id=a.id,
                        action=a.action,
                        entity_type=a.entity_type,
                        entity_id=a.entity_id,
                        by=a.by,
                        at=a.at,
                    )
                    for a in await self.repository.audit_recent(10)
                ],
            ),
            jobs=job_health,
            integrations=integrations,
        )

    async def _database(self) -> IntegrationHealth:
        started = time.perf_counter()
        try:
            await self.repository.ping()
        except Exception:  # noqa: BLE001 - any failure means "unreachable"
            return IntegrationHealth(
                key="database",
                name="Base de datos",
                status="error",
                detail="No responde",
            )
        elapsed = round((time.perf_counter() - started) * 1000, 1)
        slow = elapsed > SLOW_DATABASE_MS
        return IntegrationHealth(
            key="database",
            name="Base de datos",
            status="warning" if slow else "ok",
            detail="Respuesta lenta" if slow else "Conectada",
            latency_ms=elapsed,
        )

    def _clerk(self) -> IntegrationHealth:
        """Only checks that the keys are configured; it never calls the provider."""
        has_secret = bool(self.settings.clerk_secret_key)
        has_public = bool(self.settings.clerk_publishable_key)
        if has_secret and has_public:
            return IntegrationHealth(
                key="clerk",
                name="Autenticación (Clerk)",
                status="ok",
                detail="Claves configuradas",
            )
        missing = "clave secreta" if not has_secret else "clave pública"
        return IntegrationHealth(
            key="clerk",
            name="Autenticación (Clerk)",
            status="error",
            detail=f"Falta la {missing}",
        )

    def _storage(self) -> IntegrationHealth:
        path = Path(self.settings.upload_dir)
        if not path.exists():
            return IntegrationHealth(
                key="storage",
                name="Almacenamiento de adjuntos",
                status="warning",
                detail="La carpeta aún no existe; se crea al subir el primer archivo",
            )
        writable = os.access(path, os.W_OK)
        return IntegrationHealth(
            key="storage",
            name="Almacenamiento de adjuntos",
            status="ok" if writable else "error",
            detail=f"Límite de {self.settings.max_upload_mb} MB por archivo"
            if writable
            else "La carpeta no admite escritura",
        )

    @staticmethod
    def _job(job: JobSnapshot) -> JobHealth:
        status = "never" if job.last_ok is None else ("ok" if job.last_ok else "error")
        return JobHealth(
            id=job.id,
            name=job.name,
            running=job.running,
            interval_minutes=job.interval_minutes,
            next_run_at=job.next_run_at,
            last_run_at=job.last_run_at,
            last_status=status,  # type: ignore[arg-type]
            last_detail=job.last_detail,
        )

    # -- request categories ------------------------------------------------------------------

    async def categories(self) -> list[CategoryAdmin]:
        return [
            CategoryAdmin(
                id=c.id,
                code=c.code,
                name=c.name,
                is_active=c.is_active,
                usage=usage,
                created_at=c.created_at,
            )
            for c, usage in await self.repository.list_categories()
        ]

    async def create_category(
        self, payload: CategoryCreate, actor: AuthContext
    ) -> CategoryAdmin:
        if await self.repository.get_category_by_code(payload.code) is not None:
            raise ConflictError(f"category '{payload.code}' already exists")
        try:
            category = await self.repository.add_and_flush(
                RequestCategory(code=payload.code, name=payload.name, is_active=True)
            )
            self.audit.record(
                user_id=actor.id,
                action="category.created",
                entity_type="request_category",
                entity_id=category.id,
                new_values=payload.model_dump(),
            )
            await self.repository.commit()
        except IntegrityError as error:
            await self.repository.rollback()
            raise ConflictError(f"category '{payload.code}' already exists") from error
        return self._category(category, 0)

    async def update_category(
        self, category_id: int, payload: CategoryUpdate, actor: AuthContext
    ) -> CategoryAdmin:
        category = await self._require(category_id)
        changes = payload.model_dump(exclude_unset=True)
        if not changes or any(value is None for value in changes.values()):
            raise UnprocessableError("send name and/or is_active with a value")
        old = {field: getattr(category, field) for field in changes}
        await self.repository.update_fields(category, changes)
        self.audit.record(
            user_id=actor.id,
            action="category.updated",
            entity_type="request_category",
            entity_id=category_id,
            old_values=old,
            new_values=changes,
        )
        await self.repository.commit()
        return self._category(
            category, await self.repository.category_usage(category.code)
        )

    async def delete_category(self, category_id: int, actor: AuthContext) -> None:
        category = await self._require(category_id)
        usage = await self.repository.category_usage(category.code)
        if usage:
            raise ConflictError(
                f"the category is used by {usage} request(s) and cannot be deleted; deactivate it instead"
            )
        self.audit.record(
            user_id=actor.id,
            action="category.deleted",
            entity_type="request_category",
            entity_id=category_id,
            old_values={"code": category.code, "name": category.name},
        )
        await self.repository.delete_category(category)
        await self.repository.commit()

    async def _require(self, category_id: int) -> RequestCategory:
        category = await self.repository.get_category(category_id)
        if category is None:
            raise NotFoundError("category not found")
        return category

    @staticmethod
    def _category(category: RequestCategory, usage: int) -> CategoryAdmin:
        return CategoryAdmin(
            id=category.id,
            code=category.code,
            name=category.name,
            is_active=category.is_active,
            usage=usage,
            created_at=category.created_at,
        )

    # -- organization ------------------------------------------------------------------------

    async def organization(self) -> OrganizationResponse:
        return self._organization(await self.repository.get_organization())

    async def update_organization(
        self, payload: OrganizationUpdate, actor: AuthContext
    ) -> OrganizationResponse:
        current = await self.repository.get_organization()
        old = (
            {
                "company_name": current.company_name,
                "legal_name": current.legal_name,
                "tax_id": current.tax_id,
            }
            if current is not None
            else None
        )
        row = await self.repository.save_organization(
            company_name=payload.company_name,
            legal_name=payload.legal_name,
            tax_id=payload.tax_id,
            user_id=actor.id,
        )
        self.audit.record(
            user_id=actor.id,
            action="organization.updated",
            entity_type="organization_settings",
            entity_id=1,
            old_values=old,
            new_values=payload.model_dump(),
        )
        await self.repository.commit()
        return self._organization(row)

    @staticmethod
    def _organization(row: Any) -> OrganizationResponse:
        if row is None:
            return OrganizationResponse(
                company_name=DEFAULT_COMPANY,
                legal_name=None,
                tax_id=None,
                configured=False,
                updated_at=None,
            )
        return OrganizationResponse(
            company_name=row.company_name,
            legal_name=row.legal_name,
            tax_id=row.tax_id,
            configured=True,
            updated_at=row.updated_at,
        )
