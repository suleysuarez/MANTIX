import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/theme/app_colors.dart';
import 'package:mantix/models/requests/request_models.dart';
import 'package:mantix/pages/requests/my_requests_screen.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';
import 'package:mantix/widgets/shared/app_chip.dart';
import 'package:mantix/widgets/shared/skeleton.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

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
    expect(find.textContaining('Equipo tecnológico', findRichText: true), findsWidgets, reason: 'el formulario se abre en una hoja');
    expect(find.text('Aún no tienes solicitudes'), findsOneWidget, reason: 'la pantalla de fondo sigue');
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

  testWidgets('con más páginas, la paginación numerada pide la página y la sustituye', (tester) async {
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

    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud de la página 1'), findsNothing);
    expect(find.text('Solicitud de la página 2'), findsOneWidget);
    expect(adapter.requests.last.queryParameters['page'], 2);
  });

  testWidgets('si falla la segunda página la primera sigue visible y se puede volver a pedir', (tester) async {
    var failSecond = true;
    final adapter = FakeAdapter((options) {
      final page = options.queryParameters['page'] as int;
      if (page == 2 && failSecond) return errorResponse(500);
      return pagedResponse([ticketJson(id: page, title: 'Solicitud de la página $page')], page: page, totalPages: 2, total: 2);
    });
    await pumpScreen(tester, const MyRequestsScreen(), adapter);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud de la página 1'), findsOneWidget);

    failSecond = false;
    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud de la página 2'), findsOneWidget);
  });
  testWidgets('trae el encabezado de los módulos con el título «Mis solicitudes»', (tester) async {
    final adapter = FakeAdapter((_) => pagedResponse([]));
    await pumpScreen(tester, const MyRequestsScreen(), adapter);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Notificaciones'), findsOneWidget);
    expect(find.byTooltip('Perfil'), findsOneWidget);
    expect(find.text('Mis solicitudes'), findsOneWidget);
  });

  group('solicitud recién creada', () {
    testWidgets('sin filtro, página 1, la más nueva primero y resaltada unos segundos', (tester) async {
      var created = false;
      final adapter = FakeAdapter((options) {
        if (options.method == 'POST') return jsonResponse(201, detailJson(id: 99));
        final page = options.queryParameters['page'] as int? ?? 1;
        return pagedResponse([if (page == 1 && created) ticketJson(id: 99, title: 'Solicitud nueva'), ticketJson(id: 1)], page: page, totalPages: 2, total: 22);
      });
      await pumpScreen(tester, const MyRequestsScreen(), adapter);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Cerrado'));
      await tester.pumpAndSettle();
      expect(adapter.requests.last.queryParameters['status'], 'closed');

      created = true;
      final repository = RepositoryProvider.of<RequestsRepository>(tester.element(find.byType(MyRequestsScreen)));
      unawaited(repository.create(const NewRequest(equipmentId: 12, title: 'Solicitud nueva', description: 'detalle', priority: 'medium')));
      await tester.pumpAndSettle();

      final list = adapter.requests.where((r) => r.method == 'GET' && r.path == '/maintenance/requests').last.queryParameters;
      expect(list['page'], 1);
      expect(list['sort'], '-created_at');
      expect(list.containsKey('status'), isFalse, reason: 'se quita el filtro para que se vea');
      expect(tester.getTopLeft(find.text('Solicitud nueva')).dy, lessThan(tester.getTopLeft(find.text('La laptop no enciende')).dy));
      Finder highlighted() => find.byWidgetPredicate((w) => w is Card && w.color == AppColors.mustard.withValues(alpha: .22));
      expect(highlighted(), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(highlighted(), findsNothing);
    });
  });

  group('sin overflow en pantallas pequeñas con texto 1,3', () {
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('en ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final adapter = FakeAdapter((_) => pagedResponse([ticketJson(title: 'Un título largo de una solicitud que ocupa varias líneas en pantallas estrechas')], total: 41, totalPages: 3));
        await pumpScreen(tester, const MyRequestsScreen(), adapter, size: size, textScale: 1.3);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
