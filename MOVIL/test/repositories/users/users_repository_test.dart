import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/repositories/users/users_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';
import '../../support/users_support.dart';

void main() {
  UsersRepository repo(FakeAdapter adapter) => UsersRepository(dioWith(adapter));

  group('listUsers', () {
    test('pide la página, el tamaño y el orden, y solo manda los filtros que hay', () async {
      final adapter = FakeAdapter((_) => pagedResponse([userJson()]));
      await repo(adapter).listUsers();

      expect(adapter.requests.single.path, '/admin/users');
      expect(adapter.requests.single.queryParameters, {'page': 1, 'size': 20});
    });

    test('manda búsqueda recortada, rol, estado y fechas con el día completo', () async {
      final adapter = FakeAdapter((_) => pagedResponse([userJson()], total: 41, totalPages: 3));
      final page = await repo(adapter).listUsers(page: 2, size: 10, search: '  ana ', role: 'TECHNICIAN', isActive: false, createdFrom: DateTime(2026, 10, 1), createdTo: DateTime(2026, 10, 31), sort: 'name');

      final query = adapter.requests.single.queryParameters;
      expect(query['page'], 2);
      expect(query['size'], 10);
      expect(query['search'], 'ana');
      expect(query['role'], 'TECHNICIAN');
      expect(query['is_active'], false);
      expect(query['sort'], 'name');
      expect(DateTime.parse(query['created_to'] as String).isAfter(DateTime.parse(query['created_from'] as String).add(const Duration(days: 29))), isTrue);
      expect(page.items.single.fullName, 'Ana Pérez');
      expect(page.info!.total, 41);
    });

    test('is_active=true también viaja (no es lo mismo que no filtrar)', () async {
      final adapter = FakeAdapter((_) => pagedResponse(<Object?>[]));
      await repo(adapter).listUsers(isActive: true);
      expect(adapter.requests.single.queryParameters['is_active'], true);
    });

    test('sin permiso llega como ForbiddenFailure', () async {
      final repository = repo(FakeAdapter((_) => errorResponse(403, code: 'forbidden')));
      await expectLater(repository.listUsers(), throwsA(isA<ForbiddenFailure>()));
    });
  });

  test('summary, pending y assignableRoles leen su endpoint', () async {
    final adapter = FakeAdapter((o) => switch (o.path) {
          '/admin/users/summary' => jsonResponse(200, usersSummaryJson),
          '/admin/users/pending' => jsonResponse(200, [pendingJson(), pendingJson(id: 8, name: 'Marta', email: 'm@x.co')]),
          '/admin/roles' => jsonResponse(200, [roleJson(), roleJson(id: 1, code: 'ADMIN', name: 'Administrador')]),
          _ => errorResponse(404),
        });
    final repository = repo(adapter);

    expect((await repository.summary()).total, 40);
    expect((await repository.pending()).map((p) => p.fullName), ['Luis Nuevo', 'Marta']);
    expect((await repository.assignableRoles()).map((r) => r.code), ['TECHNICIAN', 'ADMIN']);
  });

  group('rolesOverview', () {
    test('con detalle usa /admin/roles/manage y trae descripción y conteo', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, [managedRoleJson(users: 9)]));
      final roles = await repo(adapter).rolesOverview(detailed: true);

      expect(adapter.requests.single.path, '/admin/roles/manage');
      expect((roles.single.description, roles.single.userCount), ('Atiende tickets asignados', 9));
    });

    test('sin detalle junta los roles con los conteos del resumen; un rol sin personas queda en 0', () async {
      final adapter = FakeAdapter((o) => switch (o.path) {
            '/admin/roles' => jsonResponse(200, [roleJson(), roleJson(id: 5, code: 'AUDITOR', name: 'Auditor')]),
            '/admin/users/summary' => jsonResponse(200, usersSummaryJson),
            _ => errorResponse(404),
          });
      final roles = await repo(adapter).rolesOverview(detailed: false);

      expect(adapter.requests.map((r) => r.path), unorderedEquals(['/admin/roles', '/admin/users/summary']));
      expect([for (final role in roles) (role.code, role.userCount)], [('TECHNICIAN', 9), ('AUDITOR', 0)]);
      expect(roles.first.description, isNull, reason: 'sin permiso de asignar no llega la descripción');
    });
  });

  group('cambios', () {
    test('setRoles reemplaza los roles con PUT y avisa del cambio', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, userJson(roles: [roleJson(id: 1, code: 'ADMIN', name: 'Administrador')])));
      final repository = repo(adapter);
      var changes = 0;
      final sub = repository.changes.listen((_) => changes++);
      addTearDown(sub.cancel);

      final user = await repository.setRoles(5, [1, 3]);
      await Future<void>.delayed(Duration.zero);

      expect(adapter.requests.single.method, 'PUT');
      expect(adapter.requests.single.path, '/admin/users/5/roles');
      expect(adapter.requests.single.data, {'role_ids': [1, 3]});
      expect(user.roles.single.code, 'ADMIN');
      expect(changes, 1);
    });

    test('setActive usa activate o deactivate', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, userJson()));
      final repository = repo(adapter);

      await repository.setActive(5, active: false);
      await repository.setActive(5, active: true);

      expect(adapter.requests.map((r) => '${r.method} ${r.path}'), ['POST /admin/users/5/deactivate', 'POST /admin/users/5/activate']);
    });

    test('updateContact manda el teléfono y null lo borra', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, userJson()));
      final repository = repo(adapter);

      await repository.updateContact(5, phone: (value: '+57 300 1'));
      await repository.updateContact(5, phone: (value: null));

      expect(adapter.requests[0].method, 'PATCH');
      expect(adapter.requests[0].path, '/admin/users/5');
      expect(adapter.requests[0].data, {'phone': '+57 300 1'});
      expect(adapter.requests[1].data, {'phone': null});
    });

    test('los códigos de error del servidor llegan traducidos', () async {
      Future<Object?> failure(int status, String code, Future<Object?> Function(UsersRepository) call) async {
        try {
          await call(repo(FakeAdapter((_) => errorResponse(status, code: code))));
        } catch (error) {
          return error;
        }
        return null;
      }

      final self = await failure(409, 'cannot_deactivate_self', (r) => r.setActive(1, active: false));
      expect(self, isA<ConflictFailure>().having((f) => f.message, 'message', 'No puedes desactivar tu propia cuenta.'));
      final admin = await failure(409, 'last_admin_protected', (r) => r.setRoles(1, [3]));
      expect(admin, isA<ConflictFailure>().having((f) => f.message, 'message', 'No se puede dejar al sistema sin administradores activos.'));
      final own = await failure(409, 'cannot_revoke_own_admin', (r) => r.setRoles(1, [3]));
      expect(own, isA<ConflictFailure>().having((f) => f.message, 'message', 'No puedes quitarte tu propio rol de administrador.'));
      final role = await failure(404, 'role_not_found', (r) => r.setRoles(1, [99]));
      expect(role, isA<NotFoundFailure>().having((f) => f.message, 'message', 'Uno de los roles ya no existe o está inactivo.'));
      final user = await failure(404, 'user_not_found', (r) => r.setActive(99, active: true));
      expect(user, isA<NotFoundFailure>().having((f) => f.message, 'message', 'Ese usuario ya no existe o está inactivo.'));
    });
  });
}
