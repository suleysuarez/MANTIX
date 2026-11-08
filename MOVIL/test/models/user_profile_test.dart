import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/auth/user_profile.dart';

Map<String, Object?> json({List<Map<String, String>> roles = const [], List<Map<String, String>> permissions = const []}) => {
      'id': 7,
      'email': 'ana@example.com',
      'full_name': 'Ana Pérez',
      'employee_code': null,
      'is_active': true,
      'roles': roles,
      'permissions': permissions,
    };

void main() {
  test('lee el contrato de GET /auth/me', () {
    final profile = UserProfile.fromJson(json(
      roles: [
        {'code': 'TECNICO', 'name': 'Técnico'},
      ],
      permissions: [
        {'code': 'tickets:ver_asignados', 'name': 'Ver asignados'},
      ],
    ));
    expect(profile.id, 7);
    expect(profile.fullName, 'Ana Pérez');
    expect(profile.employeeCode, isNull);
    expect(profile.roles, ['TECNICO']);
    expect(profile.can('tickets:ver_asignados'), isTrue);
    expect(profile.can('tickets:asignar'), isFalse);
  });

  group('status', () {
    test('sin roles: pendiente de aprobación', () {
      expect(UserProfile.fromJson(json()).status, AccountStatus.pendingApproval);
    });

    test('con roles pero cero permisos: sin acceso (caso distinto)', () {
      final profile = UserProfile.fromJson(json(roles: [
        {'code': 'X', 'name': 'X'},
      ]));
      expect(profile.status, AccountStatus.noAccess);
    });

    test('con roles y permisos: activa', () {
      final profile = UserProfile.fromJson(json(
        roles: [
          {'code': 'X', 'name': 'X'},
        ],
        permissions: [
          {'code': 'dashboard:ver', 'name': 'Ver'},
        ],
      ));
      expect(profile.status, AccountStatus.active);
    });
  });
}
