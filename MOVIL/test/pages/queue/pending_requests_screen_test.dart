import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/queue/pending_requests_screen.dart';
import 'package:mantix/widgets/queue/queue_board.dart';
import 'package:mantix/widgets/queue/queue_card.dart';
import 'package:mantix/widgets/queue/queue_kpi_strip.dart';
import 'package:mantix/widgets/shared/filter_widgets.dart';
import 'package:mantix/widgets/shared/multi_select_sheet.dart';

import '../../models/queue/queue_models_test.dart' show summaryJson;
import '../../support/fakes.dart';
import '../../support/requests_support.dart';

const _workflow = [
  {'status': 'submitted', 'order': 1, 'allowed_targets': ['triaged', 'assigned', 'cancelled'], 'requires': [], 'can_enter': true, 'in_queue': true},
  {'status': 'triaged', 'order': 2, 'allowed_targets': ['assigned', 'cancelled'], 'requires': ['category', 'priority'], 'can_enter': true, 'in_queue': true},
  {'status': 'assigned', 'order': 3, 'allowed_targets': ['in_progress', 'cancelled'], 'requires': ['technician'], 'can_enter': true, 'in_queue': true},
  {'status': 'in_progress', 'order': 4, 'allowed_targets': [], 'requires': [], 'can_enter': true, 'in_queue': false},
];

const _categories = [
  {'code': 'network', 'name': 'Red'},
  {'code': 'hardware', 'name': 'Hardware'},
];

const _priorities = [
  {'id': 1, 'code': 'low', 'name': 'Baja', 'level': 1},
  {'id': 2, 'code': 'high', 'name': 'Alta', 'level': 3},
  {'id': 3, 'code': 'critical', 'name': 'Crítica', 'level': 4},
];

const _permissions = {'solicitudes:ver_todos', 'tickets:ver', 'tecnicos:ver'};

Map<String, Object?> _ticket(int id, String status, {String priority = 'critical', String? category = 'network', String title = 'La laptop no enciende'}) => {
      ...ticketJson(id: id, status: status, priority: priority, title: title, canAct: true),
      'category': category,
      'created_at': '2020-01-01T00:00:00Z',
    };

/// Una opción dentro de la hoja de casillas (el mismo texto también sale en las tarjetas y las barras).
Finder _inSheet(String label) => find.descendant(of: find.byType(MultiSelectSheet<String>), matching: find.text(label));

