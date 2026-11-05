import 'package:equatable/equatable.dart';

/// Perfil local devuelto por `GET /auth/me`.
///
/// La app decide por los **permisos**, nunca por el nombre de un rol.
class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
    required this.roles,
    required this.permissions,
    this.employeeCode,
  });

  final int id;
  final String email;
  final String fullName;
  final String? employeeCode;
  final bool isActive;
  final List<String> roles;
  final Set<String> permissions;

  @override
  List<Object?> get props => [id, email, fullName, employeeCode, isActive, roles, permissions];

  bool can(String permission) => permissions.contains(permission);

  /// Roles vacíos: igual que la web, la cuenta espera aprobación.
  /// Con roles pero cero permisos es otro caso: «sin acceso asignado».
  AccountStatus get status {
    if (roles.isEmpty) return AccountStatus.pendingApproval;
    if (permissions.isEmpty) return AccountStatus.noAccess;
    return AccountStatus.active;
  }

  factory UserProfile.fromJson(Map<String, Object?> json) {
    List<String> codes(Object? value) => [
          if (value is List)
            for (final item in value)
              if (item is Map && item['code'] is String) item['code'] as String,
        ];
    return UserProfile(
      id: json['id'] as int,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      employeeCode: json['employee_code'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      roles: codes(json['roles']),
      permissions: codes(json['permissions']).toSet(),
    );
  }
}

enum AccountStatus { pendingApproval, noAccess, active }
