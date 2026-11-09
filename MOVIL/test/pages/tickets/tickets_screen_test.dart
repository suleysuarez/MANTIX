import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/tickets/tickets_screen.dart';
import 'package:mantix/widgets/tickets/ticket_cards.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  testWidgets('muestra el resumen y los tickets que devuelve la API', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([
          ticketJson(),
          ticketJson(id: 2, status: 'in_progress', title: 'Ventilador con ruido', priority: 'critical'),
          ticketJson(id: 3, status: 'resolved', title: 'Error de pantalla', priority: 'low'),
        ], total: 3));
    await pumpScreen(tester, const TicketsScreen(), adapter);
    await tester.pumpAndSettle();

    expect(find.text('GESTIÓN DE TICKETS'), findsOneWidget);
    expect(find.text('3 tickets'), findsOneWidget);
    // El ticket de prioridad alta también aparece en «Requieren atención prioritaria».
    expect(find.text('Requieren atención prioritaria'), findsOneWidget);
    expect(find.text('La laptop no enciende'), findsWidgets);
    expect(find.text('Ventilador con ruido'), findsWidgets);
    expect(find.text('Enviado'), findsWidgets);
    expect(find.widgetWithText(PriorityPill, 'Crítica'), findsWidgets);
  });

  testWidgets('filtra por grupo de estado desde el servidor', (tester) async {
    final adapter = FakeAdapter((options) => pagedResponse([ticketJson()]));
    await pumpScreen(tester, const TicketsScreen(), adapter);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filtros'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviados').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(adapter.requests.last.path, '/maintenance/requests');
    expect(adapter.requests.last.queryParameters['status'], 'submitted,triaged');
  });

  testWidgets('envía la búsqueda al servidor al confirmar el campo', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([ticketJson()]));
    await pumpScreen(tester, const TicketsScreen(), adapter);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ventilador');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(adapter.requests.last.queryParameters['search'], 'ventilador');
  });

  testWidgets('Kanban móvil permite cambiar la columna sin comprimir el tablero', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([
          ticketJson(),
          ticketJson(id: 2, status: 'resolved', title: 'Equipo reparado'),
        ]));
    await pumpScreen(tester, const TicketsScreen(), adapter);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kanban'));
    await tester.pumpAndSettle();
    expect(find.text('1/4'), findsOneWidget);
    expect(find.text('Enviado'), findsWidgets);
    expect(find.text('La laptop no enciende'), findsWidgets);

    // Las columnas se deslizan de dos en dos: «Resuelto» está en la tercera página.
    await tester.tap(find.byTooltip('Columnas siguientes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Columnas siguientes'));
    await tester.pumpAndSettle();
    expect(find.text('3/4'), findsOneWidget);
    expect(find.text('Resuelto'), findsWidgets);
    expect(find.text('Equipo reparado'), findsOneWidget);
  });

  testWidgets('la paginación numerada pide la página elegida', (tester) async {
    final adapter = FakeAdapter((options) {
      final page = options.queryParameters['page'] as int? ?? 1;
      return pagedResponse([ticketJson(id: page, title: 'Ticket de la página $page')], page: page, totalPages: 3, total: 41);
    });
    await pumpScreen(tester, const TicketsScreen(), adapter);
    await tester.pumpAndSettle();

    expect(find.text('Mostrando 1 – 1 de 41 tickets'), findsOneWidget);
    await tester.scrollUntilVisible(find.byTooltip('Página 3'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byTooltip('Página 3'));
    await tester.pumpAndSettle();

    expect(adapter.requests.last.queryParameters['page'], 3);
    expect(find.text('Ticket de la página 3'), findsWidgets);
    expect(find.text('Cargar más tickets'), findsNothing);
  });

  testWidgets('muestra el botón de creación solo con permiso', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([]));
    await pumpScreen(tester, const TicketsScreen(), adapter);
    await tester.pumpAndSettle();
    expect(find.text('Nuevo ticket'), findsOneWidget);

    final restricted = FakeAdapter((_) => pagedResponse([]));
    await pumpScreen(tester, const TicketsScreen(), restricted, permissions: const {'tickets:ver'});
    await tester.pumpAndSettle();
    expect(find.text('Nuevo ticket'), findsNothing);
  });
}
