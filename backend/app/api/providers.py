"""Composition root: FastAPI `Depends` providers for repositories and services.

Wiring is one chain per request -- `get_db` (session) -> `get_*_repository`
-> `get_*_service` -- so every collaborator shares the same `AsyncSession` (and
therefore one transaction). Services never build repositories themselves, and
routes depend on service providers only. Tests can swap any link with
`app.dependency_overrides`, or build a service directly from fakes.
"""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.repositories.admin import AdminRepository
from app.repositories.audit import AuditRepository
from app.repositories.auth import AuthRepository
from app.repositories.dashboard import DashboardRepository
from app.repositories.equipment import EquipmentRepository
from app.repositories.maintenance import MaintenanceRepository
from app.repositories.notification import NotificationRepository
from app.repositories.priority import PriorityRepository
from app.repositories.technician import TechnicianRepository
from app.services.admin import AdminUserService
from app.services.audit import AuditService
from app.services.auth import ClerkAuthService
from app.services.dashboard import DashboardService
from app.services.equipment import EquipmentService
from app.services.maintenance import MaintenanceService
from app.services.notification import NotificationService
from app.services.notification_inbox import NotificationInboxService
from app.services.priority import PriorityService
from app.services.technician import TechnicianService

Session = Depends(get_db)


# -- Repositories ----------------------------------------------------------


def get_audit_repository(session: AsyncSession = Session) -> AuditRepository:
    return AuditRepository(session)


def get_auth_repository(session: AsyncSession = Session) -> AuthRepository:
    return AuthRepository(session)


def get_notification_repository(
    session: AsyncSession = Session,
) -> NotificationRepository:
    return NotificationRepository(session)


def get_priority_repository(session: AsyncSession = Session) -> PriorityRepository:
    return PriorityRepository(session)


def get_dashboard_repository(session: AsyncSession = Session) -> DashboardRepository:
    return DashboardRepository(session)


def get_maintenance_repository(
    session: AsyncSession = Session,
) -> MaintenanceRepository:
    return MaintenanceRepository(session)


def get_equipment_repository(session: AsyncSession = Session) -> EquipmentRepository:
    return EquipmentRepository(session)


def get_technician_repository(
    session: AsyncSession = Session,
) -> TechnicianRepository:
    return TechnicianRepository(session)


def get_admin_repository(session: AsyncSession = Session) -> AdminRepository:
    return AdminRepository(session)


# -- Services --------------------------------------------------------------


def get_audit_service(
    repository: Annotated[AuditRepository, Depends(get_audit_repository)],
) -> AuditService:
    return AuditService(repository)


def get_notification_service(
    repository: Annotated[NotificationRepository, Depends(get_notification_repository)],
) -> NotificationService:
    return NotificationService(repository)


def get_auth_service(
    repository: Annotated[AuthRepository, Depends(get_auth_repository)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> ClerkAuthService:
    return ClerkAuthService(repository, settings)


def get_notification_inbox_service(
    repository: Annotated[NotificationRepository, Depends(get_notification_repository)],
) -> NotificationInboxService:
    return NotificationInboxService(repository)


def get_maintenance_service(
    repository: Annotated[MaintenanceRepository, Depends(get_maintenance_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
    notifications: Annotated[NotificationService, Depends(get_notification_service)],
) -> MaintenanceService:
    return MaintenanceService(repository, audit, notifications)


def get_equipment_service(
    repository: Annotated[EquipmentRepository, Depends(get_equipment_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
) -> EquipmentService:
    return EquipmentService(repository, audit)


def get_technician_service(
    repository: Annotated[TechnicianRepository, Depends(get_technician_repository)],
) -> TechnicianService:
    return TechnicianService(repository)


def get_admin_user_service(
    repository: Annotated[AdminRepository, Depends(get_admin_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
    notifications: Annotated[NotificationService, Depends(get_notification_service)],
) -> AdminUserService:
    return AdminUserService(repository, audit, notifications)


def get_priority_service(
    repository: Annotated[PriorityRepository, Depends(get_priority_repository)],
    audit: Annotated[AuditService, Depends(get_audit_service)],
) -> PriorityService:
    return PriorityService(repository, audit)


def get_dashboard_service(
    repository: Annotated[DashboardRepository, Depends(get_dashboard_repository)],
) -> DashboardService:
    return DashboardService(repository)
