import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mantix/core/theme/app_theme.dart';
import 'package:mantix/pages/equipment/create_equipment_screen.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';

import '../../models/equipment/equipment_models_test.dart' show equipmentItemJson;
import '../../support/fakes.dart';
import '../../support/requests_support.dart';

const _types = [
  {'id': 1, 'code': 'LAPTOP', 'name': 'Laptop'},
  {'id': 2, 'code': 'PRINTER', 'name': 'Impresora'},
];

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) typesHandler;
  late ResponseBody Function(RequestOptions) createHandler;
  late EquipmentRepository repository;
  late GoRouter router;

  setUp(() {
    typesHandler = (_) => jsonResponse(200, _types);
    createHandler = (_) => jsonResponse(201, equipmentItemJson());
    adapter = FakeAdapter((options) => options.method == 'POST' ? createHandler(options) : typesHandler(options));
    repository = EquipmentRepository(dioWith(adapter));
  });

  Future<void> pumpForm(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(390, 3200);
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
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: app!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push(CreateEquipmentScreen.path);
    await tester.pumpAndSettle();
  }

  List<RequestOptions> posts() => adapter.requests.where((r) => r.method == 'POST').toList();

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> pickType(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(field('Etiqueta de activo *'), '  EQ-029 ');
    await tester.enterText(field('Marca *'), 'Dell');
    await tester.enterText(field('Modelo *'), 'Latitude 5540');
    await pickType(tester, 'Laptop');
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Registrar equipo'));
    await tester.tap(find.text('Registrar equipo'));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra los campos del formulario y carga las categorías', (tester) async {
    await pumpForm(tester);

    for (final label in ['Etiqueta de activo *', 'Marca *', 'Modelo *', 'Número de serie', 'Descripción y especificaciones técnicas', 'Costo de adquisición']) {
      expect(field(label), findsOneWidget, reason: label);
    }
    for (final label in ['Fecha de adquisición', 'Garantía desde', 'Garantía hasta']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Nuevo equipo'), findsOneWidget);
    expect(adapter.requests.where((r) => r.path == '/equipment/types'), hasLength(1));

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Impresora'), findsOneWidget);
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

  testWidgets('envía los datos recortados y normalizados', (tester) async {
    await pumpForm(tester);
    await fillRequired(tester);
    await tester.enterText(field('Número de serie'), 'SN-1');
    await tester.enterText(field('Descripción y especificaciones técnicas'), 'Intel i7, 16 GB');
    await tester.enterText(field('Costo de adquisición'), '1250,5');

    await submit(tester);

    expect(posts().single.path, '/equipment');
    expect(posts().single.data, {
      'asset_tag': 'EQ-029',
      'equipment_type_id': 1,
      'brand': 'Dell',
      'model': 'Latitude 5540',
      'serial_number': 'SN-1',
      'description': 'Intel i7, 16 GB',
      'purchase_cost': '1250.5',
    });
  });

  testWidgets('solo envía lo obligatorio si el resto queda vacío', (tester) async {
    await pumpForm(tester);
    await fillRequired(tester);

    await submit(tester);

    expect(posts().single.data, {'asset_tag': 'EQ-029', 'equipment_type_id': 1, 'brand': 'Dell', 'model': 'Latitude 5540'});
  });

  testWidgets('al registrar vuelve a la pantalla anterior con un aviso', (tester) async {
    await pumpForm(tester);
    await fillRequired(tester);

    await submit(tester);

    expect(find.text('pantalla de equipos'), findsOneWidget);
    expect(find.text('Equipo registrado.'), findsOneWidget);
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
    expect(find.text('Nuevo equipo'), findsOneWidget, reason: 'se queda en el formulario');

    await tester.enterText(field('Marca *'), 'HP');
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
  });

  testWidgets('el costo no admite negativos ni más de dos decimales', (tester) async {
    await pumpForm(tester);
    await fillRequired(tester);

    await tester.enterText(field('Costo de adquisición'), '-5');
    await submit(tester);
    expect(find.text('El costo no puede ser negativo.'), findsOneWidget);

    await tester.enterText(field('Costo de adquisición'), '10,555');
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

    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(adapter.requests.where((r) => r.path == '/equipment/types'), hasLength(2));
  });

  testWidgets('elegir una fecha la muestra y se puede quitar', (tester) async {
    await pumpForm(tester);

    await tester.ensureVisible(find.text('Garantía desde'));
    await tester.tap(find.text('Garantía desde'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Elegir fecha'), findsNWidgets(2));
    expect(find.byTooltip('Quitar fecha'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar fecha'));
    await tester.pumpAndSettle();
    expect(find.text('Elegir fecha'), findsNWidgets(3));
  });

  testWidgets('con la fuente del sistema más grande no se desborda', (tester) async {
    await pumpForm(tester, textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('Registrar equipo'), findsOneWidget);
  });
}
