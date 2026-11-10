import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/bloc/notifications/notifications_bloc.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/core/theme/app_colors.dart';
import 'package:mantix/models/equipment/equipment_models.dart';
import 'package:mantix/pages/equipment/equipment_screen.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';
import 'package:mantix/services/device_services.dart';
import 'package:mantix/widgets/equipment/equipment_list_views.dart';
import 'package:mantix/widgets/shared/filter_widgets.dart';

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

bool createdOnce = false;

void main() {
  late MockAuthBloc authBloc;
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) listHandler;
  late ResponseBody Function(RequestOptions) summaryHandler;
  late EquipmentRepository repository;

  setUp(() {
    createdOnce = false;
    authBloc = MockAuthBloc();
    listHandler = (_) => pagedResponse([_laptop, _printer]);
    summaryHandler = (_) => jsonResponse(200, _summaryJson);
    adapter = FakeAdapter((options) => switch (options.path) {
          '/equipment' when options.method == 'POST' => jsonResponse(201, equipmentItemJson(overrides: {'id': 99, 'asset_tag': 'EQ-NEW', 'brand': 'Nuevo', 'model': 'Recién creado'})),
          '/maintenance/requests' => pagedResponse([ticketJson(id: 1, title: 'Pantalla rota')]),
          final path when path.endsWith('/attachments') => jsonResponse(200, [
              {'id': 5, 'file_name': 'factura.pdf', 'mime_type': 'application/pdf', 'file_size': 2048},
            ]),
          '/equipment/summary' => summaryHandler(options),
          '/equipment/types' => jsonResponse(200, _typesJson),
          '/locations' => jsonResponse(200, []),
          _ => listHandler(options),
        });
  });

  Future<void> pumpScreen(WidgetTester tester, {double textScale = 1, Set<String> permissions = const {'equipos:ver', 'equipos:crear'}, DeviceServices? device, Size size = const Size(390, 3600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    whenListen(authBloc, const Stream<AuthState>.empty(), initialState: Authenticated(testProfile(permissions: permissions)));
    await tester.pumpWidget(
      RepositoryProvider<DeviceServices>.value(
        value: device ?? fakeDevice(),
        child: RepositoryProvider<RequestsRepository>.value(
        value: RequestsRepository(dioWith(adapter)),
        child: RepositoryProvider<EquipmentRepository>.value(
        value: repository = EquipmentRepository(dioWith(adapter)),
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
    expect(find.text('EQUIPO Y MODELO · ESTADO'), findsOneWidget);
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

  testWidgets('tocar una tarjeta filtra por sus estados y el botón de filtros cuenta los activos', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Filtrar operativos'));
    await tester.pumpAndSettle();
    expect(lastQuery()['status'], 'assigned,in_storage');
    expect(find.byTooltip('Filtros (2 activos)'), findsOneWidget);

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

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Filtros'));
    await tester.pumpAndSettle();
  }

  testWidgets('la multiselección de estado filtra por varios estados sin cerrarse al marcar', (tester) async {
    await pumpScreen(tester);

    await openFilters(tester);
    await tester.tap(find.byType(FilterTile).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('En mantenimiento').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extraviado').last);
    await tester.pumpAndSettle();
    expect(find.text('2 activos'), findsOneWidget, reason: 'la hoja sigue abierta tras marcar');
    await tester.tap(find.text('Aplicar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(lastQuery()['status'], 'in_repair,lost');
    expect(find.byTooltip('Filtros (2 activos)'), findsOneWidget);
  });

  testWidgets('la multiselección de categoría repite el parámetro por cada categoría', (tester) async {
    await pumpScreen(tester);

    await openFilters(tester);
    await tester.tap(find.byType(FilterTile).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laptop').last);
    await tester.tap(find.text('Impresora').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(lastQuery()['equipment_type_id'], [1, 2]);
  });

  testWidgets('las fechas se envían como date_from y date_to y se quitan con su chip', (tester) async {
    await pumpScreen(tester);

    await openFilters(tester);
    await tester.tap(find.text('Cualquier fecha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(lastQuery().keys, containsAll(['date_from', 'date_to']));
    await tester.tap(find.byTooltip('Quitar filtro'));
    await tester.pumpAndSettle();
    expect(lastQuery().keys, isNot(contains('date_from')));
  });

  testWidgets('al filtrar, el listado muestra lo que devuelve el servidor para el filtro nuevo', (tester) async {
    listHandler = (options) => options.queryParameters.containsKey('status') ? pagedResponse([_printer]) : pagedResponse([_laptop]);
    await pumpScreen(tester);
    expect(find.text('Dell Latitude 5420'), findsOneWidget);

    await tester.tap(find.text('Ver equipos en mantenimiento'));
    await tester.pumpAndSettle();

    expect(find.text('HP LaserJet Pro'), findsOneWidget);
    expect(find.text('Dell Latitude 5420'), findsNothing);
  });

  testWidgets('filtrar vuelve a la página 1 y no vuelve a pedir los contadores', (tester) async {
    listHandler = (options) => pagedByQuery(options);
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(lastQuery()['page'], 2);

    await tester.tap(find.text('Filtrar operativos'));
    await tester.pumpAndSettle();

    expect(lastQuery()['page'], 1);
    expect(adapter.requests.where((r) => r.path == '/equipment/summary'), hasLength(1));
  });

  testWidgets('«Limpiar» en la hoja quita categorías, estados y fechas al aplicar', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Filtrar operativos'));
    await tester.pumpAndSettle();
    expect(lastQuery()['status'], 'assigned,in_storage');

    await tester.tap(find.byTooltip('Filtros (2 activos)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpiar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(lastQuery().keys, isNot(contains('status')));
    expect(find.byTooltip('Filtros'), findsOneWidget);
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

      expect(find.text('1-10 de 25'), findsOneWidget);
      expect(find.byType(DropdownButton<int>), findsOneWidget);
      expect(find.byTooltip('Página anterior'), findsNothing, reason: 'en la página 1 no hay «anterior»');
      expect(find.byTooltip('Página siguiente'), findsOneWidget);
    });

    testWidgets('ir a otra página la pide y actualiza el rango', (tester) async {
      listHandler = (options) => pagedByQuery(options);
      await pumpScreen(tester);

      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();

      expect(lastQuery()['page'], 2);
      expect(find.text('11-20 de 25'), findsOneWidget);
      expect(find.text('EQ-11'), findsOneWidget);

      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      expect(lastQuery()['page'], 3);
      expect(find.text('21-25 de 25'), findsOneWidget);
    });

    testWidgets('en la primera página no hay «anterior» y en la última no hay «siguiente»', (tester) async {
      listHandler = (options) => pagedByQuery(options);
      await pumpScreen(tester);
      expect(find.byTooltip('Página anterior'), findsNothing);

      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Página anterior'), findsOneWidget);
      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('21-25 de 25'), findsOneWidget);
      expect(find.byTooltip('Página siguiente'), findsNothing, reason: 'en la última no hay «siguiente»');
    });

    testWidgets('conserva diez equipos por página y el selector vuelve a la página 1 con el tamaño nuevo', (tester) async {
      listHandler = (options) => pagedByQuery(options);
      await pumpScreen(tester);

      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();

      expect(lastQuery()['size'], 10);
      expect(lastQuery()['page'], 2);
      expect(find.text('11-20 de 25'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 por página').last);
      await tester.pumpAndSettle();
      expect(lastQuery()['size'], 5);
      expect(lastQuery()['page'], 1);
    });
  });

  testWidgets('tocar un equipo abre su ficha en una hoja con secciones, historial y adjuntos', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Dell Latitude 5420'));
    await tester.pumpAndSettle();

    expect(find.text('Detalle del equipo'), findsOneWidget);
    expect(find.text('Código de activo'), findsOneWidget);
    expect(find.text('Responsable'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('Último mantenimiento'), findsWidgets);
    expect(find.textContaining('20 oct 2026'), findsWidgets);
    expect(find.text('GESTIÓN DE EQUIPOS'), findsOneWidget, reason: 'la pantalla de fondo sigue visible');
    // Historial: el registro del equipo y sus tickets.
    await tester.scrollUntilVisible(find.text('Equipo registrado'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Equipo registrado'), findsOneWidget);
    expect(find.text('Ticket TCK-0001 creado'), findsOneWidget);
    expect(find.text('Pantalla rota · Enviado'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('factura.pdf'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('factura.pdf'), findsOneWidget);
    expect(adapter.requests.any((r) => r.path == '/maintenance/requests' && r.queryParameters['equipment_id'] == 7), isTrue);
  });

  testWidgets('la etiqueta «Último mantenimiento» no se superpone con su valor', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Dell Latitude 5420'));
    await tester.pumpAndSettle();

    final label = tester.getRect(find.text('Último mantenimiento').first);
    final value = tester.getRect(find.textContaining('20 oct 2026').first);
    expect(label.overlaps(value), isFalse);
    expect(value.top, greaterThanOrEqualTo(label.bottom - 1), reason: 'el valor va debajo de la etiqueta');
  });

  group('equipo recién creado', () {
    testWidgets('vuelve a la página 1, sale primero y se resalta unos segundos', (tester) async {
      listHandler = (options) {
        final page = options.queryParameters['page'] as int;
        final created = createdOnce;
        return pagedResponse([if (page == 1 && created) equipmentItemJson(overrides: {'id': 99, 'asset_tag': 'EQ-NEW', 'brand': 'Nuevo', 'model': 'Recién creado'}), _laptop], page: page, total: 25, totalPages: 3);
      };
      await pumpScreen(tester);
      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      expect(lastQuery()['page'], 2);

      createdOnce = true;
      unawaited(repository.create(const NewEquipment(assetTag: 'EQ-NEW', typeId: 1, brand: 'Nuevo', model: 'Recién creado')));
      await tester.pumpAndSettle();

      expect(lastQuery()['page'], 1);
      expect(lastQuery()['sort'], '-created_at');
      final first = tester.getTopLeft(find.text('Nuevo Recién creado')).dy;
      expect(first, lessThan(tester.getTopLeft(find.text('Dell Latitude 5420')).dy), reason: 'aparece primero');
      Finder highlighted() => find.byWidgetPredicate((w) => w is AnimatedContainer && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == AppColors.mustard.withValues(alpha: .28));
      expect(highlighted(), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(highlighted(), findsNothing);
    });

    testWidgets('limpia los filtros para que el equipo nuevo se vea', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Filtrar operativos'));
      await tester.pumpAndSettle();
      expect(lastQuery()['status'], 'assigned,in_storage');

      unawaited(repository.create(const NewEquipment(assetTag: 'EQ-NEW', typeId: 1, brand: 'Nuevo', model: 'Recién creado')));
      await tester.pumpAndSettle();
      expect(lastQuery().keys, isNot(contains('status')));
      await tester.pump(const Duration(seconds: 5));
    });
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

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 120, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      final name = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('la pantalla, tabla y cuadrícula en $name', (tester) async {
        listHandler = (options) => pagedByQuery(options);
        await pumpScreen(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);
        await tapVisible(tester, find.text('Cuadrícula'));
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('la ficha del equipo en $name', (tester) async {
        await pumpScreen(tester, size: size, textScale: 1.3);
        await tapVisible(tester, find.text('Dell Latitude 5420'));
        expect(find.text('Detalle del equipo'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('factura.pdf'), 200, scrollable: find.byType(Scrollable).last);
        expect(tester.takeException(), isNull);
      });

      testWidgets('la hoja de filtros con filtros activos en $name', (tester) async {
        await pumpScreen(tester, size: size, textScale: 1.3);
        await tapVisible(tester, find.text('Filtrar operativos'));
        await tapVisible(tester, find.byTooltip('Filtros (2 activos)'));
        expect(find.text('Limpiar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
