import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/app.dart';
import 'package:mantix/core/config/app_config.dart';
import 'package:mantix/core/network/api_client.dart';
import 'package:mantix/core/network/providers.dart';

import 'support/fakes.dart';

const config = AppConfig(apiBaseUrl: 'http://api.test', appVersion: '1.0.0');

Map<String, Object?> me(List<String> roles, List<String> permissions) => {
      'id': 1,
      'email': 'a@b.c',
      'full_name': 'Ana Pérez',
      'employee_code': null,
      'is_active': true,
      'roles': [for (final r in roles) {'code': r, 'name': r}],
      'permissions': [for (final p in permissions) {'code': p, 'name': p}],
    };

Widget appWith({String? token = 'token-0', required Object body}) {
  final auth = FakeAuthProvider(token: token);
  return ProviderScope(
    overrides: [
      authProviderProvider.overrideWithValue(auth),
      apiClientProvider.overrideWithValue(
        createApiClient(config: config, auth: auth, adapter: FakeAdapter((_) => jsonResponse(200, body))),
      ),
    ],
    child: const MantixApp(),
  );
}

void main() {
  testWidgets('sin sesión muestra el acceso', (tester) async {
    await tester.pumpWidget(appWith(token: null, body: {}));
    await tester.pumpAndSettle();

    expect(find.text('Inicio de sesión no disponible'), findsOneWidget);
  });

  testWidgets('cuenta sin roles muestra pendiente de aprobación', (tester) async {
    await tester.pumpWidget(appWith(body: me([], [])));
    await tester.pumpAndSettle();

    expect(find.text('Cuenta pendiente de aprobación'), findsOneWidget);
    expect(find.text('Volver a comprobar'), findsOneWidget);
  });

  testWidgets('cuenta con rol y sin permisos muestra sin acceso asignado', (tester) async {
    await tester.pumpWidget(appWith(body: me(['X'], [])));
    await tester.pumpAndSettle();

    expect(find.text('Sin acceso asignado'), findsOneWidget);
    expect(find.text('Cuenta pendiente de aprobación'), findsNothing);
  });

  testWidgets('técnico aterriza en su bandeja de trabajo', (tester) async {
    await tester.pumpWidget(appWith(body: me(['TECNICO'], ['tickets:ver_asignados'])));
    await tester.pumpAndSettle();

    expect(find.text('Mi bandeja de trabajo'), findsOneWidget);
  });

  testWidgets('cuenta activa sin criterio de inicio aterriza en Perfil con sus permisos', (tester) async {
    await tester.pumpWidget(appWith(body: me(['X'], ['tickets:ver'])));
    await tester.pumpAndSettle();

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('tickets:ver'), findsOneWidget);
  });

  testWidgets('los botones táctiles miden al menos 48 px', (tester) async {
    await tester.pumpWidget(appWith(body: me([], [])));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.widgetWithText(FilledButton, 'Volver a comprobar'));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
