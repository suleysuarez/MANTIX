import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/requests/request_models.dart';
import 'package:mantix/widgets/tickets/ticket_actions.dart';

import '../../support/pump_app.dart';
import '../../support/requests_support.dart';

const _flow = [
  WorkflowStatus(status: 'assigned', order: 3, allowedTargets: ['in_progress', 'cancelled'], requires: ['technician'], canEnter: false),
  WorkflowStatus(status: 'in_progress', order: 4, allowedTargets: ['waiting', 'resolved', 'cancelled'], requires: [], canEnter: true),
  WorkflowStatus(status: 'waiting', order: 5, allowedTargets: ['in_progress', 'cancelled'], requires: [], canEnter: true),
  WorkflowStatus(status: 'resolved', order: 6, allowedTargets: ['closed', 'in_progress'], requires: ['resolution_summary'], canEnter: true),
  WorkflowStatus(status: 'cancelled', order: 8, allowedTargets: [], requires: ['reason'], canEnter: false, permission: 'solicitudes:aprobar'),
  WorkflowStatus(status: 'closed', order: 7, allowedTargets: [], requires: [], canEnter: true),
];

TicketDetail ticket(String status) => TicketDetail.fromJson(detailJson(id: 7, status: status));

void main() {
  group('availableTargets', () {
    test('desde Asignado solo ofrece iniciar el trabajo', () {
      expect(availableTargets(ticket('assigned'), _flow), ['in_progress']);
    });

    test('desde En proceso ofrece espera y resolver, en ese orden, y no cancelar aunque el flujo lo permita', () {
      expect(availableTargets(ticket('in_progress'), _flow), ['waiting', 'resolved']);
    });

    test('desde En espera ofrece reanudar; desde Resuelto, reabrir (cerrar no es del técnico)', () {
      expect(availableTargets(ticket('waiting'), _flow), ['in_progress']);
      expect(availableTargets(ticket('resolved'), _flow), ['in_progress']);
    });

    test('un estado al que la cuenta no puede entrar (canEnter falso) no se ofrece', () {
      final blocked = [for (final item in _flow) item.status == 'resolved' ? const WorkflowStatus(status: 'resolved', order: 6, allowedTargets: [], requires: ['resolution_summary'], canEnter: false) : item];
      expect(availableTargets(ticket('in_progress'), blocked), ['waiting']);
    });

    test('un estado que pide datos que la app no sabe pedir (técnico, categoría) no se ofrece', () {
      final odd = [for (final item in _flow) item.status == 'waiting' ? const WorkflowStatus(status: 'waiting', order: 5, allowedTargets: [], requires: ['technician'], canEnter: true) : item];
      expect(availableTargets(ticket('in_progress'), odd), ['resolved']);
    });

    test('sin flujo cargado no hay acciones', () {
      expect(availableTargets(ticket('in_progress'), const []), isEmpty);
    });
  });

  test('los nombres de los botones dicen qué hacen según de dónde viene', () {
    expect(actionLabel('assigned', 'in_progress'), 'Iniciar trabajo');
    expect(actionLabel('waiting', 'in_progress'), 'Reanudar trabajo');
    expect(actionLabel('resolved', 'in_progress'), 'Reabrir ticket');
    expect(actionLabel('in_progress', 'waiting'), 'Poner en espera');
    expect(actionLabel('in_progress', 'resolved'), 'Resolver ticket');
  });

  group('TicketActions', () {
    late List<(String, String?, String?)> sent;

    setUp(() => sent = []);

    Future<void> open(WidgetTester tester, {String status = 'in_progress', bool changing = false, List<WorkflowStatus> workflow = _flow, double textScale = 1}) => pumpApp(
          tester,
          SingleChildScrollView(
            child: TicketActions(ticket: ticket(status), workflow: workflow, changing: changing, onChange: (target, {notes, resolutionSummary}) => sent.add((target, notes, resolutionSummary))),
          ),
          textScale: textScale,
        );

    testWidgets('en proceso muestra «Poner en espera» y «Resolver ticket»', (tester) async {
      await open(tester);

      expect(find.text('Acciones'), findsOneWidget);
      expect(find.text('Estado actual: En proceso'), findsOneWidget);
      expect(find.text('Poner en espera'), findsOneWidget);
      expect(find.text('Resolver ticket'), findsOneWidget);
      expect(find.text('Iniciar trabajo'), findsNothing);
    });

    testWidgets('sin a dónde pasar no pinta nada', (tester) async {
      await open(tester, workflow: const []);

      expect(find.text('Acciones'), findsNothing);
    });

    testWidgets('resolver exige escribir cómo se resolvió y entrega el texto sin espacios sobrantes', (tester) async {
      await open(tester);

      await tester.tap(find.text('Resolver ticket'));
      await tester.pumpAndSettle();
      expect(find.text('Cómo se resolvió'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Resolver'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe cómo se resolvió el ticket.'), findsOneWidget);
      expect(sent, isEmpty, reason: 'sin texto no se manda nada');

      await tester.enterText(find.byType(TextField), '  Cambié la fuente de poder  ');
      await tester.pump();
      expect(find.text('Escribe cómo se resolvió el ticket.'), findsNothing, reason: 'el error se quita al escribir');
      await tester.tap(find.widgetWithText(FilledButton, 'Resolver'));
      await tester.pumpAndSettle();

      expect(sent, [('resolved', null, 'Cambié la fuente de poder')]);
    });

    testWidgets('cancelar el diálogo no cambia nada', (tester) async {
      await open(tester);

      await tester.tap(find.text('Resolver ticket'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(sent, isEmpty);
    });

    testWidgets('poner en espera pide una nota opcional y se puede confirmar sin escribirla', (tester) async {
      await open(tester);

      await tester.tap(find.text('Poner en espera'));
      await tester.pumpAndSettle();
      expect(find.text('Nota (opcional)'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      expect(sent, [('waiting', null, null)]);
    });

    testWidgets('con una nota la entrega', (tester) async {
      await open(tester);

      await tester.tap(find.text('Poner en espera'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Falta el repuesto');
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      expect(sent, [('waiting', 'Falta el repuesto', null)]);
    });

    testWidgets('mientras cambia deshabilita los botones y muestra el avance', (tester) async {
      await open(tester, changing: true);

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('los botones miden al menos 48 px y no se desbordan con texto 1,3 en 320 px', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      await open(tester, textScale: 1.3);

      expect(tester.getSize(find.widgetWithText(FilledButton, 'Resolver ticket')).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.widgetWithText(OutlinedButton, 'Poner en espera')).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  });
}