/// El recuadro pulsable de una fila de la hoja de filtros (el texto de arriba es solo su etiqueta).
Finder _tile(String label) => find.descendant(of: find.widgetWithText(FilterTile, label), matching: find.byType(InkWell));

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) summaryHandler;
  late ResponseBody Function(RequestOptions) listHandler;
  late ResponseBody Function(RequestOptions) workflowHandler;
  late ResponseBody Function(RequestOptions) categoriesHandler;

  setUp(() {
    summaryHandler = (_) => jsonResponse(200, summaryJson);
    workflowHandler = (_) => jsonResponse(200, _workflow);
    categoriesHandler = (_) => jsonResponse(200, _categories);
    listHandler = (options) {
      final status = options.queryParameters['status'];
      return switch (status) {
        'submitted' => pagedResponse([_ticket(1, 'submitted'), _ticket(2, 'submitted', priority: 'low', category: null, title: 'Teclado sin respuesta')], total: 12, totalPages: 2),
        'triaged' => pagedResponse([_ticket(3, 'triaged', priority: 'high')]),
        _ => pagedResponse(<Object?>[]),
      };
    };
    adapter = FakeAdapter((options) => switch (options.path) {
          '/maintenance/queue/summary' => summaryHandler(options),
          '/maintenance/requests/workflow' => workflowHandler(options),
          '/maintenance/requests' => listHandler(options),
          '/maintenance/categories' => categoriesHandler(options),
          '/priorities' => jsonResponse(200, _priorities),
          '/technicians' => pagedResponse(<Object?>[]),
          _ => errorResponse(404),
        });
  });

  Future<void> open(WidgetTester tester, {Size size = const Size(1400, 2400), double textScale = 1}) async {
    await pumpScreen(tester, const PendingRequestsScreen(), adapter, permissions: _permissions, size: size, textScale: textScale);
    await tester.pumpAndSettle();
  }

  group('con datos', () {
    testWidgets('muestra el encabezado, las cifras, el pulso y las columnas con sus tarjetas', (tester) async {
      await open(tester);

      expect(find.text('BANDEJA DE TRIAJE'), findsOneWidget);
      expect(find.textContaining('PENDIENTES', findRichText: true), findsOneWidget);
      expect(find.textContaining('Arrastra una tarjeta a otra columna'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);

      // Cifras (la web las llama igual; el servidor entrega la mediana).
      for (final label in ['EN COLA', 'SIN TÉCNICO', 'MÁS ANTIGUA', 'ESPERA MEDIANA']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('14'), findsOneWidget);
      expect(find.text('10,2 d'), findsWidgets, reason: 'la más antigua: 245 h');
      expect(find.text('24,1 h'), findsOneWidget);

      // Pulso de la cola.
      expect(find.text('PULSO DE LA COLA'), findsOneWidget);
      expect(find.text('Decisiones de los últimos 30 días'), findsOneWidget);
      expect(find.text('6,5 h'), findsOneWidget);
      expect(find.text('mediana 4,2 h · n = 8'), findsOneWidget);
      expect(find.text('▲ 30%'), findsOneWidget);
      expect(find.text('75% / 25%'), findsOneWidget);
      expect(find.text('6 aprobadas · 2 rechazadas · n = 8'), findsOneWidget);
      expect(find.text('POR PRIORIDAD'), findsOneWidget);
      expect(find.text('POR CATEGORÍA'), findsOneWidget);
      expect(find.text('Sin categoría'), findsWidgets);

      // Tablero.
      expect(find.text('Solicitudes por estado'), findsOneWidget);
      expect(find.text('3 columnas visibles'), findsOneWidget);
      expect(find.text('Recibidas'), findsOneWidget);
      expect(find.text('Clasificadas'), findsOneWidget);
      expect(find.text('Asignadas'), findsOneWidget);
      expect(find.byType(QueueCard), findsNWidgets(3));
      expect(find.text('La laptop no enciende'), findsNWidgets(2));
      expect(find.text('Equipo #12'), findsNWidgets(3));
      expect(find.text('Sin solicitudes en esta columna.'), findsOneWidget, reason: 'Asignadas está vacía');
      expect(find.text('Ver más (10 restantes)'), findsOneWidget, reason: '12 recibidas y 2 cargadas');
    });

    testWidgets('una tarjeta antigua muestra su espera en el tono de alerta y los nombres del servidor', (tester) async {
      await open(tester);

      final card = find.byType(QueueCard).first;
      expect(find.descendant(of: card, matching: find.text('TCK-0001')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Crítica')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Red')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining(' d')), findsWidgets, reason: 'su espera, en días');
    });

    testWidgets('«Ver más» pide la página siguiente de esa columna', (tester) async {
      await open(tester);
      adapter.requests.clear();

      await tester.tap(find.text('Ver más (10 restantes)'));
      await tester.pumpAndSettle();

      final call = adapter.requests.singleWhere((r) => r.path == '/maintenance/requests');
      expect(call.queryParameters['status'], 'submitted');
      expect(call.queryParameters['page'], 2);
    });

    testWidgets('tirar hacia abajo recarga el resumen y las columnas', (tester) async {
      await open(tester);
      adapter.requests.clear();

      // Lo que hace tirar hacia abajo: llamar a onRefresh y esperar a que terminen las dos cargas.
      var finished = false;
      final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
      unawaited(refresh.then((_) => finished = true));
      await tester.pumpAndSettle();
      expect(finished, isTrue, reason: 'el indicador termina cuando llegan el resumen y las columnas');
      expect(adapter.requests.where((r) => r.path == '/maintenance/queue/summary'), hasLength(1));
      expect(adapter.requests.where((r) => r.path == '/maintenance/requests'), hasLength(3));
    });

    testWidgets('la flecha de las cifras avanza una tarjeta', (tester) async {
      await open(tester, size: const Size(360, 800));

      expect(find.byTooltip('Ver más cifras'), findsOneWidget);
      await tester.tap(find.byTooltip('Ver más cifras'));
      await tester.pumpAndSettle();
      expect(find.byType(QueueKpiStrip), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('falla una parte y las demás siguen', () {
    testWidgets('si el resumen no carga, las cifras y el pulso dicen «no disponible» y el tablero funciona', (tester) async {
      summaryHandler = (_) => errorResponse(500);
      await open(tester);

      expect(find.text('Las cifras de la cola no están disponibles.'), findsOneWidget);
      expect(find.text('El pulso de la cola no está disponible.'), findsOneWidget);
      expect(find.byType(QueueCard), findsNWidgets(3));

      // Reintentar vuelve a pedirlo y, esta vez, llega.
      summaryHandler = (_) => jsonResponse(200, summaryJson);
      await tester.tap(find.text('Reintentar').first);
      await tester.pumpAndSettle();
      expect(find.text('EN COLA'), findsOneWidget);
      expect(find.text('PULSO DE LA COLA'), findsOneWidget);
    });

    testWidgets('si una columna falla, solo esa muestra el error y se reintenta', (tester) async {
      final original = listHandler;
      listHandler = (options) => options.queryParameters['status'] == 'triaged' ? errorResponse(500) : original(options);
      await open(tester);

      expect(find.byType(QueueCard), findsNWidgets(2));
      expect(find.text('Algo salió mal en el servidor. Inténtalo más tarde.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      listHandler = original;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(QueueCard), findsNWidgets(3));
    });

    testWidgets('si el flujo no carga no hay columnas y se puede reintentar', (tester) async {
      workflowHandler = (_) => errorResponse(500);
      await open(tester);

      expect(find.text('No pudimos cargar el tablero'), findsOneWidget);
      expect(find.byType(QueueCard), findsNothing);
      // Las cifras siguen.
      expect(find.text('EN COLA'), findsOneWidget);

      workflowHandler = (_) => jsonResponse(200, _workflow);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(QueueCard), findsNWidgets(3));
    });

    testWidgets('sin catálogo de categorías rotula con el código, sin romper nada', (tester) async {
      categoriesHandler = (_) => errorResponse(500);
      await open(tester);

      expect(find.byType(QueueCard), findsNWidgets(3));
      expect(find.text('network'), findsWidgets);
    });
  });

  group('estados vacíos', () {
    testWidgets('bandeja al día', (tester) async {
      listHandler = (_) => pagedResponse(<Object?>[]);
      await open(tester);

      expect(find.text('La bandeja está al día'), findsOneWidget);
      expect(find.byType(QueueCard), findsNothing);
    });

    testWidgets('con filtros que no coinciden se puede limpiarlos', (tester) async {
      await open(tester);
      listHandler = (_) => pagedResponse(<Object?>[]);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Ninguna solicitud coincide con los filtros'), findsOneWidget);
      expect(find.text('La bandeja está al día'), findsNothing);

      // «Limpiar filtros» quita también la búsqueda y vuelve a pedir todo.
      listHandler = (_) => pagedResponse([_ticket(1, 'submitted')]);
      await tester.tap(find.text('Limpiar filtros'));
      await tester.pumpAndSettle();
      expect(find.byType(QueueCard), findsWidgets);
      expect(find.byTooltip('Borrar búsqueda'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });
  });

  group('búsqueda y filtros', () {
    testWidgets('la búsqueda espera a que se deje de escribir y pide el término recortado a las tres columnas', (tester) async {
      await open(tester);
      adapter.requests.clear();

      await tester.enterText(find.byType(TextField), '  laptop ');
      await tester.pump(const Duration(milliseconds: 100));
      expect(adapter.requests.where((r) => r.path == '/maintenance/requests'), isEmpty, reason: 'todavía espera');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final calls = adapter.requests.where((r) => r.path == '/maintenance/requests').toList();
      expect(calls, hasLength(3));
      expect(calls.map((r) => r.queryParameters['search']).toSet(), {'laptop'});
      expect(find.byTooltip('Borrar búsqueda'), findsOneWidget);
    });

    testWidgets('la hoja aplica categoría y prioridad, y cada filtro sale como chip que se quita', (tester) async {
      await open(tester);
      adapter.requests.clear();

      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(_tile('Categoría'));
      await tester.pumpAndSettle();
      await tester.tap(_inSheet('Red'));
      await tester.tap(find.text('Aplicar').last);
      await tester.pumpAndSettle();
      await tester.tap(_tile('Prioridad'));
      await tester.pumpAndSettle();
      await tester.tap(_inSheet('Alta'));
      await tester.tap(_inSheet('Crítica'));
      await tester.tap(find.text('Aplicar').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar').last);
      await tester.pumpAndSettle();

      final query = adapter.requests.where((r) => r.path == '/maintenance/requests').first.queryParameters;
      expect(query['category'], 'network');
      expect(query['priority'], 'critical,high', reason: 'en el orden del servidor, la más urgente primero');
      expect(find.byTooltip('Filtros (2 activos)'), findsOneWidget);
      expect(find.byType(ActiveFilterChip), findsNWidgets(3), reason: 'Red, Alta y Crítica');

      adapter.requests.clear();
      await tester.tap(find.byTooltip('Quitar filtro').first);
      await tester.pumpAndSettle();
      expect(adapter.requests.where((r) => r.path == '/maintenance/requests').first.queryParameters.containsKey('category'), isFalse);
    });

    testWidgets('cerrar la hoja sin aplicar no cambia nada', (tester) async {
      await open(tester);
      adapter.requests.clear();

      await tester.tap(find.byTooltip('Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(_tile('Categoría'));
      await tester.pumpAndSettle();
      await tester.tap(_inSheet('Red'));
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(adapter.requests.where((r) => r.path == '/maintenance/requests'), isEmpty);
    });
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        await open(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);

        // Recorre toda la pantalla y el tablero.
        final page = find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable)).first;
        await tester.scrollUntilVisible(find.text('Solicitudes por estado'), 300, scrollable: page);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(QueueBoard), const Offset(-600, 0), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('${size.width.toInt()}×${size.height.toInt()} con el resumen caído y una columna con error', (tester) async {
        summaryHandler = (_) => errorResponse(500);
        listHandler = (options) => options.queryParameters['status'] == 'triaged' ? errorResponse(500) : pagedResponse([_ticket(1, 'submitted', title: 'Un título muy largo que no cabe en una sola línea de la tarjeta de la columna')]);
        await open(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
