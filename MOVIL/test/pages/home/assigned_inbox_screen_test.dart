import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/home/assigned_inbox_screen.dart';
import 'package:mantix/widgets/maintenance/maintenance_cards.dart';
import 'package:mantix/widgets/tickets/ticket_cards.dart';

import '../../support/fakes.dart';
import '../../support/maintenance_support.dart';
import '../../support/requests_support.dart';

const _technician = {'tickets:ver', 'tickets:ver_asignados', 'mantenimiento:ver'};
const _withoutMaintenance = {'tickets:ver', 'tickets:ver_asignados'};
const _canChange = {'tickets:ver', 'tickets:ver_asignados', 'mantenimiento:ver', 'tickets:cambiar_estado'};

/// El flujo de estados que el servidor le da a un técnico: puede entrar a En proceso, En espera y
/// Resuelto (que pide la resolución), pero no a Cancelado.
const _workflow = [
  {'status': 'assigned', 'order': 3, 'allowed_targets': ['in_progress', 'cancelled'], 'requires': ['technician'], 'can_enter': false, 'in_queue': true},
  {'status': 'in_progress', 'order': 4, 'allowed_targets': ['waiting', 'resolved', 'cancelled'], 'requires': <String>[], 'can_enter': true, 'in_queue': false},
  {'status': 'waiting', 'order': 5, 'allowed_targets': ['in_progress', 'cancelled'], 'requires': <String>[], 'can_enter': true, 'in_queue': false},
  {'status': 'resolved', 'order': 6, 'allowed_targets': ['closed', 'in_progress'], 'requires': ['resolution_summary'], 'can_enter': true, 'in_queue': false},
  {'status': 'cancelled', 'order': 8, 'allowed_targets': <String>[], 'requires': ['reason'], 'can_enter': false, 'in_queue': false},
];

