import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mantix/bloc/auth/auth_bloc.dart';
import 'package:mantix/bloc/notifications/notifications_bloc.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/pages/equipment/create_equipment_screen.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';

import '../../models/equipment/equipment_models_test.dart' show equipmentItemJson;
import '../../support/fakes.dart';
import '../../support/header_support.dart';
import '../../support/requests_support.dart';

const _types = [
  {'id': 1, 'code': 'LAPTOP', 'name': 'Laptop'},
  {'id': 2, 'code': 'PRINTER', 'name': 'Impresora'},
];

const _locations = [
  {'id': 3, 'code': 'HQ', 'name': 'Sede central', 'kind': 'site', 'parent_id': null},
  {'id': 4, 'code': 'WH', 'name': 'Almacén norte', 'kind': 'site', 'parent_id': null},
];

const _people = [
  {'id': 9, 'full_name': 'Ana Pérez', 'email': 'ana@mantix.test'},
  {'id': 10, 'full_name': 'Luis Gómez', 'email': 'luis@mantix.test'},
];

const _all = {'equipos:ver', 'equipos:crear', 'equipos:editar', 'equipos:asignar'};

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) typesHandler;
  late ResponseBody Function(RequestOptions) createHandler;
  late ResponseBody Function(RequestOptions) locationHandler;
  late ResponseBody Function(RequestOptions) custodyHandler;
  late EquipmentRepository repository;
  late GoRouter router;

  setUp(() {
    typesHandler = (_) => jsonResponse(200, _types);
    createHandler = (_) => jsonResponse(201, equipmentItemJson(overrides: {'id': 7}));
    locationHandler = (_) => jsonResponse(200, equipmentItemJson(overrides: {'id': 7}));
    custodyHandler = (_) => jsonResponse(200, equipmentItemJson(overrides: {'id': 7}));
    adapter = FakeAdapter((options) => switch ((options.method, options.path)) {
          ('POST', '/equipment') => createHandler(options),
          ('POST', '/equipment/7/location') => locationHandler(options),
          ('POST', '/equipment/7/custody') => custodyHandler(options),
          ('GET', '/equipment/types') => typesHandler(options),
          ('GET', '/locations') => jsonResponse(200, _locations),
          ('GET', '/equipment/custodian-candidates') => jsonResponse(200, _people),
          _ => jsonResponse(404, {}),
        });
    repository = EquipmentRepository(dioWith(adapter));
  });

  Future<void> pumpForm(WidgetTester tester, {double textScale = 1, Set<String> permissions = _all}) async {
    tester.view.physicalSize = const Size(390, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(path: '/inicio', builder: (_, _) => const Scaffold(body: Text('pantalla de equipos'))),
        GoRoute(path: CreateEquipmentScreen.path, builder: (_, _) => const CreateEquipmentScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RepositoryProvider<EquipmentRepository>.value(
        value: repository,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: authenticatedBloc(testProfile(permissions: permissions))),
            BlocProvider<NotificationsBloc>.value(value: notificationsBloc()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
            builder: (context, app) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: app!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push(CreateEquipmentScreen.path);
    await tester.pumpAndSettle();
  }

  List<RequestOptions> posts() => adapter.requests.where((r) => r.method == 'POST').toList();

  Finder key(String name) => find.byKey(Key('field-$name'));

  Future<void> pick(WidgetTester tester, Finder dropdown, String option) async {
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(key('asset-tag'), '  EQ-029 ');
    await tester.enterText(key('brand'), 'Dell');
    await tester.enterText(key('model'), 'Latitude 5540');
    await pick(tester, find.byType(DropdownButtonFormField<int>), 'Laptop');
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('GUARDAR EQUIPO'));
    await tester.tap(find.text('GUARDAR EQUIPO'));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el panel con sus secciones y campos', (tester) async {
    await pumpForm(tester);

    expect(find.text('Registrar nuevo equipo'), findsOneWidget);
    expect(find.text('Completa la ficha técnica, ubicación y estado del dispositivo.'), findsOneWidget);
    for (final section in ['INFORMACIÓN GENERAL', 'ASIGNACIÓN Y UBICACIÓN', 'ESTADO Y GARANTÍA']) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
    expect(find.textContaining('Campos requeridos'), findsOneWidget);
    for (final name in ['asset-tag', 'brand', 'model', 'serial', 'description', 'cost', 'status']) {
      expect(key(name), findsOneWidget, reason: name);
    }
    for (final label in ['Código de activo', 'Categoría', 'Marca', 'Modelo', 'Número de serie (SN)', 'Descripción y especificaciones técnicas', 'Ubicación física o área', 'Responsable asignado / custodio', 'Estado', 'Costo de adquisición', 'Fecha de adquisición', 'Garantía desde', 'Garantía hasta']) {
      expect(find.textContaining(label, findRichText: true), findsWidgets, reason: label);
    }
    expect(find.text('Sin ubicación por ahora'), findsOneWidget);
    expect(find.text('Seleccionar categoría'), findsOneWidget);
    expect(find.text('GUARDAR EQUIPO'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('El equipo se integra de inmediato al inventario.'), findsOneWidget);
  });

  testWidgets('carga categorías y ubicaciones', (tester) async {
    await pumpForm(tester);

    expect(adapter.requests.where((r) => r.path == '/equipment/types'), hasLength(1));
    expect(adapter.requests.where((r) => r.path == '/locations'), hasLength(1));
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Impresora'), findsOneWidget);
  });

  testWidgets('sin permisos de ubicación ni de responsable no se ofrece esa sección', (tester) async {
    await pumpForm(tester, permissions: const {'equipos:ver', 'equipos:crear'});

    expect(find.text('ASIGNACIÓN Y UBICACIÓN'), findsNothing);
    expect(find.text('Ubicación física o área'), findsNothing);
    expect(find.text('ESTADO Y GARANTÍA'), findsOneWidget);
  });

  testWidgets('con solo el permiso de ubicación se ofrece la ubicación y no el responsable', (tester) async {
    await pumpForm(tester, permissions: const {'equipos:ver', 'equipos:crear', 'equipos:editar'});

    expect(find.text('Ubicación física o área'), findsOneWidget);
    expect(find.textContaining('Responsable asignado'), findsNothing);
  });

  testWidgets('sin completar lo obligatorio muestra los avisos y no envía nada', (tester) async {
    await pumpForm(tester);

    await submit(tester);

    expect(find.text('La etiqueta es obligatoria.'), findsOneWidget);
    expect(find.text('La marca es obligatoria.'), findsOneWidget);
    expect(find.text('El modelo es obligatorio.'), findsOneWidget);
    expect(find.text('Elige la categoría del equipo.'), findsOneWidget);
    expect(posts(), isEmpty);
  });

  testWidgets('envía los datos recortados, el estado por defecto y nada más', (tester) async {
    await pumpForm(tester);
    await fillRequired(tester);

    await submit(tester);

    expect(posts().single.path, '/equipment');
    expect(posts().single.data, {'asset_tag': 'EQ-029', 'equipment_type_id': 1, 'brand': 'Dell', 'model': 'Latitude 5540', 'status': 'in_storage'});
  });

  testWidgets('envía los campos opcionales y el estado elegido', (tester) async {
    await pumpForm(tester);
    await fillRequired(tester);
    await tester.enterText(key('serial'), 'SN-1');
    await tester.enterText(key('description'), 'Intel i7, 16 GB');
    await tester.enterText(key('cost'), '1250,5');
    await pick(tester, key('status'), 'En mantenimiento');

    await submit(tester);

    expect(posts().single.data, {
      'asset_tag': 'EQ-029',
      'equipment_type_id': 1,
      'brand': 'Dell',
      'model': 'Latitude 5540',
      'status': 'in_repair',
      'serial_number': 'SN-1',
      'description': 'Intel i7, 16 GB',
      'purchase_cost': '1250.5',
    });
  });

  testWidgets('con ubicación y responsable los asigna después de crear el equipo', (tester) async {
    await pumpForm(tester);
    await fillRequired(tester);
    await pick(tester, find.byType(DropdownButtonFormField<int?>), 'Sede central');
    await tester.ensureVisible(find.text('Buscar por nombre o correo…'));
    await tester.tap(find.text('Buscar por nombre o correo…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Pérez'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Pérez'), findsOneWidget, reason: 'el campo muestra al responsable elegido');

    await submit(tester);

    expect(posts().map((r) => r.path), ['/equipment', '/equipment/7/location', '/equipment/7/custody']);
    expect(posts()[1].data, {'location_id': 3});
    expect(posts()[2].data, {'assigned_to_user_id': 9});
    expect(posts()[0].data.keys, isNot(contains('location_id')));
    expect(find.text('pantalla de equipos'), findsOneWidget);
    expect(find.text('Equipo registrado.'), findsOneWidget);
  });

  testWidgets('si no se puede asignar la ubicación el equipo queda registrado y se avisa', (tester) async {
    locationHandler = (_) => errorResponse(403);
    await pumpForm(tester);
    await fillRequired(tester);
    await pick(tester, find.byType(DropdownButtonFormField<int?>), 'Almacén norte');

    await submit(tester);

    expect(find.text('pantalla de equipos'), findsOneWidget);
    expect(find.textContaining('Equipo registrado.'), findsOneWidget);
    expect(find.textContaining('No se pudo asignar la ubicación'), findsOneWidget);
  });

  testWidgets('el selector de responsable busca por texto tras una pausa y permite quitarlo', (tester) async {
    await pumpForm(tester);
    await tester.ensureVisible(find.text('Buscar por nombre o correo…'));
    await tester.tap(find.text('Buscar por nombre o correo…'));
    await tester.pumpAndSettle();
    expect(find.text('Responsable del equipo'), findsOneWidget);
    expect(find.text('Luis Gómez'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'luis');
    await tester.pump(const Duration(milliseconds: 100));
    expect(adapter.requests.where((r) => r.path == '/equipment/custodian-candidates' && r.queryParameters.containsKey('search')), isEmpty);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(adapter.requests.last.queryParameters['search'], 'luis');

    await tester.tap(find.text('Luis Gómez'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luis Gómez'));
    await tester.pumpAndSettle();
    expect(find.text('Quitar responsable'), findsOneWidget);

    await tester.tap(find.text('Quitar responsable'));
    await tester.pumpAndSettle();
    expect(find.text('Buscar por nombre o correo…'), findsOneWidget);
  });

  testWidgets('los errores del servidor salen bajo cada campo y se borran al editarlo', (tester) async {
    createHandler = (_) => errorResponse(422, errors: [
          {'field': 'asset_tag', 'message': 'La etiqueta ya está en uso en la sede.', 'type': 'value_error'},
          {'field': 'brand', 'message': 'Marca no admitida.', 'type': 'value_error'},
        ]);
    await pumpForm(tester);
    await fillRequired(tester);

    await submit(tester);

    expect(find.text('La etiqueta ya está en uso en la sede.'), findsOneWidget);
    expect(find.text('Marca no admitida.'), findsOneWidget);
    expect(find.text('Registrar nuevo equipo'), findsOneWidget, reason: 'se queda en el formulario');

    await tester.enterText(key('brand'), 'HP');
    await tester.pump();
    expect(find.text('Marca no admitida.'), findsNothing);
    expect(find.text('La etiqueta ya está en uso en la sede.'), findsOneWidget);
  });

  testWidgets('una etiqueta o serie repetida (409) avisa con un mensaje específico y no se cierra', (tester) async {
    createHandler = (_) => errorResponse(409, code: 'equipment_identifier_taken');
    await pumpForm(tester);
    await fillRequired(tester);

    await submit(tester);

    expect(find.text('Ya existe un equipo con esa etiqueta o número de serie.'), findsOneWidget);
    expect(find.textContaining('detalle interno'), findsNothing);
    expect(find.text('pantalla de equipos'), findsNothing);
    expect(posts(), hasLength(1), reason: 'no intenta asignar nada si el alta falla');
  });

  testWidgets('el costo no admite negativos ni más de dos decimales', (tester) async {
    await pumpForm(tester);
    await fillRequired(tester);

    await tester.enterText(key('cost'), '-5');
    await submit(tester);
    expect(find.text('El costo no puede ser negativo.'), findsOneWidget);

    await tester.enterText(key('cost'), '10,555');
    await submit(tester);
    expect(find.text('El costo admite como máximo dos decimales.'), findsOneWidget);
    expect(posts(), isEmpty);
  });

  testWidgets('si las categorías no cargan se puede reintentar', (tester) async {
    typesHandler = (_) => errorResponse(500);
    await pumpForm(tester);

    expect(find.textContaining('No pudimos cargar las categorías'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    typesHandler = (_) => jsonResponse(200, _types);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No pudimos cargar las categorías'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(find.text('Laptop'), findsOneWidget);
    expect(adapter.requests.where((r) => r.path == '/equipment/types'), hasLength(2));
  });

  testWidgets('elegir una fecha la muestra y se puede quitar', (tester) async {
    await pumpForm(tester);

    await tester.ensureVisible(find.text('Elegir fecha').at(1));
    await tester.tap(find.text('Elegir fecha').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Elegir fecha'), findsNWidgets(2));
    expect(find.byTooltip('Quitar fecha'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar fecha'));
    await tester.pumpAndSettle();
    expect(find.text('Elegir fecha'), findsNWidgets(3));
  });

  testWidgets('«Cancelar» y la X vuelven a la pantalla anterior sin enviar nada', (tester) async {
    await pumpForm(tester);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('pantalla de equipos'), findsOneWidget);

    router.push(CreateEquipmentScreen.path);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('pantalla de equipos'), findsOneWidget);
    expect(posts(), isEmpty);
  });

  testWidgets('con la fuente del sistema más grande no se desborda', (tester) async {
    await pumpForm(tester, textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('GUARDAR EQUIPO'), findsOneWidget);
  });
}
