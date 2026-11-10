import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/queue/triage_actions_bloc.dart';
import 'package:mantix/models/queue/queue_workflow.dart';
import 'package:mantix/models/requests/request_models.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

QueueWorkflow _flow({bool canEnterAssigned = true, bool canEnterCancelled = true}) => QueueWorkflow([
      for (final json in [
        {'status': 'submitted', 'order': 1, 'allowed_targets': ['triaged', 'assigned', 'cancelled', 'in_progress'], 'requires': [], 'can_enter': true, 'in_queue': true},
        {'status': 'triaged', 'order': 2, 'allowed_targets': ['assigned', 'cancelled'], 'requires': ['category', 'priority'], 'can_enter': true, 'in_queue': true},
        {'status': 'assigned', 'order': 3, 'allowed_targets': ['cancelled', 'in_progress'], 'requires': ['technician'], 'can_enter': canEnterAssigned, 'in_queue': true},
        {'status': 'in_progress', 'order': 4, 'allowed_targets': [], 'requires': [], 'can_enter': true, 'in_queue': false},
        {'status': 'cancelled', 'order': 9, 'allowed_targets': [], 'requires': ['reason'], 'can_enter': canEnterCancelled, 'in_queue': false},
      ])
        WorkflowStatus.fromJson(json),
    ]);

