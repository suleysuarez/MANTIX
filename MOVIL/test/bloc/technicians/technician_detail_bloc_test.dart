import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/technicians/technician_detail_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/repositories/requests/requests_repository.dart';
import 'package:mantix/repositories/technicians/technicians_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';
import '../../support/technicians_support.dart';

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;

  ResponseBody tickets(RequestOptions _) => pagedResponse([ticketJson(id: 1), ticketJson(id: 2)], total: 14);
  ResponseBody performance(RequestOptions _) => jsonResponse(200, performanceJson([performanceRowJson(id: 5), performanceRowJson(id: 6, open: 0)]));

  setUp(() {
    handler = (options) => options.path == '/maintenance/requests' ? tickets(options) : performance(options);
    adapter = FakeAdapter((options) => handler(options));
  });

  TechnicianDetailBloc build({int id = 5, bool withTickets = true}) {
    final dio = dioWith(adapter);
    return TechnicianDetailBloc(technicians: TechniciansRepository(dio), requests: RequestsRepository(dio), technicianId: id, withTickets: withTickets);
  }

  bool settled(TechnicianDetailState state) => state.performanceStatus != DetailBlockStatus.loading && state.ticketsStatus != DetailBlockStatus.loading;

  blocTest<TechnicianDetailBloc, TechnicianDetailState>(
    'carga los indicadores del técnico y sus tickets abiertos',
    build: build,
    act: (bloc) => bloc.add(const TechnicianDetailRequested()),
    wait: const Duration(milliseconds: 50),
    verify: (bloc) {
      final state = bloc.state;
      expect(state.performanceStatus, DetailBlockStatus.ready);
      expect(state.performance?.technicianId, 5);
      expect(state.performance?.mttrMedianHours, 12.5);
      expect(state.period, '30d');
      expect(state.ticketsStatus, DetailBlockStatus.ready);
      expect(state.tickets, hasLength(2));
      expect(state.ticketsTotal, 14, reason: 'el total sale de las cabeceras, no de los que se listan');

      final request = adapter.requests.singleWhere((r) => r.path == '/maintenance/requests');
      expect(request.queryParameters['technician_id'], [5]);
      expect(request.queryParameters['status'], 'submitted,triaged,assigned,in_progress,waiting');
      expect(request.queryParameters['size'], TechnicianDetailBloc.ticketsShown);
    },
  );

  blocTest<TechnicianDetailBloc, TechnicianDetailState>(
    'si fallan los indicadores, los tickets siguen',
    setUp: () => handler = (options) => options.path == '/maintenance/requests' ? tickets(options) : errorResponse(500),
    build: build,
    act: (bloc) => bloc.add(const TechnicianDetailRequested()),
    wait: const Duration(milliseconds: 50),
    verify: (bloc) {
      expect(bloc.state.performanceStatus, DetailBlockStatus.failure);
      expect(bloc.state.performanceFailure, isA<ServerFailure>());
      expect(bloc.state.ticketsStatus, DetailBlockStatus.ready);
      expect(bloc.state.tickets, hasLength(2));
    },
  );

  blocTest<TechnicianDetailBloc, TechnicianDetailState>(
    'si fallan los tickets (sin permiso), los indicadores siguen',
    setUp: () => handler = (options) => options.path == '/maintenance/requests' ? errorResponse(403, code: 'forbidden') : performance(options),
    build: build,
    act: (bloc) => bloc.add(const TechnicianDetailRequested()),
    wait: const Duration(milliseconds: 50),
    verify: (bloc) {
      expect(bloc.state.ticketsStatus, DetailBlockStatus.failure);
      expect(bloc.state.ticketsFailure, isA<ForbiddenFailure>());
      expect(bloc.state.performanceStatus, DetailBlockStatus.ready);
      expect(bloc.state.performance, isNotNull);
    },
  );

  blocTest<TechnicianDetailBloc, TechnicianDetailState>(
    'un técnico sin fila de indicadores queda listo y sin dato',
    build: () => build(id: 99),
    act: (bloc) => bloc.add(const TechnicianDetailRequested()),
    wait: const Duration(milliseconds: 50),
    verify: (bloc) {
      expect(bloc.state.performanceStatus, DetailBlockStatus.ready);
      expect(bloc.state.performance, isNull);
    },
  );

  blocTest<TechnicianDetailBloc, TechnicianDetailState>(
    'sin permiso para ver tickets ese bloque ni se pide',
    build: () => build(withTickets: false),
    act: (bloc) => bloc.add(const TechnicianDetailRequested()),
    wait: const Duration(milliseconds: 50),
    verify: (bloc) {
      expect(adapter.requests.map((r) => r.path), ['/dashboard/technicians']);
      expect(bloc.state.performanceStatus, DetailBlockStatus.ready);
    },
  );

  test('reintentar un bloque solo vuelve a pedir ese bloque', () async {
    handler = (options) => errorResponse(500);
    final bloc = build()..add(const TechnicianDetailRequested());
    addTearDown(bloc.close);
    await bloc.stream.firstWhere(settled);
    expect(bloc.state.performanceStatus, DetailBlockStatus.failure);
    expect(bloc.state.ticketsStatus, DetailBlockStatus.failure);

    handler = (options) => options.path == '/maintenance/requests' ? tickets(options) : performance(options);
    final before = adapter.requests.length;
    bloc.add(const TechnicianTicketsRetried());
    await bloc.stream.firstWhere((state) => state.ticketsStatus == DetailBlockStatus.ready);
    expect(adapter.requests.length, before + 1);
    expect(bloc.state.performanceStatus, DetailBlockStatus.failure, reason: 'los indicadores no se tocaron');

    bloc.add(const TechnicianPerformanceRetried());
    await bloc.stream.firstWhere((state) => state.performanceStatus == DetailBlockStatus.ready);
    expect(bloc.state.performance?.technicianId, 5);
  });
}
