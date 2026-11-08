import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/auth/bloc/auth_bloc.dart';
import 'package:mantix/core/auth/bloc/permissions_cubit.dart';
import 'package:mantix/models/auth/user_profile.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

UserProfile profile(Set<String> permissions, {List<String> roles = const ['ROL']}) => UserProfile(
      id: 1,
      email: 'a@b.c',
      fullName: 'Ana',
      isActive: true,
      roles: roles,
      permissions: permissions,
    );

void main() {
  late MockAuthBloc auth;
  setUp(() => auth = MockAuthBloc());

  test('sin sesión no hay permisos', () {
    whenListen(auth, const Stream<AuthState>.empty(), initialState: const AuthUnauthenticated());
    final cubit = PermissionsCubit(auth);
    addTearDown(cubit.close);

    expect(cubit.state.codes, isEmpty);
    expect(cubit.state.can('solicitudes:ver'), isFalse);
  });

  test('con sesión activa expone los permisos efectivos del perfil', () {
    whenListen(
      auth,
      const Stream<AuthState>.empty(),
      initialState: Authenticated(profile(const {'solicitudes:ver', 'solicitudes:crear'})),
    );
    final cubit = PermissionsCubit(auth);
    addTearDown(cubit.close);

    expect(cubit.state.can('solicitudes:crear'), isTrue);
    expect(cubit.state.can('equipos:editar'), isFalse);
  });

  blocTest<PermissionsCubit, PermissionsState>(
    'sigue al AuthBloc: al cerrar la sesión se quedan sin permisos',
    setUp: () => whenListen(
      auth,
      Stream.fromIterable([const AuthUnauthenticated()]),
      initialState: Authenticated(profile(const {'solicitudes:ver'})),
    ),
    build: () => PermissionsCubit(auth),
    expect: () => [const PermissionsState()],
  );

  test('una cuenta pendiente o sin acceso no tiene permisos', () {
    whenListen(auth, const Stream<AuthState>.empty(), initialState: AuthPending(profile(const {}, roles: const [])));
    final cubit = PermissionsCubit(auth);
    addTearDown(cubit.close);

    expect(cubit.state.codes, isEmpty);
  });
}
