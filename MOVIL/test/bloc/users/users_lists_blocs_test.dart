import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/users/assignable_roles_cubit.dart';
import 'package:mantix/bloc/users/pending_users_bloc.dart';
import 'package:mantix/bloc/users/roles_bloc.dart';
import 'package:mantix/bloc/users/users_list_bloc.dart';
import 'package:mantix/bloc/users/users_summary_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/repositories/users/users_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';
import '../../support/users_support.dart';

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;
  late UsersRepository repository;

  setUp(() {
    handler = (_) => errorResponse(404);
    adapter = FakeAdapter((options) => handler(options));
    repository = UsersRepository(dioWith(adapter));
  });

  group('UsersListBloc', () {
    UsersListBloc build({String search = '', String? role, bool? isActive, int pageSize = 20}) => UsersListBloc(repository: repository, search: search, role: role, isActive: isActive, pageSize: pageSize);

    test('carga la página 1 con los filtros que se le dieron', () async {
      handler = (_) => pagedResponse([userJson(), userJson(id: 2, name: 'Luis')], total: 41, totalPages: 3);
      final bloc = build(search: 'a', role: 'ADMIN', isActive: true, pageSize: 10)..add(const UsersListStarted());
      addTearDown(bloc.close);

      final state = await bloc.stream.firstWhere((s) => s.status == UsersListStatus.success);

      expect(state.items.map((u) => u.fullName), ['Ana Pérez', 'Luis']);
      expect((state.total, state.totalPages, state.page), (41, 3, 1));
      final query = adapter.requests.single.queryParameters;
      expect((query['page'], query['size'], query['search'], query['role'], query['is_active'], query['sort']), (1, 10, 'a', 'ADMIN', true, 'name'));
    });

    test('moverse de página pide esa página y conserva los datos mientras llega', () async {
      handler = (o) => pagedResponse([userJson(id: (o.queryParameters['page'] as int) * 10)], page: o.queryParameters['page'] as int, totalPages: 3, total: 41);
      final bloc = build()..add(const UsersListStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == UsersListStatus.success);

      final seen = <UsersListState>[];
      final sub = bloc.stream.listen(seen.add);
      addTearDown(sub.cancel);
      bloc.add(const UsersPageSelected(3));
      await bloc.stream.firstWhere((s) => s.page == 3 && !s.loadingPage && s.items.single.id == 30);

      expect(seen.first.loadingPage, isTrue);
      expect(seen.first.items.single.id, 10, reason: 'la página anterior se sigue viendo');
      expect(adapter.requests.last.queryParameters['page'], 3);
    });

    test('un fallo queda con su mensaje y se reintenta', () async {
      handler = (_) => errorResponse(500);
      final bloc = build()..add(const UsersListStarted());
      addTearDown(bloc.close);

      final failed = await bloc.stream.firstWhere((s) => s.status == UsersListStatus.failure);
      expect(failed.failure, isA<ServerFailure>());

      handler = (_) => pagedResponse([userJson()]);
      bloc.add(const UsersListStarted());
      final ok = await bloc.stream.firstWhere((s) => s.status == UsersListStatus.success);
      expect(ok.items, hasLength(1));
      expect(ok.failure, isNull);
    });

    test('refresh termina aunque nada cambie', () async {
      handler = (_) => pagedResponse([userJson()]);
      final bloc = build()..add(const UsersListStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == UsersListStatus.success);

      await bloc.refresh().timeout(const Duration(seconds: 2));
      expect(bloc.state.items, hasLength(1));
    });

    test('si alguien cambia en otra parte de la app, la página se recarga sola', () async {
      handler = (o) => o.method == 'PUT' ? jsonResponse(200, userJson()) : pagedResponse([userJson()]);
      final bloc = build()..add(const UsersListStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == UsersListStatus.success);
      final before = adapter.requests.where((r) => r.path == '/admin/users').length;

      await repository.setRoles(1, [3]);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(adapter.requests.where((r) => r.path == '/admin/users' && r.method == 'GET').length, before + 1);
    });
  });

  group('UsersSummaryBloc', () {
    test('carga las cifras', () async {
      handler = (_) => jsonResponse(200, usersSummaryJson);
      final bloc = UsersSummaryBloc(repository: repository)..add(const UsersSummaryRequested());
      addTearDown(bloc.close);

      final ready = await bloc.stream.firstWhere((s) => s.status == UsersSummaryStatus.ready);
      expect(ready.summary!.withoutRole, 2);
      expect(ready.unavailable, isFalse);
    });

    test('si falla queda «no disponible», y si ya había cifras las conserva', () async {
      handler = (_) => errorResponse(500);
      final bloc = UsersSummaryBloc(repository: repository)..add(const UsersSummaryRequested());
      addTearDown(bloc.close);
      expect((await bloc.stream.firstWhere((s) => s.status == UsersSummaryStatus.failure)).unavailable, isTrue);

      handler = (_) => jsonResponse(200, usersSummaryJson);
      bloc.add(const UsersSummaryRequested());
      await bloc.stream.firstWhere((s) => s.status == UsersSummaryStatus.ready);

      handler = (_) => errorResponse(500);
      bloc.add(const UsersSummaryRequested());
      final failedAgain = await bloc.stream.firstWhere((s) => s.status == UsersSummaryStatus.failure);
      expect(failedAgain.summary, isNotNull);
      expect(failedAgain.unavailable, isFalse);
    });

    test('avisa cuando termina, con éxito o con error, y se recarga tras un cambio', () async {
      handler = (o) => o.method == 'POST' ? jsonResponse(200, userJson()) : jsonResponse(200, usersSummaryJson);
      final bloc = UsersSummaryBloc(repository: repository);
      addTearDown(bloc.close);

      final done = Completer<void>();
      bloc.add(UsersSummaryRequested(done: done));
      await done.future.timeout(const Duration(seconds: 2));

      await repository.setActive(1, active: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(adapter.requests.where((r) => r.path == '/admin/users/summary').length, 2);

      handler = (_) => errorResponse(500);
      final failed = Completer<void>();
      bloc.add(UsersSummaryRequested(done: failed));
      await failed.future.timeout(const Duration(seconds: 2));
    });
  });

  group('PendingUsersBloc', () {
    test('carga la lista de pendientes', () async {
      handler = (_) => jsonResponse(200, [pendingJson(), pendingJson(id: 8, name: 'Marta', email: 'm@x.co')]);
      final bloc = PendingUsersBloc(repository: repository)..add(const PendingUsersRequested());
      addTearDown(bloc.close);

      final ready = await bloc.stream.firstWhere((s) => s.status == PendingStatus.ready);
      expect(ready.users.map((u) => u.fullName), ['Luis Nuevo', 'Marta']);
    });

    test('sin pendientes queda lista vacía, no error', () async {
      handler = (_) => jsonResponse(200, <Object?>[]);
      final bloc = PendingUsersBloc(repository: repository)..add(const PendingUsersRequested());
      addTearDown(bloc.close);

      final ready = await bloc.stream.firstWhere((s) => s.status == PendingStatus.ready);
      expect(ready.users, isEmpty);
      expect(ready.failure, isNull);
    });

    test('un fallo sin datos queda en error con reintento; una recarga que falla deja la lista', () async {
      handler = (_) => errorResponse(500);
      final bloc = PendingUsersBloc(repository: repository)..add(const PendingUsersRequested());
      addTearDown(bloc.close);
      expect((await bloc.stream.firstWhere((s) => s.status == PendingStatus.failure)).users, isEmpty);

      handler = (_) => jsonResponse(200, [pendingJson()]);
      bloc.add(const PendingUsersRequested());
      await bloc.stream.firstWhere((s) => s.status == PendingStatus.ready);

      handler = (_) => errorResponse(500);
      final done = Completer<void>();
      bloc.add(PendingUsersRequested(done: done));
      await done.future.timeout(const Duration(seconds: 2));
      expect(bloc.state.status, PendingStatus.ready);
      expect(bloc.state.users, hasLength(1));
      expect(bloc.state.failure, isNotNull);
    });

    test('al asignar un rol la lista se recarga sola y la persona sale', () async {
      var pending = [pendingJson(), pendingJson(id: 8, name: 'Marta', email: 'm@x.co')];
      handler = (o) {
        if (o.method == 'PUT') {
          pending = [pendingJson(id: 8, name: 'Marta', email: 'm@x.co')];
          return jsonResponse(200, userJson(id: 7));
        }
        return jsonResponse(200, pending);
      };
      final bloc = PendingUsersBloc(repository: repository)..add(const PendingUsersRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == PendingStatus.ready && s.users.length == 2);

      await repository.setRoles(7, [3]);
      final after = await bloc.stream.firstWhere((s) => s.status == PendingStatus.ready && s.users.length == 1);
      expect(after.users.single.fullName, 'Marta');
    });
  });

  group('RolesBloc', () {
    test('con detalle (puede asignar) trae descripción y conteos del servidor', () async {
      handler = (_) => jsonResponse(200, [managedRoleJson(users: 9)]);
      final bloc = RolesBloc(repository: repository, detailed: true)..add(const RolesRequested());
      addTearDown(bloc.close);

      final ready = await bloc.stream.firstWhere((s) => s.status == RolesStatus.ready);
      expect(ready.roles.single.description, 'Atiende tickets asignados');
      expect(adapter.requests.single.path, '/admin/roles/manage');
    });

    test('sin detalle usa la lista de roles y el resumen', () async {
      handler = (o) => o.path == '/admin/roles' ? jsonResponse(200, [roleJson()]) : jsonResponse(200, usersSummaryJson);
      final bloc = RolesBloc(repository: repository, detailed: false)..add(const RolesRequested());
      addTearDown(bloc.close);

      final ready = await bloc.stream.firstWhere((s) => s.status == RolesStatus.ready);
      expect((ready.roles.single.code, ready.roles.single.userCount), ('TECHNICIAN', 9));
    });

    test('un fallo queda en error con reintento', () async {
      handler = (_) => errorResponse(403, code: 'forbidden');
      final bloc = RolesBloc(repository: repository, detailed: true)..add(const RolesRequested());
      addTearDown(bloc.close);

      final failed = await bloc.stream.firstWhere((s) => s.status == RolesStatus.failure);
      expect(failed.failure, isA<ForbiddenFailure>());
    });
  });

  group('AssignableRolesCubit', () {
    test('carga los roles activos', () async {
      handler = (_) => jsonResponse(200, [roleJson(), roleJson(id: 1, code: 'ADMIN', name: 'Administrador')]);
      final cubit = AssignableRolesCubit(repository);
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.status, AssignableRolesStatus.ready);
      expect(cubit.state.roles.map((r) => r.code), ['TECHNICIAN', 'ADMIN']);
    });

    test('si falla queda en error y se puede reintentar', () async {
      handler = (_) => errorResponse(500);
      final cubit = AssignableRolesCubit(repository);
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.status, AssignableRolesStatus.failure);

      handler = (_) => jsonResponse(200, [roleJson()]);
      await cubit.load();
      expect(cubit.state.status, AssignableRolesStatus.ready);
    });
  });
}
