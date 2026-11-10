import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/tickets/ticket_board_bloc.dart';
import 'package:mantix/models/requests/request_models.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

const _workflow = [
  {'status': 'submitted', 'order': 1, 'allowed_targets': ['triaged', 'cancelled'], 'requires': [], 'can_enter': true},
  {'status': 'triaged', 'order': 2, 'allowed_targets': ['in_progress'], 'requires': ['category', 'priority'], 'can_enter': true},
  {'status': 'in_progress', 'order': 3, 'allowed_targets': ['closed'], 'requires': [], 'can_enter': true},
  {'status': 'closed', 'order': 4, 'allowed_targets': [], 'requires': [], 'can_enter': false},
  {'status': 'cancelled', 'order': 5, 'allowed_targets': [], 'requires': ['reason'], 'can_enter': true},
];

TicketListItem ticket({int id = 1, String status = 'in_progress', bool canAct = true}) => TicketListItem.fromJson(ticketJson(id: id, status: status, canAct: canAct));

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) statusHandler;

  setUp(() {
    statusHandler = (_) => jsonResponse(200, detailJson());
    adapter = FakeAdapter((options) {
      if (options.path == '/maintenance/requests/workflow') return jsonResponse(200, _workflow);
      return statusHandler(options);
    });
  });

  TicketBoardBloc build() => TicketBoardBloc(repository: RequestsRepository(dioWith(adapter)));

  Future<TicketBoardBloc> ready() async {
    final bloc = build()..add(const TicketBoardStarted());
    await bloc.stream.firstWhere((state) => state.status == BoardStatus.ready);
    return bloc;
  }

  test('carga el flujo del servidor en orden y sabe qué destinos son válidos', () async {
    final bloc = await ready();
    addTearDown(bloc.close);

    expect([for (final state in bloc.state.workflow) state.status], ['submitted', 'triaged', 'in_progress', 'closed', 'cancelled']);
    expect(bloc.state.canMove(ticket(status: 'in_progress'), 'closed'), isFalse, reason: 'no tiene permiso para entrar en «Cerrado»');
    expect(bloc.state.canMove(ticket(status: 'submitted'), 'triaged'), isTrue);
    expect(bloc.state.canMove(ticket(status: 'submitted'), 'in_progress'), isFalse, reason: 'transición que el flujo no permite');
    expect(bloc.state.canMove(ticket(status: 'submitted', canAct: false), 'triaged'), isFalse, reason: 'no puede actuar sobre este ticket');
    expect(bloc.state.canMove(ticket(status: 'submitted'), 'submitted'), isFalse);
    expect(bloc.state.targetsFor(ticket(status: 'submitted')), ['triaged', 'cancelled']);
    expect(bloc.state.requiresFor('triaged'), ['category', 'priority']);
    expect(bloc.state.requiresFor('desconocido'), isEmpty);
  });

  test('un fallo al cargar el flujo deja el tablero sin movimientos y con el motivo', () async {
    adapter = FakeAdapter((_) => errorResponse(500));
    final bloc = build()..add(const TicketBoardStarted());
    addTearDown(bloc.close);
    await bloc.stream.firstWhere((state) => state.status == BoardStatus.failure);

    expect(bloc.state.failure, isNotNull);
    expect(bloc.state.canMove(ticket(status: 'submitted'), 'triaged'), isFalse);
  });

  test('mover manda el estado y los datos, avisa y no deja el ticket «moviéndose»', () async {
    final bloc = await ready();
    addTearDown(bloc.close);
    final states = <TicketBoardState>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);

    bloc.add(TicketMoveRequested(ticket(status: 'submitted'), 'cancelled', notes: 'Duplicado'));
    await bloc.stream.firstWhere((state) => state.notice != null && state.movingIds.isEmpty);

    final post = adapter.requests.singleWhere((r) => r.method == 'POST');
    expect(post.path, '/maintenance/requests/1/status');
    expect(post.data, {'status': 'cancelled', 'notes': 'Duplicado'});
    expect(states.any((state) => state.movingIds.contains(1)), isTrue, reason: 'mientras esperaba estaba marcado');
    expect(bloc.state.notice!.isError, isFalse);
    expect(bloc.state.notice!.message, contains('TCK-0001'));
  });

  test('si el servidor rechaza el cambio avisa con el motivo y el ticket queda libre', () async {
    final bloc = await ready();
    addTearDown(bloc.close);
    statusHandler = (_) => errorResponse(409, code: 'ticket_invalid_transition');

    bloc.add(TicketMoveRequested(ticket(status: 'submitted'), 'cancelled', notes: 'x'));
    await bloc.stream.firstWhere((state) => state.notice?.isError == true && state.movingIds.isEmpty);

    expect(bloc.state.notice!.message, startsWith('No se pudo mover TCK-0001'));
  });

  test('un movimiento no permitido ni siquiera llega al servidor', () async {
    final bloc = await ready();
    addTearDown(bloc.close);

    bloc.add(TicketMoveRequested(ticket(status: 'submitted'), 'in_progress'));
    await bloc.stream.firstWhere((state) => state.notice != null);

    expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    expect(bloc.state.notice!.isError, isTrue);
  });

  test('dos avisos iguales seguidos son avisos distintos', () async {
    final bloc = await ready();
    addTearDown(bloc.close);
    bloc.add(TicketMoveRequested(ticket(status: 'submitted'), 'in_progress'));
    final first = (await bloc.stream.firstWhere((state) => state.notice != null)).notice!;
    bloc.add(TicketMoveRequested(ticket(status: 'submitted'), 'in_progress'));
    final second = (await bloc.stream.firstWhere((state) => state.notice != null && state.notice != first)).notice!;

    expect(second.message, first.message);
    expect(second.id, isNot(first.id));
  });
}
