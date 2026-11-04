import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/features/requests/presentation/my_requests_screen.dart';
import 'package:mantix/shared/app_chip.dart';
import 'package:mantix/shared/skeleton.dart';

import '../../support/fakes.dart';
import 'support.dart';

void main() {
  testWidgets('muestra el esqueleto mientras carga y luego las solicitudes', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([
          ticketJson(),
          ticketJson(id: 2, status: 'resolved', title: 'Mouse roto', priority: 'low'),
        ]));
    await pumpScreen(tester, const MyRequestsScreen(), adapter);
    expect(find.byType(SkeletonList), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(SkeletonList), findsNothing);
    expect(find.text('La laptop no enciende'), findsOneWidget);
    expect(find.text('Mouse roto'), findsOneWidget);
    expect(find.widgetWithText(StatusChip, 'Enviado'), findsOneWidget);
    expect(find.widgetWithText(PriorityChip, 'Baja'), findsOneWidget);
  });

  testWidgets('sin solicitudes muestra el estado vacío con acción para crear', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([]));
    await pumpScreen(tester, const MyRequestsScreen(), adapter);
    await tester.pumpAndSettle();

    expect(find.text('Aún no tienes solicitudes'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Nueva solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('pantalla nueva'), findsOneWidget);
  });

  testWidgets('sin permiso de crear no hay botón ni acción de crear', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([]));
    await pumpScreen(tester, const MyRequestsScreen(), adapter, permissions: const {'solicitudes:ver'});
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Nueva solicitud'), findsNothing);
  });

  testWidgets('un error muestra el mensaje sin detalles internos y reintenta', (tester) async {
    var fail = true;
    final adapter = FakeAdapter((_) => fail ? errorResponse(500) : pagedResponse([ticketJson()]));
    await pumpScreen(tester, const MyRequestsScreen(), adapter);
    await tester.pumpAndSettle();

    expect(find.text('Algo salió mal'), findsOneWidget);
    expect(find.textContaining('detalle interno'), findsNothing);

    fail = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('La laptop no enciende'), findsOneWidget);
  });

  testWidgets('elegir un estado pide solo ese estado', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([ticketJson()]));
    await pumpScreen(tester, const MyRequestsScreen(), adapter);
    await tester.pumpAndSettle();
    expect(adapter.requests.last.queryParameters.containsKey('status'), isFalse);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Resuelto'));
    await tester.pumpAndSettle();
    expect(adapter.requests.last.queryParameters['status'], 'resolved');
  });

  testWidgets('con un filtro sin resultados el vacío lo dice y no ofrece crear', (tester) async {
    final adapter = FakeAdapter((options) =>
        options.queryParameters.containsKey('status') ? pagedResponse([]) : pagedResponse([ticketJson()]));
    await pumpScreen(tester, const MyRequestsScreen(), adapter);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Cerrado'));
    await tester.pumpAndSettle();
    expect(find.text('No hay solicitudes con este estado'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Nueva solicitud'), findsNothing);
  });

  testWidgets('toca una solicitud para abrir su detalle', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([ticketJson(id: 5)]));
    await pumpScreen(tester, const MyRequestsScreen(), adapter);
    await tester.pumpAndSettle();

    await tester.tap(find.text('La laptop no enciende'));
    await tester.pumpAndSettle();
    expect(find.text('detalle 5'), findsOneWidget);
  });

  testWidgets('con más páginas, «Cargar más» pide la siguiente y la añade', (tester) async {
    final adapter = FakeAdapter((options) {
      final page = options.queryParameters['page'] as int;
      return pagedResponse(
        [ticketJson(id: page, title: 'Solicitud de la página $page')],
        page: page,
        totalPages: 2,
        total: 2,
      );
    });
    await pumpScreen(tester, const MyRequestsScreen(), adapter);
    await tester.pumpAndSettle();
    expect(find.text('Solicitud de la página 1'), findsOneWidget);

    await tester.tap(find.text('Cargar más'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud de la página 1'), findsOneWidget);
    expect(find.text('Solicitud de la página 2'), findsOneWidget);
    expect(find.text('Cargar más'), findsNothing);
  });

  testWidgets('si falla la segunda página la primera sigue visible y se puede reintentar', (tester) async {
    var failSecond = true;
    final adapter = FakeAdapter((options) {
      final page = options.queryParameters['page'] as int;
      if (page == 2 && failSecond) return errorResponse(500);
      return pagedResponse([ticketJson(id: page, title: 'Solicitud de la página $page')], page: page, totalPages: 2, total: 2);
    });
    await pumpScreen(tester, const MyRequestsScreen(), adapter);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cargar más'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud de la página 1'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    failSecond = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud de la página 2'), findsOneWidget);
  });
}
