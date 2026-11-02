from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Identity,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.audit import AuditLog
    from app.models.equipment import EquipmentCustodyHistory
    from app.models.maintenance import MaintenanceRequest
    from app.models.notification import Notification
    from app.models.technician import Technician


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    email: Mapped[str] = mapped_column(
        String(255), unique=True, index=True, nullable=False
    )
    clerk_user_id: Mapped[str | None] = mapped_column(
        String(255), unique=True, index=True, nullable=True
    )
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    employee_code: Mapped[str | None] = mapped_column(
        String(50), unique=True, index=True, nullable=True
    )
    phone: Mapped[str | None] = mapped_column(String(50), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    #: Start of the user's latest session (refreshed at most every 30 minutes).
    last_login_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), index=True, nullable=True
    )
    #: Storage key and type of the profile photo (re-encoded by the server); null = initials.
    avatar_key: Mapped[str | None] = mapped_column(String(255), nullable=True)
    avatar_media_type: Mapped[str | None] = mapped_column(String(50), nullable=True)
    avatar_updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # Relationships
    user_roles: Mapped[list["UserRole"]] = relationship(
        "UserRole",
        back_populates="user",
        foreign_keys="UserRole.user_id",
        cascade="all, delete-orphan",
    )
    roles: Mapped[list["Role"]] = relationship(
        "Role",
        secondary="user_roles",
        # UserRole has two FKs to users (user_id, assigned_by_user_id);
        # without an explicit join, SQLAlchemy can't tell which one this
        # membership relationship should use.
        primaryjoin="User.id == UserRole.user_id",
        secondaryjoin="Role.id == UserRole.role_id",
        back_populates="users",
        viewonly=True,
    )
    technician: Mapped["Technician | None"] = relationship(
        "Technician",
        back_populates="user",
        uselist=False,
        cascade="all, delete-orphan",
    )
    maintenance_requests: Mapped[list["MaintenanceRequest"]] = relationship(
        "MaintenanceRequest",
        back_populates="requested_by_user",
        foreign_keys="MaintenanceRequest.requested_by_user_id",
    )
    custody_assignments: Mapped[list["EquipmentCustodyHistory"]] = relationship(
        "EquipmentCustodyHistory",
        back_populates="assigned_to_user",
        foreign_keys="EquipmentCustodyHistory.assigned_to_user_id",
    )
    audit_logs: Mapped[list["AuditLog"]] = relationship(
        "AuditLog", back_populates="user", foreign_keys="AuditLog.user_id"
    )
    notifications: Mapped[list["Notification"]] = relationship(
        "Notification", back_populates="user", cascade="all, delete-orphan"
    )


class Role(Base):
    __tablename__ = "roles"
    __table_args__ = (
        CheckConstraint(
            "parent_role_id IS NULL OR parent_role_id <> id", name="no_self_parent"
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    code: Mapped[str] = mapped_column(
        String(50), unique=True, index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    #: The five base roles: they cannot be deleted or renamed by code.
    is_system: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default="false", nullable=False
    )
    #: Inheritance: this role has everything its parent has (see `app.core.rbac`).
    parent_role_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("roles.id", ondelete="RESTRICT"),
        index=True,
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    #: Loaded together with the role (and so up the whole chain) because authorization needs
    #: the ancestors on every request and async sessions cannot lazy-load.
    parent: Mapped["Role | None"] = relationship(
        "Role", remote_side="Role.id", lazy="selectin", join_depth=6
    )
    user_roles: Mapped[list["UserRole"]] = relationship(
        "UserRole", back_populates="role", cascade="all, delete-orphan"
    )
    users: Mapped[list["User"]] = relationship(
        "User",
        secondary="user_roles",
        primaryjoin="Role.id == UserRole.role_id",
        secondaryjoin="User.id == UserRole.user_id",
        back_populates="roles",
        viewonly=True,
    )
    role_permissions: Mapped[list["RolePermission"]] = relationship(
        "RolePermission", back_populates="role", cascade="all, delete-orphan"
    )
    permissions: Mapped[list["Permission"]] = relationship(
        "Permission",
        secondary="role_permissions",
        back_populates="roles",
        viewonly=True,
        lazy="selectin",
    )


class Permission(Base):
    __tablename__ = "permissions"

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    code: Mapped[str] = mapped_column(
        String(100), unique=True, index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    module: Mapped[str] = mapped_column(String(50), nullable=False)
    #: `recurso:accion` permissions carry both parts; legacy dotted ones have no action.
    resource: Mapped[str | None] = mapped_column(String(50), nullable=True)
    action: Mapped[str | None] = mapped_column(String(50), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    role_permissions: Mapped[list["RolePermission"]] = relationship(
        "RolePermission", back_populates="permission", cascade="all, delete-orphan"
    )
    roles: Mapped[list["Role"]] = relationship(
        "Role",
        secondary="role_permissions",
        back_populates="permissions",
        viewonly=True,
    )


class UserRole(Base):
    __tablename__ = "user_roles"
    __table_args__ = (
        UniqueConstraint("user_id", "role_id", name="uq_user_roles_user_id_role_id"),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    user_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("users.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    role_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("roles.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    assigned_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    assigned_by_user_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )

    user: Mapped["User"] = relationship(
        "User", foreign_keys=[user_id], back_populates="user_roles"
    )
    role: Mapped["Role"] = relationship("Role", back_populates="user_roles")
    assigned_by: Mapped["User | None"] = relationship(
        "User", foreign_keys=[assigned_by_user_id]
    )


class RolePermission(Base):
    __tablename__ = "role_permissions"
    __table_args__ = (
        UniqueConstraint(
            "role_id",
            "permission_id",
            name="uq_role_permissions_role_id_permission_id",
        ),
    )

    id: Mapped[int] = mapped_column(
        BigInteger, Identity(always=False), primary_key=True
    )
    role_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("roles.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    permission_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("permissions.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    assigned_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    role: Mapped["Role"] = relationship("Role", back_populates="role_permissions")
    permission: Mapped["Permission"] = relationship(
        "Permission", back_populates="role_permissions"
    )
