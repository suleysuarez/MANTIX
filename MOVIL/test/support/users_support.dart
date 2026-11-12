/// Respuestas de ejemplo de la API de usuarios y roles, con la forma del backend.
library;

Map<String, Object?> roleJson({int id = 3, String code = 'TECHNICIAN', String name = 'Técnico'}) => {'id': id, 'code': code, 'name': name};

Map<String, Object?> userJson({
  int id = 1,
  String name = 'Ana Pérez',
  String email = 'ana@mantix.test',
  String? phone = '+57 300 123 4567',
  String? code = 'EMP-014',
  bool active = true,
  List<Map<String, Object?>>? roles,
  String? lastLogin = '2026-11-08T10:00:00Z',
  bool linked = true,
}) =>
    {
      'id': id,
      'email': email,
      'full_name': name,
      'phone': phone,
      'employee_code': code,
      'is_active': active,
      'roles': roles ?? [roleJson()],
      'created_at': '2026-10-01T09:00:00Z',
      'last_login_at': lastLogin,
      'linked': linked,
    };

const usersSummaryJson = <String, Object?>{
  'total': 40,
  'active': 36,
  'inactive': 4,
  'never_signed_in': 3,
  'without_role': 2,
  'by_role': [
    {'code': 'ADMIN', 'name': 'Administrador', 'count': 2},
    {'code': 'TECHNICIAN', 'name': 'Técnico', 'count': 9},
  ],
  'recent_access': [
    {'id': 1, 'full_name': 'Ana Pérez', 'email': 'ana@mantix.test', 'last_login_at': '2026-11-08T10:00:00Z'},
  ],
};

Map<String, Object?> pendingJson({int id = 7, String name = 'Luis Nuevo', String email = 'luis@mantix.test'}) => {'id': id, 'email': email, 'full_name': name};

Map<String, Object?> managedRoleJson({int id = 3, String code = 'TECHNICIAN', String name = 'Técnico', int users = 9, bool active = true}) => {
      'id': id,
      'code': code,
      'name': name,
      'description': 'Atiende tickets asignados',
      'is_active': active,
      'is_system': true,
      'parent_role_id': null,
      'parent_name': null,
      'depth': 0,
      'user_count': users,
      'children_count': 0,
      'own_permissions': <String>[],
      'effective': <Object?>[],
    };