String _utc(DateTime local) => local.toUtc().toIso8601String();

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) ticketsHandler;
  late ResponseBody Function(RequestOptions) calendarHandler;
  late String detailStatus;
  final today = DateTime(2026, 10, 25, 10);

  setUp(() {
    detailStatus = 'in_progress';
    ticketsHandler = (options) {
      final query = options.queryParameters;
      if (query['size'] == 1) {
        final total = query['priority'] != null ? 2 : (query['status'] == 'in_progress' ? 3 : 7);
        return pagedResponse([ticketJson()], total: total);
      }
      return pagedResponse([
        ticketJson(id: 1, status: 'assigned', title: 'La laptop no enciende'),
        ticketJson(id: 2, status: 'in_progress', title: 'Sin red en contabilidad', priority: 'critical'),
      ], total: 7);
    };
    calendarHandler = (_) => calendarResponse([
          calendarEventJson(id: 4, title: 'Revisión de UPS', kind: 'overdue', at: _utc(DateTime(2026, 10, 6, 12))),
          calendarEventJson(id: 5, title: 'Limpieza de servidor', at: _utc(DateTime(2026, 10, 28, 12)), tag: 'SRV-0001'),
        ]);
    adapter = FakeAdapter((options) {
      final path = options.path;
      if (path == '/maintenance/requests') return ticketsHandler(options);
      if (path == '/maintenance/calendar') return calendarHandler(options);
      if (path.endsWith('/attachments')) return jsonResponse(200, <Object?>[]);
      if (path == '/maintenance/requests/workflow') return jsonResponse(200, _workflow);
      if (path.endsWith('/status')) {
        detailStatus = 'resolved';
        return jsonResponse(200, detailJson(id: 1, status: 'resolved'));
      }
      if (path.startsWith('/maintenance/requests/')) return jsonResponse(200, detailJson(id: 1, status: detailStatus));
      return errorResponse(404);
    });
  });

  Future<void> open(WidgetTester tester, {Set<String> permissions = _technician, Size size = const Size(1000, 3000), double textScale = 1}) async {
    await pumpScreen(tester, AssignedInboxScreen(clock: () => today), adapter, permissions: permissions, size: size, textScale: textScale);
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el título, las cuatro cifras, sus tickets y sus mantenimientos', (tester) async {
    await open(tester);

    expect(find.text('Mi bandeja de trabajo'), findsOneWidget);
    for (final label in ['TICKETS ABIERTOS', 'EN PROCESO', 'URGENTES', 'MANT. VENCIDOS']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Abiertos 7, en proceso 3, urgentes 2 (totales del servidor) y 1 mantenimiento vencido.
    Finder inCard(String label, String value) => find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Material)).first, matching: find.text(value));
    expect(inCard('TICKETS ABIERTOS', '7'), findsOneWidget);
    expect(inCard('EN PROCESO', '3'), findsOneWidget);
    expect(inCard('URGENTES', '2'), findsOneWidget);
    expect(inCard('MANT. VENCIDOS', '1'), findsOneWidget);

    expect(find.text('Mis tickets asignados'), findsOneWidget);
    expect(find.text('La laptop no enciende'), findsOneWidget);
    expect(find.text('Sin red en contabilidad'), findsOneWidget);
    expect(find.textContaining('Mostrando'), findsNothing, reason: 'ya no hay un contador: está el paginador');

    expect(find.text('Mis mantenimientos'), findsOneWidget);
    expect(find.byType(MaintenanceEventCard), findsNWidgets(2));
    expect(find.text('Revisión de UPS'), findsOneWidget);
  });

  testWidgets('pide solo lo abierto y lo urgente, y el calendario una vez', (tester) async {
    await open(tester);

    final requests = adapter.requests.where((r) => r.path == '/maintenance/requests').toList();
    expect(requests.every((r) => (r.queryParameters['status'] as String).contains('in_progress')), isTrue);
    expect(requests.any((r) => r.queryParameters['priority'] == 'critical,high'), isTrue);
    expect(adapter.requests.where((r) => r.path == '/maintenance/calendar'), hasLength(1));
  });

  testWidgets('sin permiso de mantenimiento no hay sección ni se pide el calendario', (tester) async {
    await open(tester, permissions: _withoutMaintenance);

    expect(find.text('Mis mantenimientos'), findsNothing);
    expect(adapter.requests.where((r) => r.path == '/maintenance/calendar'), isEmpty);
    expect(find.text('MANT. VENCIDOS'), findsOneWidget);
    expect(find.text('—'), findsOneWidget, reason: 'esa cifra no está disponible sin el permiso');
  });

  testWidgets('sin tickets asignados lo dice', (tester) async {
    ticketsHandler = (_) => pagedResponse(const []);
    await open(tester);

    expect(find.text('No tienes tickets asignados'), findsOneWidget);
    expect(find.byType(TicketListCard), findsNothing);
  });

  testWidgets('si no cargan los tickets sale el error con reintento y los mantenimientos siguen', (tester) async {
    ticketsHandler = (_) => errorResponse(500);
    await open(tester);

    expect(find.text('No pudimos cargar tus tickets'), findsOneWidget);
    expect(find.text('Limpieza de servidor'), findsOneWidget, reason: 'cada sección falla por separado');

    ticketsHandler = (_) => pagedResponse([ticketJson(id: 9, title: 'Ticket recuperado')]);
    await tester.tap(find.text('Reintentar').first);
    await tester.pumpAndSettle();
    expect(find.text('Ticket recuperado'), findsOneWidget);
  });

  testWidgets('tocar un ticket abre su detalle', (tester) async {
    await open(tester);

    await tester.tap(find.text('La laptop no enciende'));
    await tester.pumpAndSettle();

    expect(find.text('Detalle del ticket'), findsOneWidget);
  });

  group('resolver desde el detalle', () {
    void ownTickets() => ticketsHandler = (options) => options.queryParameters['size'] == 1
        ? pagedResponse([ticketJson()], total: 1)
        : pagedResponse([ticketJson(id: 1, status: 'in_progress', title: 'La laptop no enciende', canAct: true)], total: 1);

    testWidgets('el técnico con permiso ve las acciones, escribe cómo se resolvió y el ticket pasa a Resuelto', (tester) async {
      ownTickets();
      await open(tester, permissions: _canChange);

      await tester.tap(find.text('La laptop no enciende'));
      await tester.pumpAndSettle();
      expect(find.text('Acciones'), findsOneWidget);
      expect(find.text('Poner en espera'), findsOneWidget);
      expect(find.text('Cancelar ticket'), findsNothing, reason: 'cancelar no es del técnico');

      await tester.tap(find.text('Resolver ticket'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Cambié la fuente de poder');
      await tester.tap(find.widgetWithText(FilledButton, 'Resolver'));
      await tester.pumpAndSettle();

      final change = adapter.requests.singleWhere((r) => r.path == '/maintenance/requests/1/status');
      expect(change.method, 'POST');
      expect(change.data, {'status': 'resolved', 'resolution_summary': 'Cambié la fuente de poder'});
      expect(find.text('Ticket actualizado: Resuelto.'), findsOneWidget);
      expect(find.text('Cambié la fuente de poder'), findsNothing, reason: 'el diálogo se cerró');
      expect(find.text('Resolver ticket'), findsNothing, reason: 'ya está resuelto: no se ofrece de nuevo');
    });

    testWidgets('si el servidor lo rechaza muestra el motivo y deja los botones', (tester) async {
      ownTickets();
      final base = adapter;
      adapter = FakeAdapter((options) => options.path.endsWith('/status') ? errorResponse(409, code: 'ticket_invalid_transition') : base.handler(options));
      await open(tester, permissions: _canChange);

      await tester.tap(find.text('La laptop no enciende'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poner en espera'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Ticket actualizado'), findsNothing);
      expect(find.text('Resolver ticket'), findsOneWidget);
    });

    testWidgets('sin tickets:cambiar_estado el detalle es solo de lectura', (tester) async {
      ownTickets();
      await open(tester);

      await tester.tap(find.text('La laptop no enciende'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle del ticket'), findsOneWidget);
      expect(find.text('Acciones'), findsNothing);
      expect(adapter.requests.where((r) => r.path == '/maintenance/requests/workflow'), isEmpty, reason: 'ni siquiera se pide el flujo');
    });

    testWidgets('un ticket que no es suyo (can_act falso) tampoco ofrece acciones', (tester) async {
      await open(tester, permissions: _canChange);

      await tester.tap(find.text('La laptop no enciende'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle del ticket'), findsOneWidget);
      expect(find.text('Acciones'), findsNothing);
    });
  });

  testWidgets('los tickets se paginan de 10 en 10 y cada página sustituye a la anterior', (tester) async {
    ticketsHandler = (options) {
      final query = options.queryParameters;
      if (query['size'] == 1) return pagedResponse([ticketJson()], total: 14);
      final page = query['page'] as int;
      final ids = page == 1 ? [for (var i = 1; i <= 10; i++) i] : [11, 12, 13, 14];
      return pagedResponse([for (final id in ids) ticketJson(id: id, title: 'Ticket $id')], page: page, totalPages: 2, total: 14);
    };
    await open(tester);

    expect(find.byType(TicketListCard), findsNWidgets(10));
    expect(adapter.requests.where((r) => r.path == '/maintenance/requests' && r.queryParameters['size'] != 1).first.queryParameters['size'], 10);

    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();

    expect(find.byType(TicketListCard), findsNWidgets(4));
    expect(find.text('Ticket 11'), findsOneWidget);
    expect(find.text('Ticket 1'), findsNothing, reason: 'la página nueva sustituye a la anterior');
    expect(find.byTooltip('Página anterior'), findsOneWidget);
  });

  testWidgets('los mantenimientos se paginan de 5 en 5 y «Todo» vuelve a la primera página', (tester) async {
    calendarHandler = (_) => calendarResponse([
          for (var i = 1; i <= 7; i++) calendarEventJson(id: 20 + i, title: 'Plan $i', at: _utc(DateTime(2026, 10, 25 + i, 12)), tag: 'SRV-$i'),
        ]);
    await open(tester);

    expect(find.byType(MaintenanceEventCard), findsNWidgets(5));
    expect(find.text('Plan 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.byType(MaintenanceEventCard), findsNWidgets(2));
    expect(find.text('Plan 6'), findsOneWidget);
    expect(find.text('Plan 1'), findsNothing);

    await tester.tap(find.text('Próx. 30 días'));
    await tester.pumpAndSettle();
    expect(find.byType(MaintenanceEventCard), findsNWidgets(5), reason: 'cambiar el rango vuelve a la primera página');
    expect(find.text('Plan 1'), findsOneWidget);
  });

  for (final size in const [Size(320, 568), Size(360, 640)]) {
    testWidgets('las cuatro cifras miden lo mismo y no hay overflow en ${size.width.toInt()}×${size.height.toInt()} con texto 1,3', (tester) async {
      await open(tester, size: size, textScale: 1.3);

      final sizes = [
        for (final label in ['TICKETS ABIERTOS', 'EN PROCESO', 'URGENTES', 'MANT. VENCIDOS']) tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(Material)).first),
      ];
      expect(sizes.toSet(), hasLength(1), reason: '$sizes');
      expect(tester.takeException(), isNull);
    });
  }
}
