import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/bloc/notifications/notifications_bloc.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/pages/equipment/equipment_screen.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';
import 'package:mantix/services/device_services.dart';
import 'package:mantix/widgets/equipment/equipment_list_views.dart';

import '../../models/equipment/equipment_models_test.dart' show equipmentItemJson;
import '../../support/device_fakes.dart';
import '../../support/fakes.dart';
import '../../support/header_support.dart';
import '../../support/requests_support.dart';

const _summaryJson = {
  'total': 38,
  'by_status': {'assigned': 20, 'in_storage': 11, 'in_repair': 3, 'lost': 1, 'retired': 2, 'disposed': 1},
};

const _typesJson = [
  {'id': 1, 'code': 'LAPTOP', 'name': 'Laptop'},
  {'id': 2, 'code': 'PRINTER', 'name': 'Impresora'},
];

final _laptop = equipmentItemJson();
final _printer = equipmentItemJson(overrides: {
  'id': 8,
  'asset_tag': 'DEMO-008',
  'brand': 'HP',
  'model': 'LaserJet Pro',
  'status': 'in_repair',
  'description': null,
  'serial_number': null,
  'equipment_type': {'id': 2, 'code': 'PRINTER', 'name': 'Impresora'},
  'current_location': null,
  'current_custodian': null,
  'last_maintenance': null,
});

