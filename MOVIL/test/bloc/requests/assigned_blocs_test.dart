import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/paged/paged_bloc.dart';
import 'package:mantix/bloc/requests/assigned_summary_bloc.dart';
import 'package:mantix/bloc/requests/assigned_tickets_bloc.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;
  late RequestsRepository repository;

  setUp(() {
    handler = (_) => errorResponse(404);
    adapter = FakeAdapter((options) => handler(options));
    repository = RequestsRepository(dioWith(adapter));
  });

  group('AssignedTicketsBloc', () {
    test('pide solo los estados abiertos, de 20 en 20, y entrega los tickets', () async {
      handler = (_) => pagedResponse([ticketJson(id: 1, status: 'assigned'), ticketJson(id: 2, status: 'in_progress')]);
      final bloc = AssignedTicketsBloc(repository: repository)..add(const PagedStarted());
      addTearDown(bloc.close);

      final state = await bloc.stream.firstWhere((s) => s.status == PagedStatus.success);

      expect(state.items.map((t) => t.id), [1, 2]);
      final query = adapter.requests.single.queryParameters;
      expect(adapter.requests.single.path, '/maintenance/requests');
      expect((query['status'], query['size'], query['page']), ('assigned,in_progress,waiting', 20, 1));
    });

    test('un error en la primera página queda como fallo y se puede reintentar', () async {
      handler = (_) => errorResponse(500);
      final bloc = AssignedTicketsBloc(repository: repository)..add(const PagedStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == PagedStatus.failure);

      handler = (_) => pagedResponse([ticketJson(id: 3)]);
      await bloc.refresh();
      expect(bloc.state.status, PagedStatus.success);
      expect(bloc.state.items.single.id, 3);
    });
  });

  group('AssignedSummaryBloc', () {
    ResponseBody byQuery(RequestOptions options) {
      final query = options.queryParameters;
      final total = query['priority'] != null ? 2 : (query['status'] == 'in_progress' ? 3 : 7);
      return pagedResponse([ticketJson()], total: total);
    }

    test('cada cifra es el total que informa el servidor, con consultas de un solo ticket', () async {
      handler = byQuery;
      final bloc = AssignedSummaryBloc(repository: repository)..add(const AssignedSummaryRequested());
      addTearDown(bloc.close);

      final state = await bloc.stream.firstWhere((s) => s.status == AssignedSummaryStatus.ready);

      expect((state.open, state.inProgress, state.urgent), (7, 3, 2));
      expect(adapter.requests, hasLength(3));
      expect(adapter.requests.every((r) => r.queryParameters['size'] == 1), isTrue);
      final priorities = adapter.requests.map((r) => r.queryParameters['priority']).whereType<String>().single;
      expect(priorities, 'critical,high', reason: 'urgente es crítica o alta');
    });

    test('si falla conserva las cifras que ya tenía y deja el error', () async {
      handler = byQuery;
      final bloc = AssignedSummaryBloc(repository: repository)..add(const AssignedSummaryRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((s) => s.status == AssignedSummaryStatus.ready);

      handler = (_) => errorResponse(500);
      bloc.add(const AssignedSummaryRequested());
      final failed = await bloc.stream.firstWhere((s) => s.status == AssignedSummaryStatus.failure);

      expect(failed.open, 7, reason: 'se siguen viendo las cifras anteriores');
      expect(failed.failure, isNotNull);
    });
  });
}
