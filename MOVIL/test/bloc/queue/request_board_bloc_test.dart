import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/queue/request_board_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/queue/queue_filters.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

const _workflow = [
  {'status': 'submitted', 'order': 1, 'allowed_targets': ['triaged', 'assigned', 'cancelled'], 'requires': [], 'can_enter': true, 'in_queue': true},
  {'status': 'triaged', 'order': 2, 'allowed_targets': ['assigned', 'cancelled'], 'requires': ['category', 'priority'], 'can_enter': true, 'in_queue': true},
  {'status': 'assigned', 'order': 3, 'allowed_targets': ['in_progress', 'cancelled'], 'requires': ['technician'], 'can_enter': true, 'in_queue': true},
  {'status': 'in_progress', 'order': 4, 'allowed_targets': [], 'requires': [], 'can_enter': true, 'in_queue': false},
  {'status': 'cancelled', 'order': 9, 'allowed_targets': [], 'requires': ['reason'], 'can_enter': true, 'in_queue': false},
];

void main() {
  // Tarjetas del servidor por estado: 12 recibidas (dos páginas de 10), 1 clasificada y ninguna asignada.
  late Map<String, List<Map<String, Object?>>> server;
  late Set<String> failing;
  late FakeAdapter adapter;

  setUp(() {
    server = {
      'submitted': [for (var i = 1; i <= 12; i++) ticketJson(id: i, status: 'submitted', canAct: true)],
      'triaged': [ticketJson(id: 20, status: 'triaged', canAct: true)],
      'assigned': [],
    };
    failing = {};
    adapter = FakeAdapter((options) {
      if (options.path == '/maintenance/requests/workflow') return jsonResponse(200, _workflow);
      final status = options.queryParameters['status'] as String;
      if (failing.contains(status)) return errorResponse(500);
      final page = options.queryParameters['page'] as int;
      final size = options.queryParameters['size'] as int;
      final all = server[status]!;
      final items = all.skip((page - 1) * size).take(size).toList();
      return pagedResponse(items, page: page, total: all.length, totalPages: (all.length / size).ceil());
    });
  });

  RequestBoardBloc build({Duration debounce = const Duration(milliseconds: 5)}) => RequestBoardBloc(repository: RequestsRepository(dioWith(adapter)), searchDebounce: debounce);

  bool settled(RequestBoardState s) => s.workflowPhase == WorkflowPhase.ready && s.columns.isNotEmpty && s.columns.every((c) => c.phase != ColumnPhase.loading);

  Future<RequestBoardBloc> ready() async {
    final bloc = build()..add(const RequestBoardStarted());
    await bloc.stream.firstWhere(settled);
    return bloc;
  }

  List<RequestOptions> listCalls() => adapter.requests.where((r) => r.path == '/maintenance/requests').toList();

  test('arma una columna por estado in_queue, con 10 tarjetas por vez y el total del servidor', () async {
    final bloc = await ready();
    addTearDown(bloc.close);

    expect([for (final c in bloc.state.columns) c.status], ['submitted', 'triaged', 'assigned']);
    final submitted = bloc.state.column('submitted')!;
    expect(submitted.items, hasLength(10));
    expect(submitted.total, 12);
    expect(submitted.hasMore, isTrue);
    expect(submitted.remaining, 2);
    expect(bloc.state.column('triaged')!.items.single.id, 20);
    expect(bloc.state.column('assigned')!.items, isEmpty);
    expect(bloc.state.isEmpty, isFalse);

    // Solo el flujo y una petición por columna: no se trae el catálogo completo.
    expect(adapter.requests, hasLength(4));
    expect(listCalls().map((r) => r.queryParameters['size']), everyElement(10));
    expect(listCalls().map((r) => r.queryParameters['page']), everyElement(1));
  });

  test('cada columna carga y falla por separado, y se reintenta sola', () async {
    failing = {'triaged'};
    final bloc = await ready();
    addTearDown(bloc.close);

    expect(bloc.state.column('submitted')!.phase, ColumnPhase.ready);
    expect(bloc.state.column('submitted')!.items, isNotEmpty);
    final failed = bloc.state.column('triaged')!;
    expect(failed.phase, ColumnPhase.failure);
    expect(failed.failure, isA<ServerFailure>());

    failing = {};
    bloc.add(const RequestBoardColumnRetried('triaged'));
    await bloc.stream.firstWhere((s) => s.column('triaged')!.phase == ColumnPhase.ready);
    expect(bloc.state.column('triaged')!.items.single.id, 20);
  });

  test('si el flujo no carga no hay columnas y se reintenta con Started', () async {
    var flowFails = true;
    adapter = FakeAdapter((options) {
      if (options.path == '/maintenance/requests/workflow') return flowFails ? errorResponse(500) : jsonResponse(200, _workflow);
      return pagedResponse(<Object?>[]);
    });
    final bloc = build()..add(const RequestBoardStarted());
    addTearDown(bloc.close);
    final failed = await bloc.stream.firstWhere((s) => s.workflowPhase == WorkflowPhase.failure);
    expect(failed.columns, isEmpty);
    expect(failed.failure, isNotNull);

    flowFails = false;
    bloc.add(const RequestBoardStarted());
    await bloc.stream.firstWhere(settled);
    expect(bloc.state.isEmpty, isTrue, reason: 'ninguna columna tiene tarjetas: la bandeja está al día');
  });

  test('«Ver más» agrega la página siguiente sin duplicar y deja de ofrecerse al terminar', () async {
    final bloc = await ready();
    addTearDown(bloc.close);

    bloc.add(const RequestBoardMoreRequested('submitted'));
    await bloc.stream.firstWhere((s) => s.column('submitted')!.items.length == 12);

    final column = bloc.state.column('submitted')!;
    expect([for (final t in column.items) t.id], [for (var i = 1; i <= 12; i++) i]);
    expect(column.hasMore, isFalse);
    expect(column.loadingMore, isFalse);
    expect(listCalls().last.queryParameters['page'], 2);
    expect(listCalls().last.queryParameters['status'], 'submitted');

    final before = adapter.requests.length;
    bloc.add(const RequestBoardMoreRequested('submitted'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(adapter.requests.length, before, reason: 'no hay más páginas');
  });

  test('si «Ver más» falla conserva las tarjetas y deja reintentar', () async {
    final bloc = await ready();
    addTearDown(bloc.close);

    failing = {'submitted'};
    bloc.add(const RequestBoardMoreRequested('submitted'));
    await bloc.stream.firstWhere((s) => s.column('submitted')!.failure != null);
    final column = bloc.state.column('submitted')!;
    expect(column.items, hasLength(10));
    expect(column.phase, ColumnPhase.ready);
    expect(column.hasMore, isTrue);

    failing = {};
    bloc.add(const RequestBoardMoreRequested('submitted'));
    await bloc.stream.firstWhere((s) => s.column('submitted')!.items.length == 12);
  });

  test('los filtros vuelven a pedir todas las columnas con los parámetros del backend', () async {
    final bloc = await ready();
    addTearDown(bloc.close);
    adapter.requests.clear();

    final filters = QueueFilters(categories: const ['network'], priorities: const ['high', 'critical'], technicianIds: const [4], dateFrom: DateTime(2026, 11, 1), dateTo: DateTime(2026, 11, 8));
    bloc.add(RequestBoardFiltersChanged(filters));
    await bloc.stream.firstWhere((s) => s.filters == filters && settled(s));

    expect(listCalls(), hasLength(3));
    final query = listCalls().first.queryParameters;
    expect(query['category'], 'network');
    expect(query['priority'], 'high,critical');
    expect(query['technician_id'], [4]);
    expect(query['date_from'], isNotNull);
    expect(query['date_to'], isNotNull);
    expect(query['page'], 1);
  });

  test('la búsqueda espera a que deje de escribir y pide solo el último término', () async {
    final bloc = build(debounce: const Duration(milliseconds: 40));
    addTearDown(bloc.close);
    bloc.add(const RequestBoardStarted());
    await bloc.stream.firstWhere(settled);
    adapter.requests.clear();

    bloc
      ..add(const RequestBoardSearchChanged('la'))
      ..add(const RequestBoardSearchChanged('lap'))
      ..add(const RequestBoardSearchChanged('  laptop  '));
    await bloc.stream.firstWhere((s) => s.filters.search == 'laptop' && settled(s));

    expect(listCalls().map((r) => r.queryParameters['search']).toSet(), {'laptop'});
    expect(listCalls(), hasLength(3), reason: 'una sola recarga de las tres columnas');
  });

  test('recargar sin vaciar: las tarjetas siguen visibles y se actualizan', () async {
    final bloc = await ready();
    addTearDown(bloc.close);

    server['triaged'] = [];
    final seen = <int>[];
    final sub = bloc.stream.listen((s) => seen.add(s.column('submitted')!.items.length));
    addTearDown(sub.cancel);
    bloc.add(const RequestBoardRefreshed());
    await bloc.stream.firstWhere((s) => s.column('triaged')!.items.isEmpty);

    expect(seen, everyElement(10), reason: 'la columna no se vació mientras recargaba');
  });

  test('una recarga que falla deja las tarjetas que había', () async {
    final bloc = await ready();
    addTearDown(bloc.close);

    failing = {'submitted'};
    bloc.add(const RequestBoardRefreshed());
    await bloc.stream.firstWhere((s) => s.column('submitted')!.failure != null);
    expect(bloc.state.column('submitted')!.items, hasLength(10));
    expect(bloc.state.column('submitted')!.phase, ColumnPhase.ready);
  });

  group('movimiento optimista', () {
    test('la tarjeta pasa de columna al instante y actualiza los contadores', () async {
      final bloc = await ready();
      addTearDown(bloc.close);
      final ticket = bloc.state.column('submitted')!.items[3];

      bloc.add(RequestBoardMovedOptimistically(ticket, 'triaged'));
      await bloc.stream.firstWhere((s) => s.column('triaged')!.items.length == 2);

      final submitted = bloc.state.column('submitted')!;
      final triaged = bloc.state.column('triaged')!;
      expect(submitted.items.any((t) => t.id == ticket.id), isFalse);
      expect(submitted.total, 11);
      expect(triaged.items.first.id, ticket.id, reason: 'llega arriba de la columna');
      expect(triaged.items.first.status, 'triaged');
      expect(triaged.total, 2);
    });

    test('si falla, vuelve a su columna y a su sitio con los contadores de antes', () async {
      final bloc = await ready();
      addTearDown(bloc.close);
      final before = bloc.state;
      final ticket = before.column('submitted')!.items[3];

      bloc.add(RequestBoardMovedOptimistically(ticket, 'triaged'));
      await bloc.stream.firstWhere((s) => s.column('triaged')!.items.length == 2);
      bloc.add(RequestBoardMoveReverted(ticket.id));
      await bloc.stream.firstWhere((s) => s.column('triaged')!.items.length == 1);

      expect(bloc.state.column('submitted'), before.column('submitted'));
      expect(bloc.state.column('triaged'), before.column('triaged'));
    });

    test('revertir algo que no se movió no hace nada', () async {
      final bloc = await ready();
      addTearDown(bloc.close);
      final before = bloc.state;

      bloc.add(const RequestBoardMoveReverted(999));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state, before);
    });

    test('hacia un estado que no es columna (rechazar) la tarjeta sale del tablero y vuelve si se revierte', () async {
      final bloc = await ready();
      addTearDown(bloc.close);
      final ticket = bloc.state.column('triaged')!.items.single;

      bloc.add(RequestBoardMovedOptimistically(ticket, 'cancelled'));
      await bloc.stream.firstWhere((s) => s.column('triaged')!.items.isEmpty);
      expect(bloc.state.column('triaged')!.total, 0);

      bloc.add(RequestBoardMoveReverted(ticket.id));
      await bloc.stream.firstWhere((s) => s.column('triaged')!.items.isNotEmpty);
      expect(bloc.state.column('triaged')!.items.single.id, 20);
      expect(bloc.state.column('triaged')!.items.single.status, 'triaged');
      expect(bloc.state.column('triaged')!.total, 1);
    });
  });

  test('la recarga avisa cuando termina aunque no haya cambiado nada (tirar para refrescar no se queda girando)', () async {
    final bloc = await ready();
    addTearDown(bloc.close);

    final done = Completer<void>();
    bloc.add(RequestBoardRefreshed(done: done));

    await done.future.timeout(const Duration(seconds: 2));
    expect(bloc.state.column('submitted')!.items, hasLength(10));
  });

  test('la recarga avisa también si falla', () async {
    final bloc = await ready();
    addTearDown(bloc.close);
    failing = {'submitted', 'triaged', 'assigned'};

    final done = Completer<void>();
    bloc.add(RequestBoardRefreshed(done: done));

    await done.future.timeout(const Duration(seconds: 2));
  });
}