TicketListItem _ticket({int id = 1, String status = 'submitted', bool canAct = true}) => TicketListItem.fromJson(ticketJson(id: id, status: status, canAct: canAct));

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;

  setUp(() {
    handler = (_) => jsonResponse(200, detailJson());
    adapter = FakeAdapter((options) => handler(options));
  });

  TriageActionsBloc build() => TriageActionsBloc(repository: RequestsRepository(dioWith(adapter)));

  /// Manda el evento y devuelve los resultados que emitió, en orden.
  Future<List<TriageOutcome>> run(TriageActionsBloc bloc, TriageMoveRequested event, {int count = 1}) async {
    final outcomes = <TriageOutcome>[];
    final sub = bloc.stream.listen((s) {
      if (s.outcome != null && (outcomes.isEmpty || outcomes.last.id != s.outcome!.id)) outcomes.add(s.outcome!);
    });
    bloc.add(event);
    while (outcomes.length < count) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await sub.cancel();
    return outcomes;
  }

  List<RequestOptions> posts() => adapter.requests.where((r) => r.method == 'POST').toList();

  group('movimientos válidos, cada uno con su endpoint', () {
    test('a «Clasificadas» usa classify con categoría y prioridad', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcomes = await run(bloc, TriageMoveRequested(_ticket(), 'triaged', workflow: _flow(), category: 'software', priority: 'high', notes: 'Visita'), count: 2);

      expect(outcomes.map((o) => o.kind), [TriageOutcomeKind.started, TriageOutcomeKind.succeeded]);
      expect(posts().single.path, '/maintenance/requests/1/classify');
      expect(posts().single.data, {'category': 'software', 'priority': 'high', 'notes': 'Visita'});
      expect(outcomes.last.message, 'TCK-0001 pasó a «Clasificadas».');
      expect(bloc.state.inFlight, isEmpty);
    });

    test('a «Asignadas» usa assignment con el técnico', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcomes = await run(bloc, TriageMoveRequested(_ticket(), 'assigned', workflow: _flow(), technicianId: 5), count: 2);

      expect(posts().single.path, '/maintenance/requests/1/assignment');
      expect(posts().single.data, {'technician_id': 5});
      expect(outcomes.last.message, 'TCK-0001 pasó a «Asignadas».');
    });

    test('rechazar desde la cola usa reject con el motivo y no el cambio de estado', () async {
      final bloc = build();
      addTearDown(bloc.close);

      final outcomes = await run(bloc, TriageMoveRequested(_ticket(status: 'triaged'), 'cancelled', workflow: _flow(), reason: '  Duplicada de TCK-9 '), count: 2);

      expect(posts().single.path, '/maintenance/requests/1/reject');
      expect(posts().single.data, {'reason': 'Duplicada de TCK-9'});
      expect(outcomes.last.message, 'TCK-0001 fue rechazada.');
    });

    test('un destino sin endpoint propio usa el cambio de estado', () async {
      final bloc = build();
      addTearDown(bloc.close);

      await run(bloc, TriageMoveRequested(_ticket(), 'in_progress', workflow: _flow()), count: 2);

      expect(posts().single.path, '/maintenance/requests/1/status');
      expect(posts().single.data, {'status': 'in_progress'});
    });
  });

  group('lo que ni siquiera se pide al servidor', () {
    Future<TriageOutcome> blocked(TriageMoveRequested event) async {
      final bloc = build();
      addTearDown(bloc.close);
      final outcome = (await run(bloc, event)).single;
      expect(outcome.kind, TriageOutcomeKind.blocked);
      expect(outcome.isError, isTrue);
      expect(adapter.requests, isEmpty, reason: 'no hubo ninguna petición');
      expect(bloc.state.inFlight, isEmpty);
      return outcome;
    }

    test('movimiento que el flujo no permite', () async {
      final outcome = await blocked(TriageMoveRequested(_ticket(status: 'assigned'), 'triaged', workflow: _flow(), category: 'a', priority: 'high'));
      expect(outcome.message, 'Ese cambio de estado no está permitido para esta solicitud.');
    });

    test('sin permiso para entrar en el destino lo dice con el nombre del estado', () async {
      final outcome = await blocked(TriageMoveRequested(_ticket(), 'assigned', workflow: _flow(canEnterAssigned: false), technicianId: 5));
      expect(outcome.message, 'Tu rol no puede pasar solicitudes a «Asignadas».');
    });

    test('sin permiso para rechazar', () async {
      final outcome = await blocked(TriageMoveRequested(_ticket(), 'cancelled', workflow: _flow(canEnterCancelled: false), reason: 'Motivo claro'));
      expect(outcome.message, contains('Tu rol no puede pasar solicitudes'));
    });

    test('una solicitud sobre la que no puede actuar', () async {
      final outcome = await blocked(TriageMoveRequested(_ticket(canAct: false), 'triaged', workflow: _flow(), category: 'a', priority: 'high'));
      expect(outcome.message, contains('permiso'));
    });

    test('rechazar sin motivo o con motivo corto', () async {
      expect((await blocked(TriageMoveRequested(_ticket(), 'cancelled', workflow: _flow()))).message, 'Escribe el motivo del rechazo.');
      adapter.requests.clear();
      expect((await blocked(TriageMoveRequested(_ticket(), 'cancelled', workflow: _flow(), reason: ' abc '))).message, 'El motivo debe tener al menos 5 caracteres.');
    });

    test('clasificar sin categoría, sin prioridad o sin ambas', () async {
      expect((await blocked(TriageMoveRequested(_ticket(), 'triaged', workflow: _flow(), priority: 'high'))).message, 'Elige la categoría.');
      expect((await blocked(TriageMoveRequested(_ticket(), 'triaged', workflow: _flow(), category: 'a'))).message, 'Elige la prioridad.');
      expect((await blocked(TriageMoveRequested(_ticket(), 'triaged', workflow: _flow()))).message, 'Elige la categoría y la prioridad.');
    });

    test('asignar sin técnico', () async {
      expect((await blocked(TriageMoveRequested(_ticket(), 'assigned', workflow: _flow()))).message, 'Elige un técnico.');
    });
  });

  group('errores del servidor', () {
    test('un técnico inactivo se explica con su mensaje y avisa para devolver la tarjeta', () async {
      handler = (_) => errorResponse(409, code: 'technician_inactive');
      final bloc = build();
      addTearDown(bloc.close);

      final outcomes = await run(bloc, TriageMoveRequested(_ticket(), 'assigned', workflow: _flow(), technicianId: 5), count: 2);

      expect(outcomes.map((o) => o.kind), [TriageOutcomeKind.started, TriageOutcomeKind.failed]);
      expect(outcomes.last.message, contains('Ese técnico está inactivo'));
      expect(outcomes.last.message, startsWith('No se pudo mover TCK-0001'));
      expect(outcomes.last.message, isNot(contains('interno')));
      expect(bloc.state.inFlight, isEmpty);
    });

    test('el servidor rechaza el cambio (403) y se dice sin detalles internos', () async {
      handler = (_) => errorResponse(403, code: 'forbidden');
      final bloc = build();
      addTearDown(bloc.close);

      final outcomes = await run(bloc, TriageMoveRequested(_ticket(), 'cancelled', workflow: _flow(), reason: 'Motivo claro'), count: 2);

      expect(outcomes.last.kind, TriageOutcomeKind.failed);
      expect(outcomes.last.message, contains('No tienes permiso'));
    });

    test('sin red', () async {
      handler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red');
      final bloc = build();
      addTearDown(bloc.close);

      final outcomes = await run(bloc, TriageMoveRequested(_ticket(), 'triaged', workflow: _flow(), category: 'a', priority: 'high'), count: 2);

      expect(outcomes.last.kind, TriageOutcomeKind.failed);
      expect(outcomes.last.message, contains('No pudimos conectar'));
    });
  });

  test('mientras una solicitud se mueve, otro movimiento de la misma se ignora', () async {
    final bloc = build();
    addTearDown(bloc.close);
    final first = TriageMoveRequested(_ticket(), 'triaged', workflow: _flow(), category: 'a', priority: 'high');

    bloc
      ..add(first)
      ..add(TriageMoveRequested(_ticket(), 'assigned', workflow: _flow(), technicianId: 5));
    await bloc.stream.firstWhere((s) => s.outcome?.kind == TriageOutcomeKind.succeeded);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(posts(), hasLength(1));
  });
}
