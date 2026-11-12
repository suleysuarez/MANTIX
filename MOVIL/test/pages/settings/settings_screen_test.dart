import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/theme/app_colors.dart';
import 'package:mantix/pages/settings/settings_screen.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

const _admin = {'configuracion:ver', 'configuracion:editar'};
const _viewer = {'configuracion:ver'};

Map<String, Object?> _health({String environment = 'development', String clerkStatus = 'error'}) => {
      'generated_at': '2026-11-12T15:00:00Z',
      'overall': 'error',
      'environment': {'name': environment, 'version': '1.4.0', 'max_upload_mb': 10, 'reminder_interval_minutes': 60, 'scheduler_enabled': true},
      'users': {'total': 13, 'active': 12, 'inactive': 1, 'without_role': 2},
      'roles': [
        {'id': 1, 'name': 'Administrador', 'is_active': true, 'users': 1, 'permissions': 40},
      ],
      'audit': {
        'last_24h': 5,
        'recent': [
          {'id': 1, 'action': 'auth.login', 'entity_type': 'user', 'by': 'Ana', 'at': '2026-11-12T14:00:00Z'},
        ],
      },
      'jobs': <Object?>[],
      'integrations': [
        {'key': 'database', 'name': 'Base de datos', 'status': 'ok', 'detail': 'Conectada', 'latency_ms': 12.0},
        {'key': 'clerk', 'name': 'Autenticación (Clerk)', 'status': clerkStatus, 'detail': 'Falta la clave secreta'},
        {'key': 'storage', 'name': 'Almacenamiento de adjuntos', 'status': 'ok', 'detail': 'Disponible'},
      ],
    };

void main() {
  late FakeAdapter adapter;
  late Map<String, Object?> health;

  setUp(() {
    health = _health();
    adapter = FakeAdapter((options) => switch (options.path) {
          '/settings/health' => jsonResponse(200, health),
          '/settings/organization' => jsonResponse(200, {'company_name': 'Mantix'}),
          '/settings/categories' || '/priorities' => jsonResponse(200, <Object?>[]),
          _ => errorResponse(404),
        });
  });

  Future<void> open(WidgetTester tester, {Set<String> permissions = _admin, Size size = const Size(1000, 3200), double textScale = 1}) async {
    await pumpScreen(tester, const SettingsScreen(), adapter, permissions: permissions, size: size, textScale: textScale);
    await tester.pumpAndSettle();
  }

  group('estado del sistema', () {
    testWidgets('no muestra Clerk: la app móvil no lo usa', (tester) async {
      await open(tester);

      expect(find.textContaining('Clerk'), findsNothing);
      expect(find.text('Base de datos'), findsOneWidget);
      expect(find.text('Almacenamiento de adjuntos'), findsOneWidget);
    });

    testWidgets('el estado general ignora a Clerk: un error suyo no pone «Requiere atención»', (tester) async {
      await open(tester);

      expect(find.text('Operativo'), findsOneWidget);
      expect(find.text('Requiere atención'), findsNothing);
    });

    testWidgets('un error de una integración que sí se ve sigue avisando', (tester) async {
      (health['integrations']! as List<Object?>)[0] = {'key': 'database', 'name': 'Base de datos', 'status': 'error', 'detail': 'Sin conexión'};
      await open(tester);

      expect(find.text('Requiere atención'), findsOneWidget);
    });

    testWidgets('la información del servicio va dentro de la misma tarjeta', (tester) async {
      await open(tester);

      // Algún contenedor de «Información del servicio» contiene también el título «Estado del sistema».
      final containers = tester.widgetList<Column>(find.ancestor(of: find.text('Información del servicio'), matching: find.byType(Column)));
      expect(containers.any((column) => find.descendant(of: find.byWidget(column), matching: find.text('Estado del sistema')).evaluate().isNotEmpty), isTrue, reason: 'comparten tarjeta');
      expect(find.text('Versión API'), findsOneWidget);
      expect(find.text('Información del servicio'), findsOneWidget, reason: 'ya no hay una tarjeta aparte');
    });
  });

  group('entorno', () {
    testWidgets('«development» se lee «Desarrollo»', (tester) async {
      await open(tester);

      expect(find.text('Desarrollo'), findsOneWidget);
      expect(find.text('development'), findsNothing);
    });

    testWidgets('«production» se lee «Producción»', (tester) async {
      health = _health(environment: 'production');
      await open(tester);

      expect(find.text('Producción'), findsOneWidget);
      expect(find.text('Desarrollo'), findsNothing);
      expect(find.text('production'), findsNothing);
    });
  });

  group('color y permisos', () {
    testWidgets('el botón de actualizar y el de catálogos son mostaza', (tester) async {
      await open(tester);

      final refresh = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh_rounded));
      expect(refresh.style!.backgroundColor!.resolve({}), AppColors.mustard);
      final catalogs = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Administrar catálogos'));
      expect(catalogs.style!.backgroundColor!.resolve({}), AppColors.mustard);
    });

    testWidgets('sin configuracion:editar se consulta pero no se edita', (tester) async {
      await open(tester, permissions: _viewer);

      expect(find.text('Consultar catálogos'), findsOneWidget);
      expect(find.text('Administrar catálogos'), findsNothing);
      expect(find.byTooltip('Editar organización'), findsNothing);
    });

    testWidgets('con configuracion:editar se puede editar la organización', (tester) async {
      await open(tester);

      expect(find.byTooltip('Editar organización'), findsOneWidget);
    });
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('configuración en ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        await open(tester, size: size, textScale: 1.3);

        expect(find.text('Configuración'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
