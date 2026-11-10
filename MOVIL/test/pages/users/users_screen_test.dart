import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/users/users_screen.dart';
import 'package:mantix/widgets/shared/filter_widgets.dart';
import 'package:mantix/widgets/users/user_cards.dart';

import '../../support/fakes.dart';
import '../../support/paginator_support.dart';
import '../../support/requests_support.dart';
import '../../support/users_support.dart';

const _viewOnly = {'usuarios:ver'};
const _canAssign = {'usuarios:ver', 'usuarios:asignar'};

/// Lo que el «servidor» devuelve en cada pestaña; cada prueba cambia lo que necesite.
void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) usersHandler;
  late ResponseBody Function(RequestOptions) summaryHandler;
  late ResponseBody Function(RequestOptions) pendingHandler;
  late ResponseBody Function(RequestOptions) rolesHandler;

  List<Object?> people() => [
        userJson(id: 1, name: 'Ana Pérez', roles: [roleJson(), roleJson(id: 1, code: 'ADMIN', name: 'Administrador')]),
        userJson(id: 2, name: 'Luis Nuevo', email: 'luis@mantix.test', roles: const [], lastLogin: null, linked: false),
        userJson(id: 3, name: 'Marta Baja', email: 'marta@mantix.test', active: false),
      ];

  setUp(() {
    usersHandler = (_) => pagedResponse(people());
    summaryHandler = (_) => jsonResponse(200, usersSummaryJson);
    pendingHandler = (_) => jsonResponse(200, [pendingJson()]);
    rolesHandler = (_) => jsonResponse(200, [roleJson(), roleJson(id: 1, code: 'ADMIN', name: 'Administrador')]);
    adapter = FakeAdapter((options) => switch (options.path) {
          '/admin/users/summary' => summaryHandler(options),
          '/admin/users/pending' => pendingHandler(options),
          '/admin/users' => usersHandler(options),
          '/admin/roles' => rolesHandler(options),
          '/admin/roles/manage' => jsonResponse(200, [managedRoleJson(users: 9), managedRoleJson(id: 1, code: 'ADMIN', name: 'Administrador', users: 2)]),
          _ => errorResponse(404),
        });
  });

  Future<void> open(WidgetTester tester, {Set<String> permissions = _viewOnly, Size size = const Size(1000, 2200), double textScale = 1}) async {
    await pumpScreen(tester, const UsersScreen(), adapter, permissions: permissions, size: size, textScale: textScale);
    await tester.pumpAndSettle();
  }

  Future<void> goTo(WidgetTester tester, String tab) async {
    await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text(tab)));
    await tester.pumpAndSettle();
  }

  List<RequestOptions> usersCalls() => adapter.requests.where((r) => r.path == '/admin/users').toList();

  group('encabezado y pestañas', () {
    testWidgets('una sola pantalla con tres pestañas y el número de pendientes', (tester) async {
      await open(tester);

      expect(find.text('USUARIOS Y ROLES'), findsOneWidget);
      for (final tab in ['Usuarios', 'Pendientes', 'Roles']) {
        expect(find.descendant(of: find.byType(TabBar), matching: find.text(tab)), findsOneWidget, reason: tab);
      }
      expect(find.descendant(of: find.byType(TabBar), matching: find.text('1')), findsOneWidget, reason: 'una persona espera un rol');
    });

    testWidgets('sin pendientes la pestaña no lleva número', (tester) async {
      pendingHandler = (_) => jsonResponse(200, <Object?>[]);
      summaryHandler = (_) => jsonResponse(200, {...usersSummaryJson, 'without_role': 0});
      await open(tester);

      expect(find.descendant(of: find.byType(TabBar), matching: find.text('0')), findsNothing);
      expect(find.descendant(of: find.byType(TabBar), matching: find.text('1')), findsNothing);
    });
  });

  group('pestaña Usuarios', () {
    testWidgets('muestra las cifras y cada persona con su correo, roles, estado y último acceso', (tester) async {
      await open(tester);

      for (final value in ['40', '36', '4', '3']) {
        expect(find.text(value), findsWidgets, reason: value);
      }
      for (final label in ['Total', 'Activos', 'Inactivos', 'Sin ingresar']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.byType(UserCard), findsNWidgets(3));
      expect(find.text('Ana Pérez'), findsOneWidget);
      expect(find.text('ana@mantix.test'), findsOneWidget);
      expect(find.text('Técnico'), findsNWidgets(2), reason: 'Ana y Marta');
      expect(find.text('Administrador'), findsOneWidget);
      expect(find.text('Activo'), findsOneWidget);
      expect(find.text('Pendiente de primer ingreso'), findsOneWidget);
      expect(find.text('Inactivo'), findsOneWidget);
      expect(find.text('Sin rol'), findsOneWidget, reason: 'Luis no tiene rol');
      expect(find.text('Último acceso: Nunca'), findsOneWidget);
    });

    testWidgets('la primera carga pide la página 1 de 20, ordenada por nombre', (tester) async {
      await open(tester);

      final query = usersCalls().single.queryParameters;
      expect((query['page'], query['size'], query['sort']), (1, 20, 'name'));
      expect(query.containsKey('search'), isFalse);
      expect(query.containsKey('role'), isFalse);
    });

    testWidgets('con varias páginas muestra el paginador y pide la elegida', (tester) async {
      usersHandler = (o) => pagedResponse(people(), page: o.queryParameters['page'] as int, totalPages: 3, total: 41);
      await open(tester);
      expect(selectedPage(tester), 1);

      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();

      expect(usersCalls().last.queryParameters['page'], 2);
      expect(selectedPage(tester), 2);
      expect(find.byTooltip('Página anterior'), findsOneWidget);
    });

    testWidgets('la búsqueda espera a que se deje de escribir y pide el término recortado', (tester) async {
      await open(tester);
      final before = usersCalls().length;

      await tester.enterText(find.byType(TextField), '  ana ');
      await tester.pump(const Duration(milliseconds: 100));
      expect(usersCalls().length, before, reason: 'todavía espera');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(usersCalls().length, before + 1);
      expect(usersCalls().last.queryParameters['search'], 'ana');
      expect(find.byTooltip('Borrar búsqueda'), findsOneWidget);

      await tester.tap(find.byTooltip('Borrar búsqueda'));
      await tester.pumpAndSettle();
      expect(usersCalls().last.queryParameters.containsKey('search'), isFalse);
    });

    testWidgets('los filtros de rol y estado se aplican y salen como chips que se quitan', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todos los roles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Técnico').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactivas').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      final query = usersCalls().last.queryParameters;
      expect(query['role'], 'TECHNICIAN');
      expect(query['is_active'], false);
      expect(query['page'], 1);
      expect(find.byTooltip('Filtros (2 activos)'), findsOneWidget);
      expect(find.byType(ActiveFilterChip), findsNWidgets(2));

      await tester.tap(find.byTooltip('Quitar filtro').first);
      await tester.pumpAndSettle();
      expect(usersCalls().last.queryParameters.containsKey('role'), isFalse);
      expect(usersCalls().last.queryParameters['is_active'], false);
    });

    testWidgets('cerrar la hoja de filtros sin aplicar no cambia nada', (tester) async {
      await open(tester);
      final before = usersCalls().length;

      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activas').last);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(usersCalls().length, before);
      expect(find.byTooltip('Filtros'), findsOneWidget);
    });

    testWidgets('sin resultados con filtros ofrece quitarlos; sin filtros dice que aún no hay usuarios', (tester) async {
      usersHandler = (_) => pagedResponse(<Object?>[]);
      await open(tester);
      expect(find.text('Aún no hay usuarios'), findsOneWidget);
      expect(find.text('Quitar filtros'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Ningún usuario coincide con los filtros'), findsOneWidget);

      usersHandler = (_) => pagedResponse(people());
      await tester.tap(find.text('Quitar filtros'));
      await tester.pumpAndSettle();
      expect(find.byType(UserCard), findsNWidgets(3));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('si la lista falla muestra el motivo y reintenta; las cifras siguen', (tester) async {
      usersHandler = (_) => errorResponse(500);
      await open(tester);

      expect(find.text('No pudimos cargar los usuarios'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);

      usersHandler = (_) => pagedResponse(people());
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(UserCard), findsNWidgets(3));
    });

    testWidgets('si las cifras fallan dicen «no disponibles» con reintento y la lista sigue', (tester) async {
      summaryHandler = (_) => errorResponse(500);
      await open(tester);

      expect(find.text('Las cifras de las cuentas no están disponibles.'), findsOneWidget);
      expect(find.byType(UserCard), findsNWidgets(3));

      summaryHandler = (_) => jsonResponse(200, usersSummaryJson);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Sin ingresar'), findsOneWidget);
    });
  });

  group('pestaña Pendientes', () {
    testWidgets('lista a quienes esperan un rol, con la explicación', (tester) async {
      pendingHandler = (_) => jsonResponse(200, [pendingJson(), pendingJson(id: 8, name: 'Marta Nueva', email: 'mn@mantix.test')]);
      await open(tester);
      await goTo(tester, 'Pendientes');

      expect(find.byType(PendingUserCard), findsNWidgets(2));
      expect(find.text('Luis Nuevo'), findsOneWidget);
      expect(find.text('luis@mantix.test'), findsOneWidget);
      expect(find.text('Sin rol'), findsNWidgets(2));
      expect(find.textContaining('no pueden usar Mantix hasta que les asignes un rol'), findsOneWidget);
    });

    testWidgets('sin pendientes lo dice', (tester) async {
      pendingHandler = (_) => jsonResponse(200, <Object?>[]);
      await open(tester);
      await goTo(tester, 'Pendientes');

      expect(find.text('No hay nadie esperando un rol'), findsOneWidget);
    });

    testWidgets('si falla muestra el motivo y reintenta', (tester) async {
      pendingHandler = (_) => errorResponse(500);
      await open(tester);
      await goTo(tester, 'Pendientes');
      expect(find.text('No pudimos cargar los pendientes'), findsOneWidget);

      pendingHandler = (_) => jsonResponse(200, [pendingJson()]);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(PendingUserCard), findsOneWidget);
    });
  });

  group('pestaña Roles', () {
    testWidgets('con solo «ver» muestra nombre, código y cuántas personas, sin descripción', (tester) async {
      await open(tester, permissions: _viewOnly);
      await goTo(tester, 'Roles');

      expect(find.byType(RoleCard), findsNWidgets(2));
      expect(find.text('TECHNICIAN'), findsOneWidget);
      expect(find.text('9 personas'), findsOneWidget);
      expect(find.text('2 personas'), findsOneWidget);
      expect(find.text('Atiende tickets asignados'), findsNothing);
      expect(adapter.requests.any((r) => r.path == '/admin/roles/manage'), isFalse);
      expect(find.textContaining('usa la versión web'), findsOneWidget);
    });

    testWidgets('con permiso de asignar añade la descripción de cada rol', (tester) async {
      await open(tester, permissions: _canAssign);
      await goTo(tester, 'Roles');

      expect(adapter.requests.any((r) => r.path == '/admin/roles/manage'), isTrue);
      expect(find.text('Atiende tickets asignados'), findsNWidgets(2));
    });

    testWidgets('solo lectura: no hay botones para crear, editar ni borrar roles', (tester) async {
      await open(tester, permissions: _canAssign);
      await goTo(tester, 'Roles');

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(find.textContaining('matriz'), findsNothing);
    });

    testWidgets('si falla muestra el motivo y reintenta', (tester) async {
      rolesHandler = (_) => errorResponse(403, code: 'forbidden');
      await open(tester);
      await goTo(tester, 'Roles');

      expect(find.text('No pudimos cargar los roles'), findsOneWidget);
      expect(find.textContaining('No tienes permiso'), findsOneWidget);
    });
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('las tres pestañas en ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        pendingHandler = (_) => jsonResponse(200, [pendingJson(name: 'Una persona con un nombre muy largo que no cabe en una línea', email: 'un.correo.muy.largo.de.prueba@una-empresa-con-dominio-largo.com')]);
        usersHandler = (_) => pagedResponse(people(), totalPages: 99, total: 990);
        await open(tester, permissions: _canAssign, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);

        await goTo(tester, 'Pendientes');
        expect(tester.takeException(), isNull);
        await goTo(tester, 'Roles');
        expect(tester.takeException(), isNull);
        await goTo(tester, 'Usuarios');
        expect(tester.takeException(), isNull);
      });

      testWidgets('con el resumen caído, la lista fallida y filtros puestos en ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        summaryHandler = (_) => errorResponse(500);
        usersHandler = (_) => errorResponse(500);
        await open(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
