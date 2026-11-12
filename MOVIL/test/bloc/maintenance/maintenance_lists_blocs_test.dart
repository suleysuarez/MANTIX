import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/equipment/equipment_search_bloc.dart';
import 'package:mantix/bloc/maintenance/schedule_detail_bloc.dart';
import 'package:mantix/bloc/maintenance/schedules_list_bloc.dart';
import 'package:mantix/bloc/maintenance/upcoming_maintenance_bloc.dart';
import 'package:mantix/bloc/paged/paged_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/maintenance/maintenance_models.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';
import 'package:mantix/repositories/maintenance/maintenance_repository.dart';

import '../../support/fakes.dart';
import '../../support/maintenance_support.dart';
import '../../support/requests_support.dart';

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;
  late MaintenanceRepository repository;
  final today = DateTime(2026, 10, 25, 10);

  setUp(() {
    handler = (_) => jsonResponse(200, {});
    adapter = FakeAdapter((options) => handler(options));
    repository = MaintenanceRepository(dioWith(adapter));
  });

  group('próximos mantenimientos', () {
    UpcomingMaintenanceBloc build() => UpcomingMaintenanceBloc(repository: repository, clock: () => today);

    Future<UpcomingMaintenanceBloc> loaded() async {
      final bloc = build()..add(const UpcomingRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == UpcomingStatus.ready);
      return bloc;
    }

    test('mira 30 días atrás y 30 adelante, que caben en los 62 que admite el servidor', () async {
      handler = (_) => calendarResponse([]);
      await loaded();

      final query = adapter.requests.single.queryParameters;
      final start = DateTime.parse(query['start'] as String);
      final end = DateTime.parse(query['end'] as String);
      expect(start.isAtSameMomentAs(DateTime(2026, 9, 25).toUtc()), isTrue);
      expect(end.isAtSameMomentAs(DateTime(2026, 11, 24).toUtc()), isTrue);
      expect(end.difference(start).inDays, lessThanOrEqualTo(62));
    });

    test('deja los vencidos primero y quita lo hecho', () async {
      handler = (_) => calendarResponse([
            calendarEventJson(id: 1, at: DateTime(2026, 10, 28, 12).toUtc().toIso8601String()),
            calendarEventJson(id: 2, kind: 'done', at: DateTime(2026, 10, 20, 12).toUtc().toIso8601String()),
            calendarEventJson(id: 3, kind: 'overdue', at: DateTime(2026, 10, 6, 12).toUtc().toIso8601String()),
            calendarEventJson(id: 4, at: DateTime(2026, 10, 26, 12).toUtc().toIso8601String()),
          ]);
      final bloc = await loaded();

      expect(bloc.state.items.map((e) => e.scheduleId), [3, 4, 1]);
      expect(bloc.state.initialLoading, isFalse);
      expect(bloc.state.unavailable, isFalse);
    });

    test('«Servicios entre» filtra por rango desde hoy sin volver a pedir al servidor', () async {
      String at(int day, [int month = 10]) => DateTime(2026, month, day, 12).toUtc().toIso8601String();
      handler = (_) => calendarResponse([
            calendarEventJson(id: 1, kind: 'overdue', at: at(6)),
            calendarEventJson(id: 2, at: at(25)),
            calendarEventJson(id: 3, at: at(30)),
            calendarEventJson(id: 4, at: at(2, 11)),
            calendarEventJson(id: 5, at: at(20, 11)),
          ]);
      final bloc = await loaded();
      List<int> ids() => bloc.state.visibleItems.map((e) => e.scheduleId).toList();

      expect(bloc.state.range, UpcomingRange.all);
      expect(ids(), [1, 2, 3, 4, 5], reason: 'Todo deja los vencidos y todos los programados cargados');

      bloc.add(const UpcomingRangeChanged(UpcomingRange.today));
      await bloc.stream.firstWhere((state) => state.range == UpcomingRange.today);
      expect(ids(), [2], reason: 'Hoy: solo lo de hoy');

      bloc.add(const UpcomingRangeChanged(UpcomingRange.week));
      await bloc.stream.firstWhere((state) => state.range == UpcomingRange.week);
      expect(ids(), [2, 3], reason: 'Próx. 7 días: de hoy al 1 de noviembre; el del 2 de noviembre y el vencido quedan fuera');

      bloc.add(const UpcomingRangeChanged(UpcomingRange.month));
      await bloc.stream.firstWhere((state) => state.range == UpcomingRange.month);
      expect(ids(), [2, 3, 4, 5]);
      expect(adapter.requests, hasLength(1), reason: 'cambiar de rango no vuelve a pedir');
    });

    test('sin servicios queda lista y vacía', () async {
      handler = (_) => calendarResponse([]);
      final bloc = await loaded();
      expect(bloc.state.items, isEmpty);
      expect(bloc.state.status, UpcomingStatus.ready);
    });

    test('si falla, queda no disponible con el motivo y se puede reintentar', () async {
      handler = (_) => errorResponse(500);
      final bloc = build()..add(const UpcomingRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == UpcomingStatus.failure);
      expect(bloc.state.unavailable, isTrue);
      expect(bloc.state.failure, isA<ServerFailure>());

      handler = (_) => calendarResponse([calendarEventJson()]);
      bloc.add(const UpcomingRequested());
      await bloc.stream.firstWhere((state) => state.status == UpcomingStatus.ready);
      expect(bloc.state.items, hasLength(1));
    });

    test('una recarga que falla conserva lo que ya se veía', () async {
      handler = (_) => calendarResponse([calendarEventJson()]);
      final bloc = await loaded();
      handler = (_) => errorResponse(500);
      final done = Completer<void>();
      bloc.add(UpcomingRequested(done: done));
      await done.future;

      expect(bloc.state.status, UpcomingStatus.failure);
      expect(bloc.state.unavailable, isFalse);
      expect(bloc.state.items, hasLength(1));
    });

    test('se recarga solo cuando alguien programa un plan', () async {
      handler = (_) => calendarResponse([]);
      final bloc = await loaded();
      handler = (options) => options.method == 'POST' ? jsonResponse(201, scheduleJson()) : calendarResponse([calendarEventJson()]);

      await repository.create(equipmentId: 12, title: 'Revisión', intervalDays: 30, remindDaysBefore: 3, firstDueAt: DateTime(2026, 11, 26, 9));
      await bloc.stream.firstWhere((state) => state.status == UpcomingStatus.ready && state.items.isNotEmpty);

      expect(bloc.state.items, hasLength(1));
    });
  });

  group('lista de planes', () {
    SchedulesListBloc build({String search = '', int? technicianId, ScheduleStatusFilter status = ScheduleStatusFilter.all, String sort = 'next_due_at', int pageSize = 20}) =>
        SchedulesListBloc(repository: repository, search: search, technicianId: technicianId, status: status, sort: sort, pageSize: pageSize);

    Future<SchedulesListBloc> loaded({SchedulesListBloc? bloc}) async {
      final list = bloc ?? build();
      list.add(const SchedulesListStarted());
      addTearDown(list.close);
      await list.stream.firstWhere((state) => state.status == SchedulesStatus.success);
      return list;
    }

    test('pide la primera página con los filtros del constructor', () async {
      handler = (_) => pagedResponse([scheduleJson(), scheduleJson(id: 5, title: 'Limpieza')], total: 2);
      final bloc = await loaded(bloc: build(search: 'ups', technicianId: 2, status: ScheduleStatusFilter.overdue, sort: 'title', pageSize: 10));

      expect(adapter.requests.single.queryParameters, {'page': 1, 'size': 10, 'sort': 'title', 'search': 'ups', 'technician_id': 2, 'overdue': true});
      expect(bloc.state.items.map((p) => p.title), ['Revisión de UPS', 'Limpieza']);
      expect(bloc.state.total, 2);
      expect(bloc.state.totalPages, 1);
    });

    test('moverse de página pide esa página y mientras llega sigue la anterior', () async {
      handler = (options) {
        final page = options.queryParameters['page'] as int;
        return pagedResponse([scheduleJson(id: page, title: 'Plan $page')], page: page, totalPages: 3, total: 3);
      };
      final bloc = await loaded();
      final states = <SchedulesListState>[];
      final subscription = bloc.stream.listen(states.add);
      addTearDown(subscription.cancel);

      bloc.add(const SchedulesPageSelected(2));
      await bloc.stream.firstWhere((state) => state.status == SchedulesStatus.success && state.page == 2 && !state.loadingPage);

      expect(states.first.loadingPage, isTrue);
      expect(states.first.items.single.title, 'Plan 1');
      expect(bloc.state.items.single.title, 'Plan 2');
      expect(bloc.state.totalPages, 3);
    });

    test('sin planes queda lista y vacía', () async {
      handler = (_) => pagedResponse(const []);
      final bloc = await loaded();
      expect(bloc.state.items, isEmpty);
      expect(bloc.state.total, 0);
    });

    test('si falla, queda en error con el motivo', () async {
      handler = (_) => errorResponse(500);
      final bloc = build()..add(const SchedulesListStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == SchedulesStatus.failure);
      expect(bloc.state.failure, isA<ServerFailure>());
    });

    test('tirar para refrescar vuelve a pedir la página actual y espera', () async {
      handler = (_) => pagedResponse([scheduleJson()]);
      final bloc = await loaded();
      final before = adapter.requests.length;
      await bloc.refresh();
      expect(adapter.requests.length, before + 1);
      expect(bloc.state.status, SchedulesStatus.success);
    });

    test('se recarga sola cuando alguien cambia un plan', () async {
      handler = (_) => pagedResponse([scheduleJson()]);
      final bloc = await loaded();
      final before = adapter.requests.where((r) => r.method == 'GET').length;
      handler = (options) => options.method == 'PATCH' ? jsonResponse(200, scheduleJson(active: false)) : pagedResponse([scheduleJson(active: false)]);

      await repository.setActive(4, active: false);
      await bloc.stream.firstWhere((state) => state.items.isNotEmpty && !state.items.first.isActive);

      expect(adapter.requests.where((r) => r.method == 'GET').length, before + 1);
    });
  });

  group('ficha de un plan', () {
    ScheduleDetailBloc build() => ScheduleDetailBloc(repository: repository, scheduleId: 4);

    bool settled(ScheduleDetailState state) => state.planStatus != PlanBlockStatus.loading && state.historyStatus != PlanBlockStatus.loading;

    ResponseBody ok(RequestOptions options) => options.path.endsWith('/history') ? jsonResponse(200, historyJson()) : jsonResponse(200, scheduleJson());

    test('carga el plan y su historial', () async {
      handler = ok;
      final bloc = build()..add(const ScheduleDetailRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(settled);

      expect(bloc.state.plan?.id, 4);
      expect(bloc.state.history?.runs, hasLength(1));
      expect(bloc.state.history?.reschedules, hasLength(1));
      expect(adapter.requests.map((r) => r.path), containsAll(['/maintenance/schedules/4', '/maintenance/schedules/4/history']));
    });

    test('si falla el historial, el plan se ve igual', () async {
      handler = (options) => options.path.endsWith('/history') ? errorResponse(500) : ok(options);
      final bloc = build()..add(const ScheduleDetailRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(settled);

      expect(bloc.state.planStatus, PlanBlockStatus.ready);
      expect(bloc.state.plan, isNotNull);
      expect(bloc.state.historyStatus, PlanBlockStatus.failure);
      expect(bloc.state.historyFailure, isA<ServerFailure>());
    });

    test('un plan que ya no existe llega como NotFoundFailure y el historial también', () async {
      handler = (_) => errorResponse(404, code: 'schedule_not_found');
      final bloc = build()..add(const ScheduleDetailRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(settled);

      expect(bloc.state.planFailure, isA<NotFoundFailure>());
      expect(bloc.state.plan, isNull);
    });

    test('reintentar un bloque solo vuelve a pedir ese bloque', () async {
      handler = (_) => errorResponse(500);
      final bloc = build()..add(const ScheduleDetailRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere(settled);

      handler = ok;
      final before = adapter.requests.length;
      bloc.add(const ScheduleHistoryRetried());
      await bloc.stream.firstWhere((state) => state.historyStatus == PlanBlockStatus.ready);
      expect(adapter.requests.length, before + 1);
      expect(bloc.state.planStatus, PlanBlockStatus.failure, reason: 'el plan no se tocó');

      bloc.add(const SchedulePlanRetried());
      await bloc.stream.firstWhere((state) => state.planStatus == PlanBlockStatus.ready);
      expect(bloc.state.plan?.id, 4);
    });
  });

  group('buscador de equipos', () {
    EquipmentSearchBloc build({String search = '', int pageSize = 20}) => EquipmentSearchBloc(repository: EquipmentRepository(dioWith(adapter)), search: search, pageSize: pageSize);

    test('pide al servidor la búsqueda, el tamaño de página y las páginas siguientes', () async {
      handler = (options) {
        final page = options.queryParameters['page'] as int;
        return pagedResponse([equipmentJson(id: page, tag: 'EQ-$page')], page: page, totalPages: 2, total: 2);
      };
      final bloc = build(search: 'dell', pageSize: 5)..add(const PagedStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == PagedStatus.success);

      expect(adapter.requests.single.path, '/equipment');
      expect(adapter.requests.single.queryParameters, containsPair('search', 'dell'));
      expect(adapter.requests.single.queryParameters, containsPair('size', 5));

      bloc.add(const PagedLoadMoreRequested());
      await bloc.stream.firstWhere((state) => state.items.length == 2);
      expect(adapter.requests.last.queryParameters, containsPair('page', 2));
    });

    test('sin permiso para ver equipos termina en error', () async {
      handler = (_) => errorResponse(403, code: 'forbidden');
      final bloc = build()..add(const PagedStarted());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == PagedStatus.failure);
      expect(bloc.state.failure, isA<ForbiddenFailure>());
    });
  });
}