void main() {
  late MockAuthBloc authBloc;
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) listHandler;
  late ResponseBody Function(RequestOptions) summaryHandler;

  setUp(() {
    authBloc = MockAuthBloc();
    listHandler = (_) => pagedResponse([_laptop, _printer]);
    summaryHandler = (_) => jsonResponse(200, _summaryJson);
    adapter = FakeAdapter((options) => switch (options.path) {
          '/equipment/summary' => summaryHandler(options),
          '/equipment/types' => jsonResponse(200, _typesJson),
          '/locations' => jsonResponse(200, []),
          _ => listHandler(options),
        });
  });

  Future<void> pumpScreen(WidgetTester tester, {double textScale = 1, Set<String> permissions = const {'equipos:ver', 'equipos:crear'}, DeviceServices? device}) async {
    tester.view.physicalSize = const Size(390, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    whenListen(authBloc, const Stream<AuthState>.empty(), initialState: Authenticated(testProfile(permissions: permissions)));
    await tester.pumpWidget(
      RepositoryProvider<DeviceServices>.value(
        value: device ?? fakeDevice(),
        child: RepositoryProvider<EquipmentRepository>.value(
        value: EquipmentRepository(dioWith(adapter)),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: authBloc),
            BlocProvider<NotificationsBloc>.value(value: notificationsBloc()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, app) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: app!,
            ),
            home: const EquipmentScreen(),
          ),
        ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<RequestOptions> listRequests() => adapter.requests.where((r) => r.path == '/equipment').toList();
  Map<String, dynamic> lastQuery() => listRequests().last.queryParameters;

  /// Responde como un servidor con [total] equipos repartidos en páginas del tamaño pedido.
  ResponseBody pagedByQuery(RequestOptions options, {int total = 25}) {
    final page = options.queryParameters['page'] as int;
    final size = options.queryParameters['size'] as int;
    final start = (page - 1) * size;
    final count = (total - start).clamp(0, size);
    final items = [for (var i = 0; i < count; i++) equipmentItemJson(overrides: {'id': start + i + 1, 'asset_tag': 'EQ-${start + i + 1}'})];
    return pagedResponse(items, page: page, total: total, totalPages: (total / size).ceil());
  }

  testWidgets('muestra el título, la descripción y los cuatro contadores', (tester) async {
    await pumpScreen(tester);

    expect(find.text('GESTIÓN DE EQUIPOS'), findsOneWidget);
    expect(find.textContaining('Administra los equipos tecnológicos'), findsOneWidget);
    for (final value in ['38', '31', '3', '4']) {
      expect(find.text(value), findsOneWidget, reason: value);
    }
    for (final badge in ['Total', '81,6% tasa', 'En curso', 'Crítico']) {
      expect(find.text(badge), findsOneWidget, reason: badge);
    }
  });

  testWidgets('la tabla muestra cada equipo con su descripción o serie, etiqueta, ubicación y estado', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(EquipmentTable), findsOneWidget);
    expect(find.text('EQUIPO Y MODELO'), findsOneWidget);
    expect(find.text('ESTADO'), findsOneWidget);
    expect(find.text('Dell Latitude 5420'), findsOneWidget);
    expect(find.text('Equipo de demostración'), findsOneWidget);
    expect(find.text('DEMO-007'), findsOneWidget);
    expect(find.text('Sede central'), findsOneWidget);
    expect(find.text('Asignado'), findsOneWidget);

    expect(find.text('HP LaserJet Pro'), findsOneWidget);
    expect(find.text('Serie: sin registrar'), findsOneWidget);
    expect(find.text('Sin ubicación'), findsOneWidget);
    expect(find.text('En mantenimiento'), findsOneWidget);
  });

  testWidgets('se puede cambiar entre tabla y cuadrícula', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Cuadrícula'));
    await tester.pumpAndSettle();
    expect(find.byType(EquipmentGrid), findsOneWidget);
    expect(find.byType(EquipmentTable), findsNothing);
    expect(find.text('Dell Latitude 5420'), findsOneWidget);
    expect(find.text('HP LaserJet Pro'), findsOneWidget);

    await tester.tap(find.text('Tabla'));
    await tester.pumpAndSettle();
    expect(find.byType(EquipmentTable), findsOneWidget);
    expect(find.byType(EquipmentGrid), findsNothing);
    expect(adapter.requests.where((r) => r.path == '/equipment'), hasLength(1), reason: 'cambiar de vista no vuelve a pedir datos');
  });

  testWidgets('la primera carga pide la página 1 de diez sin filtros', (tester) async {
    await pumpScreen(tester);

    expect(lastQuery(), {'page': 1, 'size': 10, 'sort': '-created_at'});
  });

  testWidgets('tocar una tarjeta filtra por sus estados y el desplegable lo refleja', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Filtrar operativos'));
    await tester.pumpAndSettle();
    expect(lastQuery()['status'], 'assigned,in_storage');
    expect(find.text('Varios estados'), findsOneWidget);

    await tester.tap(find.text('Ver equipos en mantenimiento'));
    await tester.pumpAndSettle();
    expect(lastQuery()['status'], 'in_repair');

    await tester.tap(find.text('Revisar estos equipos'));
    await tester.pumpAndSettle();
    expect(lastQuery()['status'], 'lost,retired,disposed');

    await tester.tap(find.text('Ver todo'));
    await tester.pumpAndSettle();
    expect(lastQuery().keys, isNot(contains('status')));
  });

  testWidgets('el desplegable de estado filtra por un estado', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('En mantenimiento').last);
    await tester.pumpAndSettle();

    expect(lastQuery()['status'], 'in_repair');
  });

  testWidgets('el desplegable de categoría filtra por categoría', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byType(DropdownButton<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Impresora').last);
    await tester.pumpAndSettle();

    expect(lastQuery()['equipment_type_id'], 2);
  });

  testWidgets('filtrar vuelve a la página 1 y no vuelve a pedir los contadores', (tester) async {
    listHandler = (options) => pagedByQuery(options);
    await pumpScreen(tester);
    await tester.tap(find.descendant(of: find.byType(EquipmentPagination), matching: find.text('2')));
    await tester.pumpAndSettle();
    expect(lastQuery()['page'], 2);

    await tester.tap(find.text('Filtrar operativos'));
    await tester.pumpAndSettle();

    expect(lastQuery()['page'], 1);
    expect(adapter.requests.where((r) => r.path == '/equipment/summary'), hasLength(1));
  });

  testWidgets('«Limpiar filtros» quita la búsqueda, la categoría y el estado', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'dell');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filtrar operativos'));
    await tester.pumpAndSettle();
    expect(lastQuery()['status'], 'assigned,in_storage');
    expect(lastQuery()['search'], 'dell');

    await tester.tap(find.byTooltip('Limpiar filtros'));
    await tester.pumpAndSettle();

    expect(lastQuery().keys, isNot(contains('status')));
    expect(lastQuery().keys, isNot(contains('search')));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('la búsqueda espera a que dejes de escribir y conserva el texto y el foco', (tester) async {
    await pumpScreen(tester);
    final before = listRequests().length;

    await tester.enterText(find.byType(TextField), '  dell ');
    await tester.pump(const Duration(milliseconds: 100));
    expect(listRequests(), hasLength(before), reason: 'todavía no ha pasado la espera');

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(lastQuery()['search'], 'dell');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '  dell ');
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
  });

  group('paginación', () {
    testWidgets('muestra el rango, el total y los botones de página', (tester) async {
      listHandler = (options) => pagedByQuery(options);
      await pumpScreen(tester);

      expect(find.text('Mostrando 1 – 10 de 25 equipos'), findsOneWidget);
      expect(find.text('10 por página'), findsOneWidget);
      expect(find.byTooltip('Página anterior'), findsOneWidget);
      expect(find.byTooltip('Página siguiente'), findsOneWidget);
    });

    testWidgets('ir a otra página la pide y actualiza el rango', (tester) async {
      listHandler = (options) => pagedByQuery(options);
      await pumpScreen(tester);

      await tester.tap(find.descendant(of: find.byType(EquipmentPagination), matching: find.text('2')));
      await tester.pumpAndSettle();

      expect(lastQuery()['page'], 2);
      expect(find.text('Mostrando 11 – 20 de 25 equipos'), findsOneWidget);
      expect(find.text('EQ-11'), findsOneWidget);

      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      expect(lastQuery()['page'], 3);
      expect(find.text('Mostrando 21 – 25 de 25 equipos'), findsOneWidget);
    });

    testWidgets('en la primera página no se puede retroceder y en la última no se puede avanzar', (tester) async {
      listHandler = (options) => pagedByQuery(options);
      await pumpScreen(tester);
      final requests = listRequests().length;

      await tester.tap(find.byTooltip('Página anterior'));
      await tester.pumpAndSettle();
      expect(listRequests(), hasLength(requests));

      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      final onLast = listRequests().length;
      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      expect(listRequests(), hasLength(onLast));
    });

    testWidgets('cambiar el tamaño de página vuelve a la página 1', (tester) async {
      listHandler = (options) => pagedByQuery(options);
      await pumpScreen(tester);
      await tester.tap(find.descendant(of: find.byType(EquipmentPagination), matching: find.text('2')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('10 por página'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20 por página').last);
      await tester.pumpAndSettle();

      expect(lastQuery()['size'], 20);
      expect(lastQuery()['page'], 1);
      expect(find.text('Mostrando 1 – 20 de 25 equipos'), findsOneWidget);
    });

    test('pageButtons muestra la primera, la última y las vecinas con huecos', () {
      expect(pageButtons(1, 3), [1, 2, 3]);
      expect(pageButtons(1, 10), [1, 2, null, 10]);
      expect(pageButtons(5, 10), [1, null, 4, 5, 6, null, 10]);
      expect(pageButtons(10, 10), [1, null, 9, 10]);
      expect(pageButtons(1, 1), [1]);
    });
  });

  testWidgets('tocar un equipo abre su ficha', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Dell Latitude 5420'));
    await tester.pumpAndSettle();

    expect(find.text('Código de activo'), findsOneWidget);
    expect(find.text('Responsable'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('Último mantenimiento'), findsOneWidget);
    expect(find.textContaining('20 oct 2026'), findsOneWidget);
  });

  testWidgets('sin resultados muestra el vacío filtrado y permite volver a todo el catálogo', (tester) async {
    listHandler = (options) => pagedResponse(options.queryParameters.containsKey('search') ? [] : [_laptop]);
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Ningún equipo coincide con los filtros'), findsOneWidget);
    expect(find.text('GESTIÓN DE EQUIPOS'), findsOneWidget, reason: 'el encabezado sigue visible');

    await tester.tap(find.text('Ver todo el catálogo'));
    await tester.pumpAndSettle();

    expect(find.text('Dell Latitude 5420'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('sin ningún equipo registrado lo dice', (tester) async {
    listHandler = (_) => pagedResponse([]);
    await pumpScreen(tester);

    expect(find.text('Aún no hay equipos registrados'), findsOneWidget);
    expect(find.text('Ver todo el catálogo'), findsNothing);
  });

  testWidgets('si el listado falla muestra el error con reintento y el encabezado', (tester) async {
    listHandler = (_) => errorResponse(500);
    await pumpScreen(tester);

    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('GESTIÓN DE EQUIPOS'), findsOneWidget);
    expect(find.textContaining('detalle interno'), findsNothing);

    listHandler = (_) => pagedResponse([_laptop]);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Dell Latitude 5420'), findsOneWidget);
  });

  testWidgets('si los contadores fallan se muestran con guion y se pueden reintentar', (tester) async {
    summaryHandler = (_) => errorResponse(500);
    await pumpScreen(tester);

    expect(find.text('–'), findsNWidgets(4));
    expect(find.textContaining('No pudimos cargar los contadores'), findsOneWidget);
    expect(find.text('Dell Latitude 5420'), findsOneWidget, reason: 'el listado no depende de los contadores');

    summaryHandler = (_) => jsonResponse(200, _summaryJson);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('38'), findsOneWidget);
  });

  testWidgets('con el permiso equipos:crear aparece «Nuevo equipo»', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Nuevo equipo'), findsOneWidget);
  });

  testWidgets('sin el permiso equipos:crear no aparece «Nuevo equipo»', (tester) async {
    await pumpScreen(tester, permissions: const {'equipos:ver'});

    expect(find.text('Nuevo equipo'), findsNothing);
    expect(find.text('GESTIÓN DE EQUIPOS'), findsOneWidget);
  });

  testWidgets('el menú lateral ofrece Equipos con el permiso equipos:ver', (tester) async {
    await pumpScreen(tester);

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Equipos'), findsOneWidget);
  });

  testWidgets('con la fuente del sistema más grande no se desborda', (tester) async {
    listHandler = (options) => pagedByQuery(options);
    await pumpScreen(tester, textScale: 1.3);

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cuadrícula'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
