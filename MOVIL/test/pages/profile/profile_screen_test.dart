import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mantix/bloc/profile/avatar_cubit.dart';
import 'package:mantix/pages/profile/profile_screen.dart';

import '../../support/fakes.dart';
import '../../support/profile_support.dart';
import '../../support/requests_support.dart';

const _editor = {'perfil:ver', 'perfil:editar', 'tickets:ver'};
const _viewer = {'perfil:ver'};

/// Un PNG real de 1×1 píxel: la foto se decodifica de verdad en la prueba.
final _tinyPng = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) profileHandler;
  late ResponseBody Function(RequestOptions) historyHandler;
  // Dos horas después del último acceso de los datos de prueba: «Hace 2 h», sin depender de la zona horaria.
  final now = DateTime.parse('2026-11-12T17:00:00Z');

  setUp(() {
    profileHandler = (options) => jsonResponse(200, profileJson());
    historyHandler = (_) => pagedResponse([
          historyJson(id: 1),
          historyJson(id: 2, action: 'roles.replaced', kind: 'security', actor: 'Admin Demo', at: '2026-11-11T10:00:00Z'),
        ]);
    adapter = FakeAdapter((options) {
      if (options.path == '/profile/history') return historyHandler(options);
      if (options.path.startsWith('/profile')) return profileHandler(options);
      return errorResponse(404);
    });
  });

  Future<void> open(WidgetTester tester, {Set<String> permissions = _editor, Size size = const Size(1000, 3000), double textScale = 1}) async {
    await pumpScreen(tester, ProfileScreen(clock: () => now), adapter, permissions: permissions, size: size, textScale: textScale);
    await tester.pumpAndSettle();
  }

  List<RequestOptions> writes() => adapter.requests.where((r) => r.method != 'GET').toList();

  group('contenido', () {
    testWidgets('muestra el encabezado, mis datos y mi actividad', (tester) async {
      await open(tester);

      // Encabezado: nombre, correo, rol y estado de la cuenta.
      expect(find.text('Ana Pérez'), findsWidgets);
      expect(find.text('ana@mantix.test'), findsWidgets);
      expect(find.text('Técnico'), findsOneWidget);
      expect(find.text('Cuenta activa'), findsOneWidget);
      // Mis datos.
      expect(find.text('Mis datos'), findsOneWidget);
      expect(find.text('+57 300 123 4567'), findsOneWidget);
      expect(find.text('Hace 2 h'), findsOneWidget);
      expect(find.text('1 oct 2026'), findsOneWidget);
      // Mi actividad.
      expect(find.text('Mi actividad'), findsOneWidget);
      expect(find.text('Iniciaste sesión'), findsOneWidget);
      expect(find.text('Cambiaron tus roles'), findsOneWidget);
      expect(find.textContaining('por Admin Demo'), findsOneWidget);
    });

    testWidgets('un dato que falta sale como «Sin registrar» y nunca como un «Nunca» inventado', (tester) async {
      profileHandler = (_) => jsonResponse(200, profileJson(phone: null, lastLogin: null));
      await open(tester);

      expect(find.text('Sin registrar'), findsNWidgets(2), reason: 'teléfono y último acceso');
      expect(find.text('Nunca'), findsNothing);
    });

    testWidgets('no muestra los permisos', (tester) async {
      await open(tester);

      expect(find.textContaining('Mis permisos'), findsNothing);
      expect(find.text('tickets:ver'), findsNothing);
    });

    testWidgets('sin actividad lo dice', (tester) async {
      historyHandler = (_) => pagedResponse(const []);
      await open(tester);

      expect(find.text('Aún no hay actividad'), findsOneWidget);
    });

    testWidgets('la actividad se pagina con números y cada página sustituye a la anterior', (tester) async {
      historyHandler = (options) {
        final page = options.queryParameters['page'] as int;
        return pagedResponse([historyJson(id: page, action: page == 1 ? 'auth.login' : 'profile.updated', kind: page == 1 ? 'session' : 'profile')], page: page, totalPages: 2, total: 2);
      };
      await open(tester);
      expect(find.text('Iniciaste sesión'), findsOneWidget);
      expect(find.text('Actualizaste tus datos'), findsNothing);
      expect(find.text('Ver más'), findsNothing, reason: 'ya no hay botón «Ver más»');

      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();

      expect(find.text('Actualizaste tus datos'), findsOneWidget);
      expect(find.text('Iniciaste sesión'), findsNothing, reason: 'la página nueva sustituye a la anterior');
      expect(find.byTooltip('Página siguiente'), findsNothing);
      expect(find.byTooltip('Página anterior'), findsOneWidget);
    });

    testWidgets('si no cargan los datos queda lo que sabe la sesión y un reintento', (tester) async {
      profileHandler = (_) => errorResponse(500);
      await open(tester);

      expect(find.text('Ana Pérez'), findsOneWidget, reason: 'el encabezado sale de la sesión');
      expect(find.text('No pudimos cargar tus datos'), findsOneWidget);
      expect(find.text('Editar'), findsNothing, reason: 'sin datos no hay qué editar');

      profileHandler = (_) => jsonResponse(200, profileJson());
      await tester.tap(find.text('Reintentar').first);
      await tester.pumpAndSettle();
      expect(find.text('+57 300 123 4567'), findsOneWidget);
    });
  });

  group('permisos', () {
    testWidgets('sin perfil:editar no hay editar ni cambiar la foto', (tester) async {
      await open(tester, permissions: _viewer);

      expect(find.text('Editar'), findsNothing);
      expect(find.byIcon(Icons.photo_camera_rounded), findsNothing);
    });

    testWidgets('con perfil:editar se puede editar y cambiar la foto', (tester) async {
      await open(tester);

      expect(find.text('Editar'), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
    });
  });

  group('editar mis datos', () {
    ResponseBody respond(RequestOptions options) {
      if (options.method == 'PATCH') return jsonResponse(200, profileJson(name: 'Ana María Pérez'));
      return jsonResponse(200, profileJson());
    }

    testWidgets('la hoja trae lo actual, el correo no se edita y guarda solo lo que cambió', (tester) async {
      await open(tester);
      profileHandler = respond;

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();

      expect(find.text('Editar mis datos'), findsOneWidget);
      final fields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, 'Ana Pérez');
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '+57 300 123 4567');
      expect(tester.widget<TextField>(fields.at(2)).enabled, isFalse, reason: 'el correo es la identidad de acceso');

      await tester.enterText(fields.at(0), '  Ana María   Pérez ');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(writes().single.method, 'PATCH');
      expect(writes().single.data, {'full_name': 'Ana María Pérez'});
      expect(find.text('Datos actualizados.'), findsOneWidget);
      expect(find.text('Ana María Pérez'), findsWidgets);
    });

    testWidgets('un nombre o un teléfono inválidos se explican y no se pueden guardar', (tester) async {
      await open(tester);
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));

      await tester.enterText(fields.at(0), 'A');
      await tester.pumpAndSettle();
      expect(find.text('Escribe tu nombre (al menos 2 letras).'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar cambios')).onPressed, isNull);

      await tester.enterText(fields.at(0), 'Ana Pérez');
      await tester.enterText(fields.at(1), 'abc');
      await tester.pumpAndSettle();
      expect(find.text('El teléfono solo admite números, espacios, +, ( ) y -.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar cambios')).onPressed, isNull);
      expect(writes(), isEmpty);
    });

    testWidgets('si el servidor lo rechaza se avisa con un mensaje claro', (tester) async {
      await open(tester);
      profileHandler = (options) => options.method == 'PATCH' ? errorResponse(422, code: 'validation_error') : jsonResponse(200, profileJson());

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'Ana María');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('detalle interno'), findsNothing);
    });
  });

  group('foto', () {
    testWidgets('tocar la foto abre el menú: sin foto no ofrece quitarla', (tester) async {
      await open(tester);

      await tester.tap(find.byIcon(Icons.photo_camera_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Tomar una foto'), findsOneWidget);
      expect(find.text('Elegir de la galería'), findsOneWidget);
      expect(find.text('Quitar mi foto'), findsNothing);
    });

    testWidgets('mi foto se ve en todo el encabezado: el perfil la comparte con el AvatarCubit y al quitarla se vacía', (tester) async {
      profileHandler = (options) => options.path == '/profile/avatar' && options.method == 'GET'
          ? ResponseBody.fromBytes(_tinyPng, 200, headers: {
              Headers.contentTypeHeader: ['image/jpeg']
            })
          : jsonResponse(200, profileJson(hasAvatar: options.method != 'DELETE'));
      await open(tester);
      final avatar = tester.element(find.byType(ProfileScreen)).read<AvatarCubit>();
      expect(avatar.state, _tinyPng, reason: 'al cargar el perfil la foto pasa al resto de la app');

      await tester.tap(find.byIcon(Icons.photo_camera_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar mi foto'));
      await tester.pumpAndSettle();

      expect(avatar.state, isNull);
    });

    testWidgets('con foto ofrece quitarla y al hacerlo la borra', (tester) async {
      profileHandler = (options) => options.path == '/profile/avatar' && options.method == 'GET'
          ? ResponseBody.fromBytes(_tinyPng, 200, headers: {
              Headers.contentTypeHeader: ['image/jpeg']
            })
          : jsonResponse(200, profileJson(hasAvatar: options.method != 'DELETE'));
      await open(tester);

      await tester.tap(find.byIcon(Icons.photo_camera_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar mi foto'));
      await tester.pumpAndSettle();

      expect(writes().single.method, 'DELETE');
      expect(find.text('Foto quitada.'), findsOneWidget);
    });
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('perfil, hoja de edición y menú de foto en ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        profileHandler = (_) => jsonResponse(200, profileJson(name: 'María de los Ángeles Fernández de la Vega Hernández'));
        await open(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Editar'));
        await tester.pumpAndSettle();
        expect(find.text('Editar mis datos'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Cerrar'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.photo_camera_rounded));
        await tester.pumpAndSettle();
        expect(find.text('Tomar una foto'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
