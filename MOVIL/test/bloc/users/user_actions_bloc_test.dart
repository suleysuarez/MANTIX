import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/users/user_actions_bloc.dart';
import 'package:mantix/models/users/user_models.dart';
import 'package:mantix/repositories/users/users_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';
import '../../support/users_support.dart';

const _me = 1;

ManagedUser _user({int id = 5, bool active = true, String? phone = '+57 300 123 4567', String? code = 'EMP-014'}) => ManagedUser.fromJson(userJson(id: id, name: 'Luis Gómez', active: active, phone: phone, code: code));

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;

  setUp(() {
    handler = (_) => jsonResponse(200, userJson(id: 5, name: 'Luis Gómez'));
    adapter = FakeAdapter((options) => handler(options));
  });

  UserActionsBloc build() => UserActionsBloc(repository: UsersRepository(dioWith(adapter)), currentUserId: _me);

  /// Manda [event] y devuelve el resultado que emitió.
  Future<UserOutcome> run(UserActionsBloc bloc, UserActionsEvent event) async {
    bloc.add(event);
    return (await bloc.stream.firstWhere((s) => s.outcome != null && s.inFlight.isEmpty)).outcome!;
  }

  Iterable<RequestOptions> writes() => adapter.requests.where((r) => r.method != 'GET');

  group('asignar roles', () {
    test('manda PUT con los roles únicos y avisa en español', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, const UserRolesChangeRequested(userId: 5, name: 'Luis Gómez', roleIds: [3, 1, 3]));

      expect(outcome.kind, UserOutcomeKind.succeeded);
      expect(outcome.message, 'Roles de Luis Gómez actualizados.');
      expect(outcome.user, isNotNull);
      expect(writes().single.method, 'PUT');
      expect(writes().single.path, '/admin/users/5/roles');
      expect((writes().single.data as Map)['role_ids'], [3, 1]);
    });

    test('un pendiente (sin roles actuales) recibe el rol', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, const UserRolesChangeRequested(userId: 7, name: 'Luis Nuevo', roleIds: [3]));

      expect(outcome.kind, UserOutcomeKind.succeeded);
      expect(writes().single.path, '/admin/users/7/roles');
    });

    test('sin elegir ningún rol no se pide nada', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, const UserRolesChangeRequested(userId: 5, name: 'Luis Gómez', roleIds: []));

      expect(outcome.kind, UserOutcomeKind.blocked);
      expect(outcome.message, 'Elige al menos un rol.');
      expect(adapter.requests, isEmpty);
    });

    test('más de diez roles no se pide', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, UserRolesChangeRequested(userId: 5, name: 'Luis Gómez', roleIds: List.generate(11, (i) => i + 1)));

      expect(outcome.kind, UserOutcomeKind.blocked);
      expect(outcome.message, 'Un usuario admite como máximo 10 roles.');
      expect(adapter.requests, isEmpty);
    });

    test('la misma selección que ya tiene no se pide', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, const UserRolesChangeRequested(userId: 5, name: 'Luis Gómez', roleIds: [3, 1], currentRoleIds: [1, 3]));

      expect(outcome.kind, UserOutcomeKind.blocked);
      expect(outcome.message, 'Luis Gómez ya tiene esos roles.');
      expect(adapter.requests, isEmpty);
    });

    test('quitarse el propio rol de administrador lo explica el servidor', () async {
      handler = (_) => errorResponse(409, code: 'cannot_revoke_own_admin');
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, const UserRolesChangeRequested(userId: _me, name: 'Ana', roleIds: [3], currentRoleIds: [1]));

      expect(outcome.kind, UserOutcomeKind.failed);
      expect(outcome.message, contains('No puedes quitarte tu propio rol de administrador.'));
      expect(outcome.message, isNot(contains('interno')));
    });

    test('dejar al sistema sin administradores lo explica el servidor', () async {
      handler = (_) => errorResponse(409, code: 'last_admin_protected');
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, const UserRolesChangeRequested(userId: 9, name: 'Marta', roleIds: [3], currentRoleIds: [1]));

      expect(outcome.kind, UserOutcomeKind.failed);
      expect(outcome.message, contains('No se puede dejar al sistema sin administradores activos.'));
    });

    test('un rol que ya no existe', () async {
      handler = (_) => errorResponse(404, code: 'role_not_found');
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, const UserRolesChangeRequested(userId: 5, name: 'Luis Gómez', roleIds: [99]));

      expect(outcome.message, contains('Uno de los roles ya no existe o está inactivo.'));
    });

    test('sin permiso y sin red se dicen sin detalles internos', () async {
      handler = (_) => errorResponse(403, code: 'forbidden');
      var bloc = build();
      addTearDown(bloc.close);
      expect((await run(bloc, const UserRolesChangeRequested(userId: 5, name: 'Luis', roleIds: [3]))).message, contains('No tienes permiso'));

      handler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red');
      bloc = build();
      addTearDown(bloc.close);
      expect((await run(bloc, const UserRolesChangeRequested(userId: 5, name: 'Luis', roleIds: [3]))).message, contains('No pudimos conectar'));
    });
  });

  group('activar y desactivar', () {
    test('desactivar a otra persona usa deactivate', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, UserActiveChangeRequested(_user(), active: false));

      expect(outcome.kind, UserOutcomeKind.succeeded);
      expect(outcome.message, 'La cuenta de Luis Gómez fue desactivada.');
      expect(writes().single.path, '/admin/users/5/deactivate');
    });

    test('activar usa activate', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, UserActiveChangeRequested(_user(active: false), active: true));

      expect(outcome.message, 'La cuenta de Luis Gómez fue activada.');
      expect(writes().single.path, '/admin/users/5/activate');
    });

    test('no se puede desactivar la propia cuenta y ni se pide', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, UserActiveChangeRequested(_user(id: _me), active: false));

      expect(outcome.kind, UserOutcomeKind.blocked);
      expect(outcome.message, 'No puedes desactivar tu propia cuenta.');
      expect(adapter.requests, isEmpty);
    });

    test('activar la propia cuenta ya activa no es el caso de «desactivarse», pero tampoco hay nada que hacer', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, UserActiveChangeRequested(_user(id: _me), active: true));

      expect(outcome.kind, UserOutcomeKind.blocked);
      expect(outcome.message, contains('ya está activa'));
      expect(adapter.requests, isEmpty);
    });

    test('el último administrador está protegido por el servidor', () async {
      handler = (_) => errorResponse(409, code: 'last_admin_protected');
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, UserActiveChangeRequested(_user(), active: false));

      expect(outcome.kind, UserOutcomeKind.failed);
      expect(outcome.message, startsWith('No se pudo desactivar a Luis Gómez:'));
      expect(outcome.message, contains('administradores activos'));
    });

    test('mientras una acción está en curso, otra sobre la misma persona se ignora', () async {
      final bloc = build();
      addTearDown(bloc.close);

      bloc
        ..add(UserActiveChangeRequested(_user(), active: false))
        ..add(UserActiveChangeRequested(_user(), active: false));
      await bloc.stream.firstWhere((s) => s.outcome != null && s.inFlight.isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(writes(), hasLength(1));
    });
  });

  group('editar teléfono y código', () {
    test('manda solo lo que cambió, normalizado', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, UserContactChangeRequested(_user(), phone: '  +57  311 000 ', employeeCode: 'emp-014'));

      expect(outcome.kind, UserOutcomeKind.succeeded);
      expect(outcome.message, 'Datos de Luis Gómez actualizados.');
      expect(writes().single.method, 'PATCH');
      expect(writes().single.data, {'phone': '+57 311 000'}, reason: 'el código quedó igual (EMP-014) y no viaja');
    });

    test('vaciar un campo lo borra con null', () async {
      final bloc = build();
      addTearDown(bloc.close);

      await run(bloc, UserContactChangeRequested(_user(), phone: '  ', employeeCode: 'EMP-014'));

      expect(writes().single.data, {'phone': null});
    });

    test('sin cambios no se pide', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, UserContactChangeRequested(_user(), phone: '+57 300 123 4567', employeeCode: 'emp-014'));

      expect(outcome.kind, UserOutcomeKind.blocked);
      expect(outcome.message, 'No hay cambios que guardar.');
      expect(adapter.requests, isEmpty);
    });

    test('un teléfono o un código con formato inválido no se piden', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final phone = await run(bloc, UserContactChangeRequested(_user(), phone: 'abc', employeeCode: 'EMP-014'));
      expect(phone.kind, UserOutcomeKind.blocked);
      expect(phone.message, 'El teléfono solo admite números, espacios, +, ( ) y -.');

      final code = await run(bloc, UserContactChangeRequested(_user(), phone: '+57 300 123 4567', employeeCode: 'x'));
      expect(code.message, 'El código solo admite letras, números, punto, guion y guion bajo (2 a 50).');
      expect(adapter.requests, isEmpty);
    });

    test('un código de empleado repetido lo explica el servidor', () async {
      handler = (_) => errorResponse(409, code: 'user_employee_code_taken');
      final bloc = build();
      addTearDown(bloc.close);

      final outcome = await run(bloc, UserContactChangeRequested(_user(), employeeCode: 'EMP-099'));

      expect(outcome.kind, UserOutcomeKind.failed);
      expect(outcome.message, contains('Ya existe un usuario con ese código de empleado.'));
    });
  });
}
