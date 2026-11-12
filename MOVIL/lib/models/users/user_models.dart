/// Modelos de la API de usuarios y roles (`/admin/users`, `/admin/roles`). Escritos a mano, con
/// lectura tolerante: un campo opcional ausente no rompe la pantalla.
library;

import 'package:equatable/equatable.dart';

DateTime _date(Object? value) => DateTime.parse(value! as String).toLocal();

DateTime? _dateOrNull(Object? value) => value is String ? DateTime.parse(value).toLocal() : null;

int _int(Object? value) => value is num ? value.toInt() : 0;

/// Un rol dentro de un usuario o de un selector: lo mínimo para mostrarlo y asignarlo.
class UserRoleRef extends Equatable {
  const UserRoleRef({required this.id, required this.code, required this.name});

  factory UserRoleRef.fromJson(Map<String, Object?> json) => UserRoleRef(id: json['id']! as int, code: json['code']! as String, name: json['name']! as String);

  final int id;
  final String code;
  final String name;

  @override
  List<Object?> get props => [id, code, name];
}

/// Fila de `GET /admin/users`: una cuenta con sus roles.
class ManagedUser extends Equatable {
  const ManagedUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
    required this.roles,
    required this.createdAt,
    required this.linked,
    this.phone,
    this.employeeCode,
    this.lastLoginAt,
  });

  factory ManagedUser.fromJson(Map<String, Object?> json) => ManagedUser(
        id: json['id']! as int,
        email: json['email']! as String,
        fullName: json['full_name']! as String,
        phone: json['phone'] as String?,
        employeeCode: json['employee_code'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        roles: [for (final role in (json['roles'] as List? ?? const [])) UserRoleRef.fromJson((role as Map).cast<String, Object?>())],
        createdAt: _date(json['created_at']),
        lastLoginAt: _dateOrNull(json['last_login_at']),
        linked: json['linked'] as bool? ?? false,
      );

  final int id;
  final String email;
  final String fullName;
  final String? phone;
  final String? employeeCode;
  final bool isActive;
  final List<UserRoleRef> roles;
  final DateTime createdAt;

  /// Cuándo empezó su última sesión; `null` si nunca entró.
  final DateTime? lastLoginAt;

  /// La persona ya entró una vez y su cuenta de acceso quedó vinculada.
  final bool linked;

  @override
  List<Object?> get props => [id, email, fullName, phone, employeeCode, isActive, roles, createdAt, lastLoginAt, linked];
}

/// Una persona que ya entró pero no tiene rol (`GET /admin/users/pending`).
class PendingUser extends Equatable {
  const PendingUser({required this.id, required this.email, required this.fullName});

  factory PendingUser.fromJson(Map<String, Object?> json) => PendingUser(id: json['id']! as int, email: json['email']! as String, fullName: json['full_name']! as String);

  final int id;
  final String email;
  final String fullName;

  @override
  List<Object?> get props => [id, email, fullName];
}

class RoleCount extends Equatable {
  const RoleCount({required this.code, required this.name, required this.count});

  factory RoleCount.fromJson(Map<String, Object?> json) => RoleCount(code: json['code']! as String, name: json['name']! as String, count: _int(json['count']));

  final String code;
  final String name;
  final int count;

  @override
  List<Object?> get props => [code, name, count];
}

class RecentAccess extends Equatable {
  const RecentAccess({required this.id, required this.fullName, required this.email, required this.lastLoginAt});

  factory RecentAccess.fromJson(Map<String, Object?> json) => RecentAccess(id: json['id']! as int, fullName: json['full_name']! as String, email: json['email']! as String, lastLoginAt: _date(json['last_login_at']));

  final int id;
  final String fullName;
  final String email;
  final DateTime lastLoginAt;

  @override
  List<Object?> get props => [id, fullName, email, lastLoginAt];
}

/// Indicadores de la pantalla de usuarios (`GET /admin/users/summary`).
class UsersSummary extends Equatable {
  const UsersSummary({required this.total, required this.active, required this.inactive, required this.neverSignedIn, required this.withoutRole, required this.byRole, required this.recentAccess});

  factory UsersSummary.fromJson(Map<String, Object?> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, Object?>) parse) => raw is List ? [for (final item in raw) parse((item as Map).cast<String, Object?>())] : const [];
    return UsersSummary(
      total: _int(json['total']),
      active: _int(json['active']),
      inactive: _int(json['inactive']),
      neverSignedIn: _int(json['never_signed_in']),
      withoutRole: _int(json['without_role']),
      byRole: list(json['by_role'], RoleCount.fromJson),
      recentAccess: list(json['recent_access'], RecentAccess.fromJson),
    );
  }

  final int total;
  final int active;
  final int inactive;

  /// Registrados que nunca entraron.
  final int neverSignedIn;

  /// Activos sin rol: los de la pestaña Pendientes.
  final int withoutRole;
  final List<RoleCount> byRole;
  final List<RecentAccess> recentAccess;

  @override
  List<Object?> get props => [total, active, inactive, neverSignedIn, withoutRole, byRole, recentAccess];
}

/// Un rol para la pestaña Roles. [userCount] y [description] solo llegan con el permiso de
/// asignar roles (o, el conteo, del resumen); si no se sabe, son `null`.
class RoleInfo extends Equatable {
  const RoleInfo({required this.id, required this.code, required this.name, this.description, this.isActive = true, this.userCount});

  factory RoleInfo.fromJson(Map<String, Object?> json) => RoleInfo(
        id: json['id']! as int,
        code: json['code']! as String,
        name: json['name']! as String,
        description: json['description'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        userCount: json['user_count'] is num ? (json['user_count']! as num).toInt() : null,
      );

  final int id;
  final String code;
  final String name;
  final String? description;
  final bool isActive;
  final int? userCount;

  RoleInfo withCount(int? count) => RoleInfo(id: id, code: code, name: name, description: description, isActive: isActive, userCount: count);

  @override
  List<Object?> get props => [id, code, name, description, isActive, userCount];
}
