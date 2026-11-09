import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/pages/tickets/tickets_screen.dart';
import 'package:mantix/widgets/shared/app_chip.dart';

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

    expect(find.text('Gestión de tickets'), findsOneWidget);
    expect(find.text('3 tickets'), findsOneWidget);
    expect(find.text('La laptop no enciende'), findsOneWidget);
    expect(find.text('Ventilador con ruido'), findsOneWidget);
    expect(find.widgetWithText(StatusChip, 'Enviado'), findsOneWidget);
    expect(find.widgetWithText(PriorityChip, 'Crítica'), findsOneWidget);
  });

  testWidgets('filtra por grupo de estado desde el servidor', (tester) async {
    final adapter = FakeAdapter((options) => pagedResponse([ticketJson()]));
    await pumpScreen(tester, const TicketsScreen(), adapter);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Enviados'));
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
    expect(find.widgetWithText(ChoiceChip, 'Enviado'), findsOneWidget);
    expect(find.text('La laptop no enciende'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Resuelto'));
    await tester.pumpAndSettle();
    expect(find.text('Equipo reparado'), findsOneWidget);
    expect(find.text('La laptop no enciende'), findsNothing);
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
