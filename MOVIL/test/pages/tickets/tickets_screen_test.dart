import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/theme/app_colors.dart';
import 'package:mantix/models/requests/request_models.dart';
import 'package:mantix/pages/tickets/tickets_screen.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';
import 'package:mantix/widgets/shared/filter_widgets.dart';
import 'package:mantix/widgets/shared/paginator.dart';
import 'package:mantix/widgets/tickets/ticket_cards.dart';

import '../../support/paginator_support.dart';
import '../../support/fakes.dart';
import '../../support/requests_support.dart';

/// Flujo de estados como lo envía el servidor.
const _workflow = [
  {'status': 'submitted', 'order': 1, 'allowed_targets': ['triaged', 'assigned', 'cancelled'], 'requires': [], 'can_enter': true},
  {'status': 'triaged', 'order': 2, 'allowed_targets': ['assigned', 'cancelled'], 'requires': ['category', 'priority'], 'can_enter': true},
  {'status': 'assigned', 'order': 3, 'allowed_targets': ['in_progress', 'cancelled'], 'requires': ['technician'], 'can_enter': true},
  {'status': 'in_progress', 'order': 4, 'allowed_targets': ['waiting', 'resolved', 'cancelled'], 'requires': [], 'can_enter': true},
  {'status': 'waiting', 'order': 5, 'allowed_targets': ['in_progress', 'cancelled'], 'requires': [], 'can_enter': true},
  {'status': 'resolved', 'order': 6, 'allowed_targets': ['closed', 'in_progress'], 'requires': ['resolution_summary'], 'can_enter': true},
  {'status': 'closed', 'order': 7, 'allowed_targets': [], 'requires': [], 'can_enter': false},
  {'status': 'cancelled', 'order': 8, 'allowed_targets': [], 'requires': ['reason'], 'can_enter': true},
];

const _categories = [
  {'code': 'hardware', 'name': 'Hardware'},
  {'code': 'software', 'name': 'Software'},
  {'code': 'network', 'name': 'Red'},
];

const _priorities = [
  {'id': 1, 'code': 'low', 'name': 'Baja', 'level': 1},
  {'id': 2, 'code': 'medium', 'name': 'Media', 'level': 2},
  {'id': 3, 'code': 'high', 'name': 'Alta', 'level': 3},
  {'id': 4, 'code': 'critical', 'name': 'Crítica', 'level': 4},
];

