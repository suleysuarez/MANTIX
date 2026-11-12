import 'package:equatable/equatable.dart';

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// Un rol de la persona, con el nombre que se lee.
class ProfileRole extends Equatable {
  const ProfileRole({required this.code, required this.name});

  factory ProfileRole.fromJson(Map<String, Object?> json) => ProfileRole(code: json['code'] as String? ?? '', name: json['name'] as String? ?? json['code'] as String? ?? '');

  final String code;
  final String name;

  @override
  List<Object?> get props => [code, name];
}

/// Mi perfil (`GET /profile`). El correo es la identidad de acceso y no se edita.
class ProfileData extends Equatable {
  const ProfileData({
    required this.id,
    required this.email,
    required this.fullName,
    required this.roles,
    required this.hasAvatar,
    required this.createdAt,
    this.phone,
    this.avatarVersion,
    this.lastLoginAt,
  });

  factory ProfileData.fromJson(Map<String, Object?> json) => ProfileData(
        id: json['id']! as int,
        email: json['email']! as String,
        fullName: json['full_name']! as String,
        phone: json['phone'] as String?,
        roles: [for (final role in (json['roles'] as List? ?? const [])) ProfileRole.fromJson((role as Map).cast<String, Object?>())],
        hasAvatar: json['has_avatar'] as bool? ?? false,
        avatarVersion: json['avatar_version'] as int?,
        lastLoginAt: _date(json['last_login_at']),
        createdAt: _date(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final int id;
  final String email;
  final String fullName;
  final String? phone;
  final List<ProfileRole> roles;
  final bool hasAvatar;

  /// Cambia con cada foto nueva; `null` sin foto.
  final int? avatarVersion;

  /// Cuándo empezó su última sesión; `null` si nunca entró.
  final DateTime? lastLoginAt;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, email, fullName, phone, roles, hasAvatar, avatarVersion, lastLoginAt, createdAt];
}

/// Una fila de mi actividad (`GET /profile/history`): lo que hice y lo que otros hicieron en mi cuenta.
class HistoryEntry extends Equatable {
  const HistoryEntry({required this.id, required this.action, required this.kind, required this.createdAt, this.actorName});

  factory HistoryEntry.fromJson(Map<String, Object?> json) => HistoryEntry(
        id: json['id']! as int,
        action: json['action'] as String? ?? '',
        kind: json['kind'] as String? ?? 'activity',
        actorName: json['actor_name'] as String?,
        createdAt: _date(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final int id;

  /// Código de la acción (`auth.login`, `profile.updated`…).
  final String action;

  /// `session`, `profile`, `security` o `activity`.
  final String kind;

  /// Quién lo hizo cuando fue otra persona (por ejemplo, un administrador); `null` si fui yo.
  final String? actorName;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, action, kind, actorName, createdAt];
}
