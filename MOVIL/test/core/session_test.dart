import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/auth/session.dart';
import 'package:mantix/core/config/app_config.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/core/network/api_client.dart';
import 'package:mantix/core/network/providers.dart';

import '../support/fakes.dart';

const config = AppConfig(apiBaseUrl: 'http://api.test', appVersion: '1.0.0');

Map<String, Object?> me({bool active = true, List<String> roles = const ['TECNICO'], List<String> permissions = const ['tickets:ver_asignados']}) => {
      'id': 3,
      'email': 'tec@example.com',
      'full_name': 'Tec Uno',
      'employee_code': 'E-3',
      'is_active': active,
      'roles': [for (final r in roles) {'code': r, 'name': r}],
      'permissions': [for (final p in permissions) {'code': p, 'name': p}],
    };

ProviderContainer containerWith({required FakeAuthProvider auth, required FakeAdapter adapter}) {
  final container = ProviderContainer(overrides: [
    authProviderProvider.overrideWithValue(auth),
    apiClientProvider.overrideWithValue(createApiClient(config: config, auth: auth, adapter: adapter)),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('sin token queda sin sesión y no llama al servidor', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, me()));
    final container = containerWith(auth: FakeAuthProvider(token: null), adapter: adapter);

    final state = await container.read(sessionProvider.future);

    expect(state, isA<SignedOut>());
    expect(adapter.requests, isEmpty);
  });

  test('con token carga el perfil de GET /auth/me', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, me()));
    final container = containerWith(auth: FakeAuthProvider(), adapter: adapter);

    final state = await container.read(sessionProvider.future);

    expect(state, isA<SignedIn>());
    expect((state as SignedIn).profile.fullName, 'Tec Uno');
    expect(adapter.requests.single.path, '/auth/me');
  });

  test('un usuario inactivo no entra', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, me(active: false)));
    final container = containerWith(auth: FakeAuthProvider(), adapter: adapter);

    final state = await container.read(sessionProvider.future);

    expect(state, isA<SignedOut>());
    expect((state as SignedOut).failure, isA<ForbiddenFailure>());
  });

  test('un 403 deja sin sesión', () async {
    final adapter = FakeAdapter((_) => jsonResponse(403, {'detail': 'x', 'code': 'forbidden'}));
    final container = containerWith(auth: FakeAuthProvider(), adapter: adapter);

    expect(await container.read(sessionProvider.future), isA<SignedOut>());
  });

  test('un 500 es recuperable: sin conexión, no sin sesión', () async {
    final adapter = FakeAdapter((_) => jsonResponse(500, {'detail': 'x'}));
    final container = containerWith(auth: FakeAuthProvider(), adapter: adapter);

    final state = await container.read(sessionProvider.future);

    expect(state, isA<SessionUnavailable>());
    expect((state as SessionUnavailable).failure, isA<ServerFailure>());
  });

  test('refresh vuelve a cargar y se recupera tras un fallo', () async {
    var fail = true;
    final adapter = FakeAdapter((_) => fail ? jsonResponse(500, {'detail': 'x'}) : jsonResponse(200, me()));
    final container = containerWith(auth: FakeAuthProvider(), adapter: adapter);
    expect(await container.read(sessionProvider.future), isA<SessionUnavailable>());

    fail = false;
    await container.read(sessionProvider.notifier).refresh();

    expect(container.read(sessionProvider).value, isA<SignedIn>());
  });

  test('cerrar sesión llama al proveedor y deja sin sesión', () async {
    final auth = FakeAuthProvider();
    final adapter = FakeAdapter((_) => jsonResponse(200, me()));
    final container = containerWith(auth: auth, adapter: adapter);
    await container.read(sessionProvider.future);

    await container.read(sessionProvider.notifier).signOut();

    expect(auth.signedOut, isTrue);
    expect(container.read(sessionProvider).value, isA<SignedOut>());
  });

  test('un error de red no se confunde con sesión caducada', () async {
    final adapter = FakeAdapter((options) => throw DioException(requestOptions: options, type: DioExceptionType.connectionError));
    final container = containerWith(auth: FakeAuthProvider(), adapter: adapter);

    final state = await container.read(sessionProvider.future);

    expect(state, isA<SessionUnavailable>());
    expect((state as SessionUnavailable).failure, isA<NetworkFailure>());
  });
}
