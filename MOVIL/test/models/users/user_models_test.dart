import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/users/user_models.dart';

import '../../support/users_support.dart';

void main() {
  test('ManagedUser lee la fila de la lista con sus roles y su último acceso', () {
    final user = ManagedUser.fromJson(userJson(roles: [roleJson(), roleJson(id: 1, code: 'ADMIN', name: 'Administrador')]));

    expect((user.id, user.email, user.fullName), (1, 'ana@mantix.test', 'Ana Pérez'));
    expect((user.phone, user.employeeCode, user.isActive, user.linked), ('+57 300 123 4567', 'EMP-014', true, true));
    expect([for (final role in user.roles) role.code], ['TECHNICIAN', 'ADMIN']);
    expect(user.lastLoginAt, isNotNull);
  });

  test('quien nunca entró llega con lastLoginAt nulo y los opcionales ausentes no rompen nada', () {
    final user = ManagedUser.fromJson(userJson(lastLogin: null, phone: null, code: null, linked: false));

    expect(user.lastLoginAt, isNull);
    expect((user.phone, user.employeeCode, user.linked), (null, null, false));
  });

  test('una persona sin roles llega con la lista vacía', () {
    expect(ManagedUser.fromJson(userJson(roles: const [])).roles, isEmpty);
  });

  test('PendingUser lee id, correo y nombre', () {
    final pending = PendingUser.fromJson(pendingJson());
    expect((pending.id, pending.email, pending.fullName), (7, 'luis@mantix.test', 'Luis Nuevo'));
  });

  test('UsersSummary lee las cifras, los roles y los últimos accesos', () {
    final summary = UsersSummary.fromJson(usersSummaryJson);

    expect((summary.total, summary.active, summary.inactive, summary.neverSignedIn, summary.withoutRole), (40, 36, 4, 3, 2));
    expect([for (final role in summary.byRole) (role.code, role.count)], [('ADMIN', 2), ('TECHNICIAN', 9)]);
    expect(summary.recentAccess.single.fullName, 'Ana Pérez');
  });

  test('un resumen incompleto no rompe la lectura', () {
    final summary = UsersSummary.fromJson(const {});
    expect((summary.total, summary.withoutRole), (0, 0));
    expect(summary.byRole, isEmpty);
  });

  group('RoleInfo', () {
    test('con detalle trae descripción, estado y cuántas personas lo tienen', () {
      final role = RoleInfo.fromJson(managedRoleJson(users: 9));
      expect((role.description, role.isActive, role.userCount), ('Atiende tickets asignados', true, 9));
    });

    test('sin detalle no se sabe: description y userCount son nulos hasta que llegan del resumen', () {
      final role = RoleInfo.fromJson(roleJson());
      expect((role.description, role.userCount), (null, null));
      expect(role.withCount(4).userCount, 4);
    });
  });
}
