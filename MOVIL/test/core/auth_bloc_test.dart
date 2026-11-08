import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/repositories/auth/auth_repository.dart';
import 'package:mantix/core/auth/bloc/auth_bloc.dart';
import 'package:mantix/core/config/app_config.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/network/api_client.dart';

import '../support/fakes.dart';

const config = AppConfig(apiBaseUrl: 'http://api.test', appVersion: '1.0.0');

Map<String, Object?> me({
  bool active = true,
  List<String> roles = const ['TECNICO'],
  List<String> permissions = const ['tickets:ver_asignados'],
}) =>
    {
      'id': 3,
      'email': 'tec@example.com',
      'full_name': 'Tec Uno',
      'employee_code': 'E-3',
      'is_active': active,
      'roles': [for (final r in roles) {'code': r, 'name': r}],
      'permissions': [for (final p in permissions) {'code': p, 'name': p}],
    };

AuthBloc authBloc({required FakeAuthProvider auth, required FakeAdapter adapter, void Function()? onExpired}) {
  final dio = createApiClient(config: config, auth: auth, adapter: adapter, onSessionExpired: onExpired);
  return AuthBloc(auth: auth, repository: AuthRepository(dio));
}

/// Arranca el Bloc y espera a que termine de cargar (la primera emisión).
Future<void> start(AuthBloc bloc) async {
  bloc.add(const AuthStarted());
  await bloc.stream.first;
}

Matcher failureOf<S extends AuthState>(Matcher failure) => isA<S>().having((s) => (s as dynamic).failure, 'failure', failure);