Map<String, Object?> _technician(int id, String name, {bool active = true, bool available = true, String? specialization}) => {
      'id': id,
      'user_id': id + 100,
      'full_name': name,
      'email': '${name.split(' ').first.toLowerCase()}@x.co',
      'employee_code': null,
      'specialization': specialization,
      'is_available': available,
      'is_active': active,
      'hourly_rate': null,
      'created_at': '2026-10-01T10:00:00Z',
    };

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) listHandler;
  late ResponseBody Function(RequestOptions) statusHandler;
  late ResponseBody Function(RequestOptions) classifyHandler;
  late ResponseBody Function(RequestOptions) assignHandler;
  late ResponseBody Function(RequestOptions) techniciansHandler;
  late ResponseBody Function(RequestOptions) prioritiesHandler;
  late RequestsRepository repository;

  setUp(() {
    listHandler = (_) => pagedResponse([ticketJson()]);
    statusHandler = (_) => jsonResponse(200, detailJson(status: 'waiting'));
    classifyHandler = (_) => jsonResponse(200, detailJson(status: 'triaged'));
    assignHandler = (_) => jsonResponse(200, detailJson(status: 'assigned'));
    prioritiesHandler = (_) => jsonResponse(200, _priorities);
    techniciansHandler = (_) => pagedResponse([
          _technician(5, 'Luis Técnico', specialization: 'Redes'),
          _technician(6, 'Ana Inactiva', active: false),
          _technician(7, 'Marta Pérez', available: false),
        ], total: 3);
    adapter = FakeAdapter((options) {
      if (options.path == '/maintenance/requests/workflow') return jsonResponse(200, _workflow);
      if (options.path == '/maintenance/categories') return jsonResponse(200, _categories);
      if (options.path == '/priorities') return prioritiesHandler(options);
      if (options.path == '/technicians') return techniciansHandler(options);
      if (options.method == 'POST' && options.path.endsWith('/classify')) return classifyHandler(options);
      if (options.method == 'POST' && options.path.endsWith('/assignment')) return assignHandler(options);
      if (options.method == 'POST' && options.path.endsWith('/status')) return statusHandler(options);
      if (options.method == 'POST' && options.path == '/maintenance/requests') return jsonResponse(201, detailJson(id: 99));
      if (options.path == '/equipment') return pagedResponse([equipmentJson()]);
      if (options.path.endsWith('/attachments')) return jsonResponse(200, []);
      if (RegExp(r'^/maintenance/requests/\d+$').hasMatch(options.path)) return jsonResponse(200, detailJson());
      return listHandler(options);
    });
  });

  Future<void> pump(WidgetTester tester, {Set<String> permissions = const {'solicitudes:ver', 'solicitudes:crear', 'tickets:ver'}, Size size = const Size(1400, 1800), double textScale = 1}) async {
    await pumpScreen(tester, const TicketsScreen(), adapter, permissions: permissions, size: size, textScale: textScale);
    await tester.pumpAndSettle();
    repository = RepositoryProvider.of<RequestsRepository>(tester.element(find.byType(TicketsScreen)));
  }

  List<RequestOptions> listRequests() => adapter.requests.where((r) => r.method == 'GET' && r.path == '/maintenance/requests').toList();
  Map<String, dynamic> lastQuery() => listRequests().last.queryParameters;

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Filtros'));
    await tester.pumpAndSettle();
  }

  Future<void> apply(WidgetTester tester) async {
    await tester.tap(find.text('Aplicar').last);
    await tester.pumpAndSettle();
  }

  group('encabezado y resumen', () {
    testWidgets('usa el encabezado de Equipos, sin banner ni textos de más', (tester) async {
      listHandler = (_) => pagedResponse([
            ticketJson(),
            ticketJson(id: 2, status: 'in_progress', title: 'Ventilador con ruido', priority: 'critical'),
            ticketJson(id: 3, status: 'resolved', title: 'Error de pantalla', priority: 'low'),
          ], total: 3);
      await pump(tester);

      expect(find.text('GESTIÓN DE TICKETS'), findsOneWidget);
      expect(find.text('Incidencias y órdenes de trabajo.'), findsOneWidget);
      expect(find.text('Tickets recientes'), findsNothing);
      expect(find.textContaining('Registra, asigna'), findsNothing, reason: 'el banner azul ya no existe');
      expect(find.text('La laptop no enciende'), findsWidgets);
      expect(find.text('Ventilador con ruido'), findsWidgets);
      expect(find.widgetWithText(PriorityPill, 'Crítica'), findsWidgets);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('el botón «Nuevo ticket» solo está con permiso y abre el formulario en una hoja', (tester) async {
      await pump(tester);
      expect(find.text('Nuevo ticket'), findsOneWidget);
      await tester.tap(find.text('Nuevo ticket'));
      await tester.pumpAndSettle();
      expect(find.text('Crear nuevo ticket'), findsOneWidget);
      expect(find.text('GESTIÓN DE TICKETS'), findsOneWidget, reason: 'la pantalla de fondo sigue ahí');
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      await pump(tester, permissions: const {'tickets:ver'});
      expect(find.text('Nuevo ticket'), findsNothing);
    });

    testWidgets('las tarjetas muestran el equipo cuando el servidor lo envía', (tester) async {
      listHandler = (_) => pagedResponse([
            ticketJson(equipment: {'id': 12, 'asset_tag': 'EQ-0012', 'brand': 'Dell', 'model': 'Latitude'}),
          ]);
      await pump(tester);
      expect(find.text('EQ-0012 · Dell Latitude'), findsOneWidget);
    });
  });

  group('filtros', () {
    testWidgets('estado con varias opciones se envía como lista separada por comas', (tester) async {
      await pump(tester);
      await openFilters(tester);
      await tester.tap(find.byType(FilterTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('En proceso').last);
      await tester.tap(find.text('Enviado').last);
      await tester.pumpAndSettle();
      expect(find.text('2 activos'), findsOneWidget, reason: 'la hoja no se cierra al marcar');
      await apply(tester);
      await apply(tester);

      expect(lastQuery()['status'], 'submitted,in_progress');
      expect(find.byTooltip('Filtros (2 activos)'), findsOneWidget);
    });

    testWidgets('una prioridad viaja sola y varias separadas por coma', (tester) async {
      await pump(tester);
      await openFilters(tester);
      await tester.tap(find.byType(FilterTile).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alta').last);
      await tester.pumpAndSettle();
      await apply(tester);
      await apply(tester);
      expect(lastQuery()['priority'], 'high');

      await tester.tap(find.byTooltip('Filtros (1 activos)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilterTile).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crítica').last);
      await tester.pumpAndSettle();
      await apply(tester);
      await apply(tester);
      expect(lastQuery()['priority'], 'critical,high');
    });

    testWidgets('el equipo se elige con búsqueda y se envía como equipment_id', (tester) async {
      await pump(tester);
      await openFilters(tester);
      await tester.tap(find.text('Elegir equipo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EQ-0012 · Dell Latitude'));
      await tester.pumpAndSettle();
      expect(find.text('Añadir otro equipo'), findsOneWidget);
      await apply(tester);

      expect(lastQuery()['equipment_id'], 12);
      expect(find.text('EQ-0012 · Dell Latitude'), findsOneWidget, reason: 'queda como chip de filtro activo');
    });

    testWidgets('«Limpiar» quita todo al aplicar y los chips se quitan solos', (tester) async {
      await pump(tester);
      await openFilters(tester);
      await tester.tap(find.byType(FilterTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviado').last);
      await tester.pumpAndSettle();
      await apply(tester);
      await apply(tester);
      expect(lastQuery()['status'], 'submitted');

      await tester.tap(find.byTooltip('Quitar filtro'));
      await tester.pumpAndSettle();
      expect(lastQuery().keys, isNot(contains('status')));
    });

    testWidgets('las fechas usan el calendario compacto y se envían como date_from y date_to', (tester) async {
      await pump(tester);
      await openFilters(tester);
      await tester.tap(find.text('Cualquier fecha'));
      await tester.pumpAndSettle();
      expect(find.text('Rango de fechas'), findsWidgets);
      await tester.tap(find.text('Elegir').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      await apply(tester);
      await apply(tester);
      expect(lastQuery().keys, containsAll(['date_from', 'date_to']));
    });

    testWidgets('envía la búsqueda al servidor al confirmar el campo', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'ventilador');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(lastQuery()['search'], 'ventilador');
    });
  });

  group('paginación', () {
    testWidgets('pide la página elegida y vuelve arriba', (tester) async {
      listHandler = (options) {
        final page = options.queryParameters['page'] as int? ?? 1;
        return pagedResponse([ticketJson(id: page, title: 'Ticket de la página $page')], page: page, totalPages: 3, total: 41);
      };
      await pump(tester);
      expect(selectedPage(tester), 1);
      expect(find.textContaining(' de 41'), findsNothing, reason: 'ya no se escribe el rango');
      await tester.scrollUntilVisible(find.byTooltip('Página siguiente'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();

      expect(lastQuery()['page'], 3);
      expect(find.text('Ticket de la página 3'), findsWidgets);
    });

    testWidgets('cambiar el tamaño de página pide size=10 desde la página 1', (tester) async {
      listHandler = (options) {
        final page = options.queryParameters['page'] as int? ?? 1;
        return pagedResponse([ticketJson(id: page)], page: page, totalPages: 3, total: 41);
      };
      await pump(tester);
      expect(lastQuery()['size'], 20);
      await tester.scrollUntilVisible(find.byType(DropdownButton<int>), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 por página').last);
      await tester.pumpAndSettle();

      expect(lastQuery()['size'], 10);
      expect(lastQuery()['page'], 1);
    });
  });

  group('detalle en hoja inferior', () {
    testWidgets('tocar la fila abre el detalle con datos, historial con creación y adjuntos', (tester) async {
      await pump(tester);
      await tester.tap(find.text('La laptop no enciende').first);
      await tester.pumpAndSettle();

      expect(find.text('Detalle del ticket'), findsOneWidget);
      expect(find.text('GESTIÓN DE TICKETS'), findsOneWidget, reason: 'el encabezado de la pantalla sigue visible detrás');
      expect(find.text('Datos del ticket'), findsOneWidget);
      expect(find.text('Técnico asignado'), findsOneWidget);
      expect(find.text('Luis Técnico'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Ticket creado'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('Ticket creado'), findsOneWidget);
      expect(find.text('Enviado → Asignado'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Adjuntos'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('Adjuntos'), findsOneWidget);
      expect(adapter.requests.any((r) => r.path == '/maintenance/requests/1'), isTrue);
    });

    testWidgets('tocar la tarjeta de atención prioritaria también abre la hoja', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
      expect(find.text('Detalle del ticket'), findsOneWidget);
    });
  });

  group('tablero', () {
    setUp(() {
      listHandler = (_) => pagedResponse([
            ticketJson(id: 1, status: 'in_progress', title: 'Equipo en curso', priority: 'low', canAct: true),
            ticketJson(id: 2, status: 'submitted', title: 'Equipo nuevo', priority: 'low', canAct: false),
            ticketJson(id: 3, status: 'resolved', title: 'Equipo reparado', priority: 'low', canAct: true),
          ]);
    });

    Future<void> openBoard(WidgetTester tester, {Size size = const Size(1400, 1800), double textScale = 1}) async {
      await pump(tester, size: size, textScale: textScale);
      await tester.scrollUntilVisible(find.text('Kanban'), 100, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kanban'));
      await tester.pumpAndSettle();
    }

    testWidgets('Kanban carga también las páginas siguientes sin mostrar paginador', (tester) async {
      listHandler = (options) {
        final page = options.queryParameters['page'] as int;
        return pagedResponse(
          [ticketJson(id: page == 1 ? 1 : 501, title: page == 1 ? 'Primer ticket' : 'Ticket 501')],
          page: page,
          totalPages: 2,
          total: 501,
        );
      };
      await openBoard(tester);

      expect(find.text('Ticket 501'), findsNWidgets(2), reason: 'el número y el título coinciden en esta tarjeta');
      expect(find.byType(TicketKanbanCard), findsNWidgets(2));
      expect(listRequests().where((r) => r.queryParameters['size'] == 500), hasLength(2));
      expect(find.byType(Paginator), findsNothing);
    });

    testWidgets('muestra un estado debajo de otro con su contador y sin desplazamiento horizontal', (tester) async {
      await openBoard(tester);

      for (final label in ['Enviado', 'En triaje', 'Asignado', 'En proceso', 'En espera', 'Resuelto', 'Cerrado', 'Cancelado']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Equipo en curso'), findsOneWidget);
      expect(find.text('Equipo nuevo'), findsOneWidget);
      expect(find.byType(Paginator), findsNothing, reason: 'Kanban no pagina');
      expect(lastQuery()['size'], 500, reason: 'Kanban carga la página máxima del API');
      final horizontal = tester.widgetList<Scrollable>(find.byType(Scrollable)).where((s) => s.axisDirection == AxisDirection.right || s.axisDirection == AxisDirection.left);
      // El único desplazamiento horizontal posible es el de los campos de texto y el carrusel
      // de atención prioritaria; el tablero no añade ninguno.
      expect(horizontal.length, lessThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cada sección se puede cerrar y abrir', (tester) async {
      await openBoard(tester);
      expect(find.text('Equipo en curso'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(RegExp('En proceso, 1 ticket, abierto')));
      await tester.pumpAndSettle();
      expect(find.text('Equipo en curso'), findsNothing);

      await tester.tap(find.bySemanticsLabel(RegExp('En proceso, 1 ticket, cerrado')));
      await tester.pumpAndSettle();
      expect(find.text('Equipo en curso'), findsOneWidget);
    });

    testWidgets('«Mover a…» solo ofrece los destinos válidos y manda el cambio', (tester) async {
      await openBoard(tester);
      await tester.tap(find.byTooltip('Mover a…').first);
      await tester.pumpAndSettle();
      // Desde «En proceso»: En espera, Resuelto y Cancelado (Cerrado no es alcanzable).
      expect(find.text('En espera'), findsWidgets);
      expect(find.descendant(of: find.byType(PopupMenuItem<String>), matching: find.text('Cerrado')), findsNothing);
      await tester.tap(find.descendant(of: find.byType(PopupMenuItem<String>), matching: find.text('En espera')));
      await tester.pumpAndSettle();

      final post = adapter.requests.singleWhere((r) => r.method == 'POST' && r.path == '/maintenance/requests/1/status');
      expect(post.data, {'status': 'waiting'});
      expect(find.textContaining('pasó a «En espera»'), findsOneWidget);
    });

    testWidgets('un ticket sobre el que no se puede actuar no tiene menú ni se arrastra', (tester) async {
      await openBoard(tester);
      // «Equipo nuevo» (id 2) no es del usuario: solo hay menú en las otras dos tarjetas.
      expect(find.byTooltip('Mover a…'), findsNWidgets(2));
      expect(find.byType(LongPressDraggable<TicketListItem>), findsNWidgets(2));
    });

    testWidgets('un estado que exige la resolución la pide en un diálogo corto', (tester) async {
      await openBoard(tester);
      await tester.tap(find.byTooltip('Mover a…').first);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(PopupMenuItem<String>), matching: find.text('Resuelto')));
      await tester.pumpAndSettle();

      expect(find.text('Resumen de la solución'), findsOneWidget);
      await tester.tap(find.text('Mover'));
      await tester.pumpAndSettle();
      expect(find.text('Resumen de la solución es obligatorio.'), findsOneWidget);
      expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);

      await tester.enterText(find.byType(TextField).last, '  Se cambió el SSD ');
      await tester.tap(find.text('Mover'));
      await tester.pumpAndSettle();
      final post = adapter.requests.singleWhere((r) => r.method == 'POST' && r.path.endsWith('/status'));
      expect(post.data, {'status': 'resolved', 'resolution_summary': 'Se cambió el SSD'});
    });

    Future<void> openMenuFor(WidgetTester tester, String target) async {
      await tester.scrollUntilVisible(
        find.byTooltip('Mover a…'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('Mover a…').first);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(PopupMenuItem<String>), matching: find.text(target)));
      await tester.pumpAndSettle();
    }

    group('pasar a «En triaje»', () {
      setUp(() => listHandler = (_) => pagedResponse([ticketJson(id: 2, status: 'submitted', title: 'Sin clasificar', priority: 'low', canAct: true)]));

      FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar triaje'));

      testWidgets('pide la categoría y la prioridad: no se puede confirmar sin categoría', (tester) async {
        await openBoard(tester);
        await openMenuFor(tester, 'En triaje');

        expect(find.text('Pasar a «En triaje»'), findsOneWidget);
        expect(find.text('Elegir categoría'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Baja'), findsOneWidget);
        expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Baja')).selected, isTrue, reason: 'la prioridad del ticket queda elegida');
        expect(confirm(tester).onPressed, isNull);
        expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      });

      testWidgets('con categoría y prioridad confirma y manda classify con los datos', (tester) async {
        await openBoard(tester);
        await openMenuFor(tester, 'En triaje');
        await tester.tap(find.byKey(const Key('field-category')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Software'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Alta'));
        await tester.pumpAndSettle();
        expect(confirm(tester).onPressed, isNotNull);
        await tester.enterText(find.byType(TextField).last, '  Requiere visita ');
        await tester.tap(find.text('Confirmar triaje'));
        await tester.pumpAndSettle();

        final post = adapter.requests.singleWhere((r) => r.method == 'POST');
        expect(post.path, '/maintenance/requests/2/classify');
        expect(post.data, {'category': 'software', 'priority': 'high', 'notes': 'Requiere visita'});
        expect(find.textContaining('pasó a «En triaje»'), findsOneWidget);
      });

      testWidgets('las categorías se piden una vez y se buscan sin volver al servidor', (tester) async {
        await openBoard(tester);
        await openMenuFor(tester, 'En triaje');
        await tester.tap(find.byKey(const Key('field-category')));
        await tester.pumpAndSettle();
        expect(find.text('Hardware'), findsOneWidget);
        expect(find.text('Red'), findsOneWidget);

        await tester.enterText(find.byType(TextField).last, 'soft');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.text('Hardware'), findsNothing);
        expect(find.text('Software'), findsOneWidget);
        expect(adapter.requests.where((r) => r.path == '/maintenance/categories'), hasLength(1));
      });

      testWidgets('si el servidor rechaza el triaje la tarjeta se queda y se avisa', (tester) async {
        classifyHandler = (_) => errorResponse(409, code: 'ticket_classify_wrong_status');
        await openBoard(tester);
        await openMenuFor(tester, 'En triaje');
        await tester.tap(find.byKey(const Key('field-category')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hardware'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirmar triaje'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Solo se clasifican las solicitudes que esperan triaje'), findsOneWidget);
        expect(find.text('Sin clasificar'), findsOneWidget);
      });

      testWidgets('si las prioridades no cargan se puede reintentar', (tester) async {
        prioritiesHandler = (_) => errorResponse(500);
        await openBoard(tester);
        await openMenuFor(tester, 'En triaje');

        expect(find.text('Reintentar'), findsOneWidget);
        prioritiesHandler = (_) => jsonResponse(200, _priorities);
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ChoiceChip, 'Crítica'), findsOneWidget);
      });
    });

    group('pasar a «Asignado»', () {
      setUp(() => listHandler = (_) => pagedResponse([ticketJson(id: 2, status: 'submitted', title: 'Sin técnico', priority: 'low', canAct: true)]));

      FilledButton assignButton(WidgetTester tester) => tester.widget<FilledButton>(find.byType(FilledButton).last);

      testWidgets('ofrece solo técnicos activos y no se confirma sin elegir uno', (tester) async {
        await openBoard(tester);
        await openMenuFor(tester, 'Asignado');

        expect(find.text('Pasar a «Asignado»'), findsOneWidget);
        expect(find.text('Luis Técnico'), findsOneWidget);
        expect(find.text('Marta Pérez'), findsOneWidget);
        expect(find.text('No disponible'), findsOneWidget);
        expect(find.text('Ana Inactiva'), findsNothing, reason: 'una cuenta inactiva no se ofrece');
        expect(assignButton(tester).onPressed, isNull);
        expect(find.text('Asignar técnico'), findsOneWidget);
      });

      testWidgets('elegir un técnico y confirmar manda la asignación', (tester) async {
        await openBoard(tester);
        await openMenuFor(tester, 'Asignado');
        await tester.tap(find.text('Luis Técnico'));
        await tester.pumpAndSettle();
        expect(find.text('Asignar a Luis Técnico'), findsOneWidget);
        await tester.tap(find.text('Asignar a Luis Técnico'));
        await tester.pumpAndSettle();

        final post = adapter.requests.singleWhere((r) => r.method == 'POST');
        expect(post.path, '/maintenance/requests/2/assignment');
        expect(post.data, {'technician_id': 5});
        expect(find.textContaining('pasó a «Asignado»'), findsOneWidget);
      });

      testWidgets('busca en el servidor con el texto y pide los técnicos por páginas', (tester) async {
        await openBoard(tester);
        await openMenuFor(tester, 'Asignado');
        final first = adapter.requests.where((r) => r.path == '/technicians').first.queryParameters;
        expect(first, containsPair('page', 1));
        expect(first, containsPair('size', 20));

        await tester.enterText(find.byType(TextField).last, 'luis');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(adapter.requests.where((r) => r.path == '/technicians').last.queryParameters, containsPair('search', 'luis'));
      });

      testWidgets('«Ver más resultados» pide la página siguiente', (tester) async {
        techniciansHandler = (options) {
          final page = options.queryParameters['page'] as int;
          return pagedResponse([_technician(page * 10, 'Técnico $page')], page: page, totalPages: 2, total: 2);
        };
        await openBoard(tester);
        await openMenuFor(tester, 'Asignado');
        expect(find.text('Técnico 1'), findsOneWidget);

        await tester.tap(find.text('Ver más resultados'));
        await tester.pumpAndSettle();
        expect(find.text('Técnico 2'), findsOneWidget);
      });

      testWidgets('si el técnico resulta inactivo en el servidor se avisa y el ticket no cambia', (tester) async {
        assignHandler = (_) => errorResponse(409, code: 'technician_inactive');
        await openBoard(tester);
        await openMenuFor(tester, 'Asignado');
        await tester.tap(find.text('Luis Técnico'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Asignar a Luis Técnico'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Ese técnico está inactivo y no puede recibir tickets'), findsOneWidget);
        expect(find.text('Sin técnico'), findsOneWidget);
      });

      testWidgets('sin permiso para ver técnicos lo dice', (tester) async {
        techniciansHandler = (_) => errorResponse(403, code: 'forbidden');
        await openBoard(tester);
        await openMenuFor(tester, 'Asignado');

        expect(find.text('Sin permiso'), findsOneWidget);
        expect(assignButton(tester).onPressed, isNull);
      });
    });

    for (final size in const [Size(320, 568), Size(360, 640)]) {
      final name = '${size.width.toInt()}x${size.height.toInt()}';
      for (final target in const ['En triaje', 'Asignado']) {
        testWidgets('la hoja de «$target» sin overflow en $name con texto 1,3', (tester) async {
          listHandler = (_) => pagedResponse([ticketJson(id: 2, status: 'submitted', title: 'Un ticket con un título bastante largo para comprobar el ajuste de línea', priority: 'low', canAct: true)]);
          await openBoard(tester, size: size, textScale: 1.3);
          await openMenuFor(tester, target);
          expect(tester.takeException(), isNull);
          if (target == 'En triaje') {
            await tester.tap(find.byKey(const Key('field-category')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          } else {
            await tester.tap(find.text('Luis Técnico'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        });
      }
    }

    testWidgets('si el servidor rechaza el cambio, la tarjeta se queda y se avisa con un mensaje claro', (tester) async {
      statusHandler = (_) => errorResponse(409, code: 'ticket_invalid_transition');
      await openBoard(tester);
      await tester.tap(find.byTooltip('Mover a…').first);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(PopupMenuItem<String>), matching: find.text('En espera')));
      await tester.pumpAndSettle();

      expect(find.textContaining('No se pudo mover TCK-0001'), findsOneWidget);
      expect(find.text('Equipo en curso'), findsOneWidget);
    });

    testWidgets('arrastrar con pulsación larga y soltar en un estado válido lo mueve', (tester) async {
      await openBoard(tester);
      final card = find.text('Equipo en curso');
      final target = find.bySemanticsLabel(RegExp('En espera, 0 tickets'));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getCenter(card));
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 4));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      final post = adapter.requests.where((r) => r.method == 'POST' && r.path == '/maintenance/requests/1/status');
      expect(post, hasLength(1));
      expect(post.single.data, {'status': 'waiting'});
    });

    testWidgets('soltar en un estado que no es válido no manda nada', (tester) async {
      await openBoard(tester);
      final card = find.text('Equipo en curso');
      final target = find.bySemanticsLabel(RegExp('Enviado, 1 ticket'));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getCenter(card));
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('sin overflow en ${size.width.toInt()}x${size.height.toInt()} con texto 1,3', (tester) async {
        await openBoard(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ticket recién creado', () {
    testWidgets('el listado vuelve a la página 1, lo muestra primero y lo resalta unos segundos', (tester) async {
      var created = false;
      listHandler = (options) {
        final page = options.queryParameters['page'] as int? ?? 1;
        return pagedResponse([if (page == 1 && created) ticketJson(id: 99, title: 'Ticket nuevo'), ticketJson(id: 1)], page: page, totalPages: 3, total: 41);
      };
      await pump(tester);
      await tester.scrollUntilVisible(find.byTooltip('Página siguiente'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byTooltip('Página siguiente'));
      await tester.pumpAndSettle();
      expect(lastQuery()['page'], 2);

      created = true;
      unawaited(repository.create(const NewRequest(equipmentId: 12, title: 'Ticket nuevo', description: 'detalle', priority: 'medium')));
      await tester.pumpAndSettle();

      expect(lastQuery()['page'], 1);
      expect(lastQuery()['sort'], '-created_at');
      Finder inList(String text) => find.descendant(of: find.byType(TicketListCard), matching: find.text(text));
      expect(tester.getTopLeft(inList('Ticket nuevo')).dy, lessThan(tester.getTopLeft(inList('La laptop no enciende')).dy), reason: 'aparece primero');
      Finder highlighted() => find.byWidgetPredicate((w) => w is AnimatedContainer && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == AppColors.mustard.withValues(alpha: .22));
      expect(highlighted(), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(highlighted(), findsNothing);
    });

    testWidgets('limpia los filtros para que el ticket nuevo se vea', (tester) async {
      await pump(tester);
      await openFilters(tester);
      await tester.tap(find.byType(FilterTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerrado').last);
      await tester.pumpAndSettle();
      await apply(tester);
      await apply(tester);
      expect(lastQuery()['status'], 'closed');

      unawaited(repository.create(const NewRequest(equipmentId: 12, title: 'Nuevo', description: 'detalle', priority: 'medium')));
      await tester.pumpAndSettle();
      expect(lastQuery().keys, isNot(contains('status')));
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      final name = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('la tabla, la hoja de filtros y el detalle en $name', (tester) async {
        listHandler = (_) => pagedResponse([
              ticketJson(equipment: {'id': 12, 'asset_tag': 'EQ-0012', 'brand': 'Dell', 'model': 'Latitude con un nombre bastante largo'}),
              ticketJson(id: 2, title: 'Un título muy largo que debe cortarse en dos líneas y terminar con puntos suspensivos', priority: 'critical'),
            ], total: 41, totalPages: 3);
        await pump(tester, size: size, textScale: 1.3);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Filtros'));
        await tester.pumpAndSettle();
        expect(find.text('Limpiar'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Limpiar'));
        await tester.pumpAndSettle();
        await apply(tester);

        // La lista construye las tarjetas de forma perezosa: se baja hasta que haya una.
        for (var i = 0; i < 10 && find.byType(TicketListCard).evaluate().isEmpty; i++) {
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
          await tester.pumpAndSettle();
        }
        final row = find.byType(TicketListCard).first;
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.text('Detalle del ticket'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
