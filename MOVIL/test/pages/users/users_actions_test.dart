import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/users/users_screen.dart';
import 'package:mantix/widgets/users/user_cards.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';
import '../../support/users_support.dart';

const _all = {'usuarios:ver', 'usuarios:asignar', 'usuarios:editar', 'usuarios:cambiar_estado'};

/// La persona que usa la app es Ana (id 1): `testProfile` tiene id 1.
void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) writeHandler;

  List<Object?> people() => [
        userJson(id: 1, name: 'Ana Pérez', roles: [roleJson(), roleJson(id: 1, code: 'ADMIN', name: 'Administrador')]),
        userJson(id: 2, name: 'Luis Nuevo', email: 'luis@mantix.test', roles: const [], lastLogin: null, linked: false, phone: null, code: null),
        userJson(id: 3, name: 'Marta Baja', email: 'marta@mantix.test', active: false),
        userJson(id: 4, name: 'Pedro Gómez', email: 'pedro@mantix.test'),
      ];

  setUp(() {
    writeHandler = (_) => jsonResponse(200, userJson(id: 4, name: 'Pedro Gómez'));
    adapter = FakeAdapter((options) {
      if (options.method != 'GET') return writeHandler(options);
      return switch (options.path) {
        '/admin/users/summary' => jsonResponse(200, usersSummaryJson),
        '/admin/users/pending' => jsonResponse(200, [pendingJson()]),
        '/admin/users' => pagedResponse(people()),
        '/admin/roles' => jsonResponse(200, [roleJson(), roleJson(id: 1, code: 'ADMIN', name: 'Administrador'), roleJson(id: 5, code: 'AUDITOR', name: 'Auditor')]),
        '/admin/roles/manage' => jsonResponse(200, <Object?>[]),
        _ => errorResponse(404),
      };
    });
  });

  Future<void> open(WidgetTester tester, {Set<String> permissions = _all, Size size = const Size(1000, 2400), double textScale = 1}) async {
    await pumpScreen(tester, const UsersScreen(), adapter, permissions: permissions, size: size, textScale: textScale);
    await tester.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(UserCard, name));
    await tester.pumpAndSettle();
  }

  Iterable<RequestOptions> writes() => adapter.requests.where((r) => r.method != 'GET');

  Finder inSheet(Finder finder) => find.descendant(of: find.byType(BottomSheet), matching: finder);

  /// Los dos campos de la hoja de contacto: el teléfono y el código (el de búsqueda de la pantalla queda detrás).
  Finder phoneField() => inSheet(find.byType(TextField)).at(0);
  Finder codeField() => inSheet(find.byType(TextField)).at(1);

  /// En pantallas pequeñas los botones quedan abajo: se desplaza la ficha hasta verlos.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final scrollable = inSheet(find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
    // Un poco más, para que el botón no quede pegado al borde de la pantalla.
    await tester.drag(scrollable, const Offset(0, -140), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  group('detalle', () {
    testWidgets('tocar una persona abre su ficha con roles, datos y estado', (tester) async {
      await open(tester);
      await openDetail(tester, 'Pedro Gómez');

      expect(find.text('Detalle del usuario'), findsOneWidget);
      expect(inSheet(find.text('pedro@mantix.test')), findsOneWidget);
      expect(inSheet(find.text('+57 300 123 4567')), findsOneWidget);
      expect(inSheet(find.text('EMP-014')), findsWidgets);
      expect(inSheet(find.text('Técnico')), findsOneWidget);
      expect(inSheet(find.text('Activo')), findsOneWidget);
    });

    testWidgets('una persona sin rol lo dice y los datos que faltan salen como «Sin registrar»', (tester) async {
      await open(tester);
      await openDetail(tester, 'Luis Nuevo');

      expect(inSheet(find.text('Todavía no tiene un rol: no puede usar Mantix.')), findsOneWidget);
      expect(inSheet(find.text('Sin registrar')), findsNWidgets(2));
      expect(inSheet(find.text('Pendiente de primer ingreso')), findsOneWidget);
    });

    testWidgets('cada botón sale solo con su permiso', (tester) async {
      await open(tester, permissions: {'usuarios:ver'});
      await openDetail(tester, 'Pedro Gómez');
      expect(find.text('Cambiar roles'), findsNothing);
      expect(find.text('Editar teléfono y código'), findsNothing);
      expect(find.text('Desactivar cuenta'), findsNothing);
    });

    testWidgets('con solo asignar roles, solo está «Cambiar roles»', (tester) async {
      await open(tester, permissions: {'usuarios:ver', 'usuarios:asignar'});
      await openDetail(tester, 'Pedro Gómez');
      expect(find.text('Cambiar roles'), findsOneWidget);
      expect(find.text('Editar teléfono y código'), findsNothing);
      expect(find.text('Desactivar cuenta'), findsNothing);
    });

    testWidgets('con todos los permisos están los tres botones', (tester) async {
      await open(tester);
      await openDetail(tester, 'Pedro Gómez');
      expect(find.text('Cambiar roles'), findsOneWidget);
      expect(find.text('Editar teléfono y código'), findsOneWidget);
      expect(find.text('Desactivar cuenta'), findsOneWidget);
    });

    testWidgets('en la propia cuenta no se ofrece desactivarse y lo explica', (tester) async {
      await open(tester);
      await openDetail(tester, 'Ana Pérez');

      expect(find.text('Eres tú'), findsOneWidget);
      expect(find.text('Desactivar cuenta'), findsNothing);
      expect(find.text('No puedes desactivar tu propia cuenta.'), findsOneWidget);
      expect(find.text('Cambiar roles'), findsOneWidget);
    });
  });

  group('cambiar roles', () {
    testWidgets('elige roles, manda PUT con ellos y avisa; la ficha se cierra y la lista se recarga', (tester) async {
      await open(tester);
      final loads = adapter.requests.where((r) => r.path == '/admin/users' && r.method == 'GET').length;
      await openDetail(tester, 'Pedro Gómez');

      await tester.tap(find.text('Cambiar roles'));
      await tester.pumpAndSettle();
      expect(find.text('Roles de Pedro Gómez'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Técnico')).value, isTrue, reason: 'ya lo tiene');
      expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Auditor')).value, isFalse);

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Auditor'));
      await tester.pumpAndSettle();
      expect(find.text('2 roles elegidos'), findsOneWidget);
      await tester.tap(find.text('Guardar roles'));
      await tester.pumpAndSettle();

      expect(writes().single.method, 'PUT');
      expect(writes().single.path, '/admin/users/4/roles');
      expect((writes().single.data as Map)['role_ids'], [3, 5], reason: 'en el orden de la lista de roles');
      expect(find.text('Roles de Pedro Gómez actualizados.'), findsOneWidget);
      expect(find.text('Detalle del usuario'), findsNothing, reason: 'la ficha se cerró');
      expect(adapter.requests.where((r) => r.path == '/admin/users' && r.method == 'GET').length, greaterThan(loads), reason: 'la lista se recargó sola');
    });

    testWidgets('sin ningún rol elegido no se puede guardar y lo dice', (tester) async {
      await open(tester);
      await openDetail(tester, 'Pedro Gómez');

      await tester.tap(find.text('Cambiar roles'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Técnico'));
      await tester.pumpAndSettle();

      expect(find.text('Elige al menos un rol.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar roles')).onPressed, isNull);
      expect(writes(), isEmpty);
    });

    testWidgets('cerrar la hoja de roles sin guardar no manda nada', (tester) async {
      await open(tester);
      await openDetail(tester, 'Pedro Gómez');

      await tester.tap(find.text('Cambiar roles'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Auditor'));
      await tester.tap(find.byTooltip('Cerrar').last);
      await tester.pumpAndSettle();

      expect(writes(), isEmpty);
      expect(find.text('Detalle del usuario'), findsOneWidget, reason: 'la ficha sigue abierta');
    });

    testWidgets('dejar los mismos roles lo dice dentro de la ficha y no se pide nada', (tester) async {
      await open(tester);
      await openDetail(tester, 'Pedro Gómez');

      await tester.tap(find.text('Cambiar roles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar roles'));
      await tester.pumpAndSettle();

      expect(writes(), isEmpty);
      expect(inSheet(find.text('Pedro Gómez ya tiene esos roles.')), findsOneWidget);
    });

    testWidgets('quitarse el propio rol de administrador: el motivo sale en la ficha y no se cierra', (tester) async {
      writeHandler = (_) => errorResponse(409, code: 'cannot_revoke_own_admin');
      await open(tester);
      await openDetail(tester, 'Ana Pérez');

      await tester.tap(find.text('Cambiar roles'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Administrador'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar roles'));
      await tester.pumpAndSettle();

      expect(inSheet(find.textContaining('No puedes quitarte tu propio rol de administrador.')), findsOneWidget);
      expect(find.text('Detalle del usuario'), findsOneWidget);
    });

    testWidgets('dejar al sistema sin administradores lo explica', (tester) async {
      writeHandler = (_) => errorResponse(409, code: 'last_admin_protected');
      await open(tester);
      await openDetail(tester, 'Pedro Gómez');

      await tester.tap(find.text('Cambiar roles'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Auditor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar roles'));
      await tester.pumpAndSettle();

      expect(inSheet(find.textContaining('No se puede dejar al sistema sin administradores activos.')), findsOneWidget);
    });

    testWidgets('si los roles no cargan la hoja lo dice y se reintenta', (tester) async {
      var fail = true;
      adapter = FakeAdapter((options) {
        if (options.method != 'GET') return writeHandler(options);
        return switch (options.path) {
          '/admin/users/summary' => jsonResponse(200, usersSummaryJson),
          '/admin/users/pending' => jsonResponse(200, <Object?>[]),
          '/admin/users' => pagedResponse(people()),
          '/admin/roles' => fail ? errorResponse(500) : jsonResponse(200, [roleJson(), roleJson(id: 5, code: 'AUDITOR', name: 'Auditor')]),
          _ => errorResponse(404),
        };
      });
      await open(tester);
      await openDetail(tester, 'Pedro Gómez');

      await tester.tap(find.text('Cambiar roles'));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar roles')).onPressed, isNull);

      fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CheckboxListTile, 'Auditor'), findsOneWidget);
    });
  });

  group('asignar rol a un pendiente', () {
    Future<void> toPending(WidgetTester tester) async {
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Pendientes')));
      await tester.pumpAndSettle();
    }

    testWidgets('el botón «Asignar rol» solo sale con permiso de asignar', (tester) async {
      await open(tester, permissions: {'usuarios:ver'});
      await toPending(tester);
      expect(find.byType(PendingUserCard), findsOneWidget);
      expect(find.text('Asignar rol'), findsNothing);
    });

    testWidgets('elige un rol y manda PUT; la persona sale de la lista', (tester) async {
      var pending = <Object?>[pendingJson()];
      adapter = FakeAdapter((options) {
        if (options.method == 'PUT') {
          pending = <Object?>[];
          return jsonResponse(200, userJson(id: 7, name: 'Luis Nuevo'));
        }
        return switch (options.path) {
          '/admin/users/summary' => jsonResponse(200, usersSummaryJson),
          '/admin/users/pending' => jsonResponse(200, pending),
          '/admin/users' => pagedResponse(people()),
          '/admin/roles' => jsonResponse(200, [roleJson(), roleJson(id: 5, code: 'AUDITOR', name: 'Auditor')]),
          _ => errorResponse(404),
        };
      });
      await open(tester);
      await toPending(tester);

      await tester.tap(find.text('Asignar rol'));
      await tester.pumpAndSettle();
      expect(find.text('Elige los roles de Luis Nuevo.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Asignar roles')).onPressed, isNull, reason: 'todavía no eligió ninguno');
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Técnico'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asignar roles'));
      await tester.pumpAndSettle();

      expect(writes().single.path, '/admin/users/7/roles');
      expect((writes().single.data as Map)['role_ids'], [3]);
      expect(find.text('Roles de Luis Nuevo actualizados.'), findsOneWidget);
      expect(find.byType(PendingUserCard), findsNothing);
      expect(find.text('No hay nadie esperando un rol'), findsOneWidget);
    });

    testWidgets('si el servidor lo rechaza avisa con su motivo y la persona sigue pendiente', (tester) async {
      writeHandler = (_) => errorResponse(404, code: 'role_not_found');
      await open(tester);
      await toPending(tester);

      await tester.tap(find.text('Asignar rol'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Técnico'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asignar roles'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Uno de los roles ya no existe o está inactivo.'), findsOneWidget);
      expect(find.byType(PendingUserCard), findsOneWidget);
    });
  });

  group('activar y desactivar', () {
    testWidgets('desactivar pide confirmación; cancelar no manda nada', (tester) async {
      await open(tester);
      await openDetail(tester, 'Pedro Gómez');

      await tester.tap(find.text('Desactivar cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('¿Desactivar a Pedro Gómez?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(writes(), isEmpty);
      expect(find.text('Detalle del usuario'), findsOneWidget);
    });

    testWidgets('confirmar desactiva con POST y avisa', (tester) async {
      await open(tester);
      await openDetail(tester, 'Pedro Gómez');

      await tester.tap(find.text('Desactivar cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Desactivar'));
      await tester.pumpAndSettle();

      expect(writes().single.method, 'POST');
      expect(writes().single.path, '/admin/users/4/deactivate');
      expect(find.text('La cuenta de Pedro Gómez fue desactivada.'), findsOneWidget);
      expect(find.text('Detalle del usuario'), findsNothing);
    });

    testWidgets('una cuenta inactiva se activa sin pedir confirmación', (tester) async {
      await open(tester);
      await openDetail(tester, 'Marta Baja');

      expect(find.text('Desactivar cuenta'), findsNothing);
      await tester.tap(find.text('Activar cuenta'));
      await tester.pumpAndSettle();

      expect(writes().single.path, '/admin/users/3/activate');
      expect(find.text('La cuenta de Marta Baja fue activada.'), findsOneWidget);
    });

    testWidgets('si el último administrador está protegido, el motivo sale en la ficha', (tester) async {
      writeHandler = (_) => errorResponse(409, code: 'last_admin_protected');
      await open(tester);
      await openDetail(tester, 'Pedro Gómez');

      await tester.tap(find.text('Desactivar cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Desactivar'));
      await tester.pumpAndSettle();

      expect(inSheet(find.textContaining('administradores activos')), findsOneWidget);
      expect(find.text('Detalle del usuario'), findsOneWidget);
    });

    testWidgets('sin red avisa sin detalles internos', (tester) async {
      writeHandler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red');
      await open(tester);
      await openDetail(tester, 'Pedro Gómez');

      await tester.tap(find.text('Desactivar cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Desactivar'));
      await tester.pumpAndSettle();

      expect(inSheet(find.textContaining('No pudimos conectar')), findsOneWidget);
    });
  });

  group('editar teléfono y código', () {
    Future<void> openContact(WidgetTester tester, String name) async {
      await open(tester);
      await openDetail(tester, name);
      await tester.tap(find.text('Editar teléfono y código'));
      await tester.pumpAndSettle();
    }

    testWidgets('la hoja trae lo que ya tiene y guarda solo lo que cambió', (tester) async {
      await openContact(tester, 'Pedro Gómez');

      expect(find.text('Editar datos de contacto'), findsOneWidget);
      expect(tester.widget<TextField>(phoneField()).controller!.text, '+57 300 123 4567');
      expect(tester.widget<TextField>(codeField()).controller!.text, 'EMP-014');
      await tester.enterText(phoneField(), '  +57   311 000 1111 ');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(writes().single.method, 'PATCH');
      expect(writes().single.path, '/admin/users/4');
      expect(writes().single.data, {'phone': '+57 311 000 1111'}, reason: 'el código no cambió y no viaja');
      expect(find.text('Datos de Pedro Gómez actualizados.'), findsOneWidget);
    });

    testWidgets('vaciar un campo lo borra', (tester) async {
      await openContact(tester, 'Pedro Gómez');

      await tester.enterText(codeField(), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(writes().single.data, {'employee_code': null});
    });

    testWidgets('un teléfono o un código inválidos se explican y no se pueden guardar', (tester) async {
      await openContact(tester, 'Pedro Gómez');

      await tester.enterText(phoneField(), 'abc');
      await tester.pumpAndSettle();
      expect(find.text('El teléfono solo admite números, espacios, +, ( ) y -.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar cambios')).onPressed, isNull);

      await tester.enterText(phoneField(), '+57 300 123 4567');
      await tester.enterText(codeField(), 'x');
      await tester.pumpAndSettle();
      expect(find.text('El código solo admite letras, números, punto, guion y guion bajo (2 a 50).'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar cambios')).onPressed, isNull);
      expect(writes(), isEmpty);
    });

    testWidgets('guardar sin cambios lo dice en la ficha', (tester) async {
      await openContact(tester, 'Pedro Gómez');

      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(writes(), isEmpty);
      expect(inSheet(find.text('No hay cambios que guardar.')), findsOneWidget);
    });

    testWidgets('un código repetido lo explica el servidor', (tester) async {
      writeHandler = (_) => errorResponse(409, code: 'user_employee_code_taken');
      await openContact(tester, 'Pedro Gómez');

      await tester.enterText(codeField(), 'EMP-099');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(inSheet(find.textContaining('Ya existe un usuario con ese código de empleado.')), findsOneWidget);
    });
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('ficha y hojas en ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        await open(tester, size: size, textScale: 1.3);
        // En una pantalla tan pequeña la tarjeta queda abajo: se desplaza la lista hasta verla.
        await tester.ensureVisible(find.widgetWithText(UserCard, 'Pedro Gómez'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(UserCard, 'Pedro Gómez'));
        await tester.pumpAndSettle();
        expect(find.text('Detalle del usuario'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await reveal(tester, find.text('Cambiar roles'));
        await tester.tap(find.text('Cambiar roles'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Se cierra la hoja de roles (la de arriba) sin depender de dónde cae su botón en una pantalla tan pequeña.
        Navigator.of(tester.element(find.text('Roles de Pedro Gómez'))).pop();
        await tester.pumpAndSettle();

        await reveal(tester, find.text('Editar teléfono y código'));
        await tester.tap(find.text('Editar teléfono y código'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.enterText(phoneField(), 'abc');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