void main() {
  group('AuthStarted', () {
    late FakeAdapter adapter;
    setUp(() => adapter = FakeAdapter((_) => jsonResponse(200, me())));

    blocTest<AuthBloc, AuthState>(
      'sin token queda sin sesión y no llama al servidor',
      build: () => authBloc(auth: FakeAuthProvider(token: null), adapter: adapter),
      act: start,
      expect: () => [const AuthUnauthenticated()],
      verify: (_) => expect(adapter.requests, isEmpty),
    );

    blocTest<AuthBloc, AuthState>(
      'con token carga el perfil de GET /auth/me',
      build: () => authBloc(auth: FakeAuthProvider(), adapter: adapter),
      act: start,
      expect: () => [
        isA<Authenticated>().having((s) => s.profile.fullName, 'fullName', 'Tec Uno'),
      ],
      verify: (_) => expect(adapter.requests.single.path, '/auth/me'),
    );

    blocTest<AuthBloc, AuthState>(
      'un usuario inactivo no entra',
      build: () => authBloc(
        auth: FakeAuthProvider(),
        adapter: FakeAdapter((_) => jsonResponse(200, me(active: false))),
      ),
      act: start,
      expect: () => [failureOf<AuthUnauthenticated>(isA<ForbiddenFailure>())],
    );

    blocTest<AuthBloc, AuthState>(
      'un 403 deja sin sesión',
      build: () => authBloc(
        auth: FakeAuthProvider(),
        adapter: FakeAdapter((_) => jsonResponse(403, {'detail': 'x', 'code': 'forbidden'})),
      ),
      act: start,
      expect: () => [isA<AuthUnauthenticated>()],
    );

    blocTest<AuthBloc, AuthState>(
      'un 500 es recuperable: sin conexión, no sin sesión',
      build: () => authBloc(auth: FakeAuthProvider(), adapter: FakeAdapter((_) => jsonResponse(500, {'detail': 'x'}))),
      act: start,
      expect: () => [failureOf<AuthUnavailable>(isA<ServerFailure>())],
    );

    blocTest<AuthBloc, AuthState>(
      'un error de red no se confunde con sesión caducada',
      build: () => authBloc(
        auth: FakeAuthProvider(),
        adapter: FakeAdapter((options) => throw DioException(requestOptions: options, type: DioExceptionType.connectionError)),
      ),
      act: start,
      expect: () => [failureOf<AuthUnavailable>(isA<NetworkFailure>())],
    );

    blocTest<AuthBloc, AuthState>(
      'una cuenta sin roles queda pendiente de aprobación',
      build: () => authBloc(
        auth: FakeAuthProvider(),
        adapter: FakeAdapter((_) => jsonResponse(200, me(roles: const [], permissions: const []))),
      ),
      act: start,
      expect: () => [isA<AuthPending>()],
    );

    blocTest<AuthBloc, AuthState>(
      'una cuenta con rol y sin permisos queda sin acceso asignado',
      build: () => authBloc(
        auth: FakeAuthProvider(),
        adapter: FakeAdapter((_) => jsonResponse(200, me(permissions: const []))),
      ),
      act: start,
      expect: () => [isA<AuthNoAccess>()],
    );
  });

  test('empieza con la sesión desconocida', () {
    final bloc = authBloc(auth: FakeAuthProvider(), adapter: FakeAdapter((_) => jsonResponse(200, me())));
    addTearDown(bloc.close);
    expect(bloc.state, const AuthUnknown());
  });

  test('volver a comprobar pasa por la carga y se recupera tras un fallo', () async {
    var fail = true;
    final adapter = FakeAdapter((_) => fail ? jsonResponse(500, {'detail': 'x'}) : jsonResponse(200, me()));
    final bloc = authBloc(auth: FakeAuthProvider(), adapter: adapter);
    addTearDown(bloc.close);
    bloc.add(const AuthStarted());
    await bloc.stream.firstWhere((s) => s is AuthUnavailable);

    fail = false;
    final emitted = <AuthState>[];
    final subscription = bloc.stream.listen(emitted.add);
    bloc.add(const AuthRefreshRequested());
    await bloc.stream.firstWhere((s) => s is Authenticated);
    await subscription.cancel();

    expect(emitted, [const AuthUnknown(), isA<Authenticated>()]);
  });

  test('cerrar sesión llama al proveedor y deja sin sesión', () async {
    final auth = FakeAuthProvider();
    final bloc = authBloc(auth: auth, adapter: FakeAdapter((_) => jsonResponse(200, me())));
    addTearDown(bloc.close);
    bloc.add(const AuthStarted());
    await bloc.stream.firstWhere((s) => s is Authenticated);

    bloc.add(const AuthSignOutRequested());
    await bloc.stream.firstWhere((s) => s is AuthUnauthenticated);

    expect(auth.signedOut, isTrue);
    expect(bloc.state, const AuthUnauthenticated());
  });

  test('la sesión expirada cierra la sesión con un mensaje claro y avisa una sola vez', () async {
    final auth = FakeAuthProvider();
    final bloc = authBloc(auth: auth, adapter: FakeAdapter((_) => jsonResponse(200, me())));
    addTearDown(bloc.close);
    bloc.add(const AuthStarted());
    await bloc.stream.firstWhere((s) => s is Authenticated);

    bloc
      ..add(const AuthSessionExpired())
      ..add(const AuthSessionExpired());
    await bloc.stream.firstWhere((s) => s is AuthUnauthenticated);
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state, const AuthUnauthenticated(failure: UnauthorizedFailure()));
    expect(auth.signedOut, isTrue);
  });

  test('un 401 que persiste tras la renovación llega al AuthBloc por el callback del cliente', () async {
    final auth = FakeAuthProvider();
    late final AuthBloc bloc;
    final adapter = FakeAdapter((options) {
      // /auth/me responde bien; cualquier otra ruta da 401 aunque se renueve el token.
      if (options.path == '/auth/me') return jsonResponse(200, me());
      return jsonResponse(401, {'detail': 'x', 'code': 'unauthorized'});
    });
    final dio = createApiClient(config: config, auth: auth, adapter: adapter, onSessionExpired: () => bloc.add(const AuthSessionExpired()));
    bloc = AuthBloc(auth: auth, repository: AuthRepository(dio));
    addTearDown(bloc.close);
    bloc.add(const AuthStarted());
    await bloc.stream.firstWhere((s) => s is Authenticated);

    // El aviso llega antes de que termine la petición: se escucha antes de lanzarla.
    final expired = bloc.stream.firstWhere((s) => s is AuthUnauthenticated);
    await expectLater(dio.get<Object?>('/maintenance/requests'), throwsA(isA<DioException>()));
    await expired;

    expect(auth.refreshCalls, 1, reason: 'un solo intento de renovación');
    expect(bloc.state, const AuthUnauthenticated(failure: UnauthorizedFailure()));
  });

  test('cuando el proveedor emite un inicio de sesión se carga el perfil', () async {
    final auth = FakeAuthProvider(token: null);
    final bloc = authBloc(auth: auth, adapter: FakeAdapter((_) => jsonResponse(200, me())));
    addTearDown(bloc.close);
    bloc.add(const AuthStarted());
    await bloc.stream.firstWhere((s) => s is AuthUnauthenticated);

    auth.simulateSignIn();
    await bloc.stream.firstWhere((s) => s is Authenticated);

    expect(bloc.state.profile?.fullName, 'Tec Uno');
  });

  test('si el proveedor cierra la sesión tras una expiración no se pierde el mensaje', () async {
    final auth = FakeAuthProvider();
    final bloc = authBloc(auth: auth, adapter: FakeAdapter((_) => jsonResponse(200, me())));
    addTearDown(bloc.close);
    bloc.add(const AuthStarted());
    await bloc.stream.firstWhere((s) => s is Authenticated);
    bloc.add(const AuthSessionExpired());
    await bloc.stream.firstWhere((s) => s is AuthUnauthenticated);

    auth.simulateSignIn(token: null);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(bloc.state, const AuthUnauthenticated(failure: UnauthorizedFailure()));
  });
}
