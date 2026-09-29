"""Composition root: FastAPI `Depends` providers for repositories and services.

Wiring is one chain per request -- `get_db` -> repositories/audit ->
service -- so every collaborator shares the same `AsyncSession` (and therefore
one transaction). Routes depend on the service providers only and never see the
session. Tests can swap any link with `app.dependency_overrides`, or build a
service directly from fakes.
"""

from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.repositories.admin import AdminRepository
from app.repositories.equipment import EquipmentRepository
from app.repositories.maintenance import MaintenanceRepository
from app.repositories.technician import TechnicianRepository
from app.services.admin import AdminUserService
from app.services.audit import AuditService
from app.services.equipment import EquipmentService
from app.services.maintenance import MaintenanceService
from app.services.notification import NotificationService
from app.services.technician import TechnicianService

Session = Depends(get_db)


def get_audit_service(session: AsyncSession = Session) -> AuditService:
    return AuditService(session)


def get_notification_service(session: AsyncSession = Session) -> NotificationService:
    return NotificationService(session)


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
