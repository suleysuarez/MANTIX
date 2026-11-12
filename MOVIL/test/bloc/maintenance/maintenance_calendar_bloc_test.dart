import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/maintenance/maintenance_calendar_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
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
    handler = (_) => calendarResponse([
          calendarEventJson(id: 1, at: DateTime(2026, 10, 6, 12).toUtc().toIso8601String(), kind: 'overdue'),
          calendarEventJson(id: 2, at: DateTime(2026, 10, 13, 12).toUtc().toIso8601String()),
          calendarEventJson(id: 3, at: DateTime(2026, 10, 13, 16).toUtc().toIso8601String(), title: 'Otro'),
        ]);
    adapter = FakeAdapter((options) => handler(options));
    repository = MaintenanceRepository(dioWith(adapter));
  });

  MaintenanceCalendarBloc build() => MaintenanceCalendarBloc(repository: repository, clock: () => today);

  Future<MaintenanceCalendarBloc> loaded() async {
    final bloc = build()..add(const CalendarRequested());
    addTearDown(bloc.close);
    await bloc.stream.firstWhere((state) => state.status == CalendarStatus.ready);
    return bloc;
  }

  test('empieza en el mes de hoy y todavía cargando', () {
    final bloc = build();
    addTearDown(bloc.close);
    expect(bloc.state.anchor, DateTime(2026, 10));
    expect(bloc.state.loading, isTrue);
    expect(bloc.state.events, isEmpty);
  });

  test('pide los servicios de la cuadrícula del mes y los agrupa por día', () async {
    final bloc = await loaded();

    final query = adapter.requests.single.queryParameters;
    expect(query['start'], DateTime(2026, 9, 28).toUtc().toIso8601String());
    expect(query['end'], DateTime(2026, 11, 2).toUtc().toIso8601String());
    expect(bloc.state.events, hasLength(3));
    expect(bloc.state.byDay.keys, ['2026-10-06', '2026-10-13']);
    expect(bloc.state.byDay['2026-10-13'], hasLength(2));
    expect(bloc.state.truncated, isFalse);
  });

  test('avisa si el servidor llegó a su tope', () async {
    handler = (_) => calendarResponse([calendarEventJson()], truncated: true);
    final bloc = await loaded();
    expect(bloc.state.truncated, isTrue);
  });

  group('moverse de mes', () {
    test('borra los servicios de la vista y pide el nuevo mes', () async {
      final bloc = await loaded();
      bloc.add(const CalendarMonthShifted(1));
      await bloc.stream.firstWhere((state) => state.anchor == DateTime(2026, 11) && state.status == CalendarStatus.ready);

      final query = adapter.requests.last.queryParameters;
      expect(query['start'], DateTime(2026, 10, 26).toUtc().toIso8601String());
      expect(query['end'], DateTime(2026, 12, 7).toUtc().toIso8601String());
    });

    test('mientras llega el mes nuevo no se enseñan marcas del anterior', () async {
      final bloc = await loaded();
      final states = <MaintenanceCalendarState>[];
      final subscription = bloc.stream.listen(states.add);
      addTearDown(subscription.cancel);
      bloc.add(const CalendarMonthShifted(-1));
      await bloc.stream.firstWhere((state) => state.status == CalendarStatus.ready);

      expect(states.first.anchor, DateTime(2026, 9));
      expect(states.first.events, isEmpty);
      expect(states.first.loading, isTrue, reason: 'al moverse ya está cargando el mes nuevo');
    });

    test('moverse quita el día elegido', () async {
      final bloc = await loaded();
      bloc.add(const CalendarDaySelected('2026-10-13'));
      await pumpEventQueue();
      expect(bloc.state.selectedKey, '2026-10-13');

      bloc.add(const CalendarMonthShifted(1));
      await bloc.stream.firstWhere((state) => state.status == CalendarStatus.ready);
      expect(bloc.state.selectedKey, isNull);
    });

    test('una respuesta que llega tarde de otro mes se descarta', () async {
      final gated = GatedAdapter((options) {
        final start = DateTime.parse(options.queryParameters['start'] as String);
        // Octubre trae un servicio; noviembre, otro distinto.
        return start.isBefore(DateTime(2026, 10, 15).toUtc())
            ? calendarResponse([calendarEventJson(id: 1, title: 'De octubre')])
            : calendarResponse([calendarEventJson(id: 2, title: 'De noviembre', at: DateTime(2026, 11, 10, 12).toUtc().toIso8601String())]);
      });
      final bloc = MaintenanceCalendarBloc(repository: MaintenanceRepository(Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = gated), clock: () => today)..add(const CalendarRequested());
      addTearDown(bloc.close);
      await pumpEventQueue();
      bloc.add(const CalendarMonthShifted(1));
      await pumpEventQueue();
      expect(gated.pending, 2);

      gated.releaseNext(); // llega la de octubre, que ya no es el mes visible
      await pumpEventQueue();
      expect(bloc.state.events, isEmpty);

      gated.releaseNext();
      await bloc.stream.firstWhere((state) => state.status == CalendarStatus.ready);
      expect(bloc.state.events.single.title, 'De noviembre');
    });
  });

  group('día elegido', () {
    test('tocar un día lo elige, tocarlo otra vez lo quita y sus servicios salen por hora', () async {
      final bloc = await loaded();
      bloc.add(const CalendarDaySelected('2026-10-13'));
      await pumpEventQueue();
      expect(bloc.state.selectedEvents.map((e) => e.scheduleId), [2, 3]);

      bloc.add(const CalendarDaySelected('2026-10-13'));
      await pumpEventQueue();
      expect(bloc.state.selectedKey, isNull);
      expect(bloc.state.selectedEvents, isEmpty);
    });

    test('un día sin servicios no tiene lista', () async {
      final bloc = await loaded();
      bloc.add(const CalendarDaySelected('2026-10-20'));
      await pumpEventQueue();
      expect(bloc.state.selectedEvents, isEmpty);
    });

    test('null quita la elección', () async {
      final bloc = await loaded();
      bloc.add(const CalendarDaySelected('2026-10-13'));
      bloc.add(const CalendarDaySelected(null));
      await pumpEventQueue();
      expect(bloc.state.selectedKey, isNull);
    });

    test('«hoy» vuelve al mes actual y elige el día de hoy', () async {
      final bloc = await loaded();
      bloc.add(const CalendarMonthShifted(2));
      await bloc.stream.firstWhere((state) => state.status == CalendarStatus.ready);
      bloc.add(const CalendarTodayRequested());
      await bloc.stream.firstWhere((state) => state.anchor == DateTime(2026, 10) && state.status == CalendarStatus.ready);

      expect(bloc.state.selectedKey, '2026-10-25');
    });

    test('«hoy» en el mes actual solo elige el día, sin volver a pedir', () async {
      final bloc = await loaded();
      final before = adapter.requests.length;
      bloc.add(const CalendarTodayRequested());
      await pumpEventQueue();

      expect(bloc.state.selectedKey, '2026-10-25');
      expect(adapter.requests.length, before);
      expect(bloc.state.events, hasLength(3), reason: 'los servicios del mes siguen a la vista');
    });
  });

  group('errores', () {
    test('si falla, queda en error con el motivo y se puede reintentar', () async {
      handler = (_) => errorResponse(500);
      final bloc = build()..add(const CalendarRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == CalendarStatus.failure);
      expect(bloc.state.failure, isA<ServerFailure>());

      handler = (_) => calendarResponse([calendarEventJson()]);
      bloc.add(const CalendarRequested());
      await bloc.stream.firstWhere((state) => state.status == CalendarStatus.ready);
      expect(bloc.state.failure, isNull);
      expect(bloc.state.events, hasLength(1));
    });

    test('sin permiso llega un ForbiddenFailure', () async {
      handler = (_) => errorResponse(403, code: 'forbidden');
      final bloc = build()..add(const CalendarRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == CalendarStatus.failure);
      expect(bloc.state.failure, isA<ForbiddenFailure>());
    });

    test('sin red llega un NetworkFailure', () async {
      handler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red');
      final bloc = build()..add(const CalendarRequested());
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state.status == CalendarStatus.failure);
      expect(bloc.state.failure, isA<NetworkFailure>());
    });
  });

  test('tirar para refrescar espera a que termine', () async {
    final bloc = await loaded();
    final before = adapter.requests.length;
    final done = Completer<void>();
    bloc.add(CalendarRequested(done: done));
    await done.future;
    expect(adapter.requests.length, before + 1);
    expect(bloc.state.status, CalendarStatus.ready);
  });

  test('se recarga solo cuando alguien cambia un plan', () async {
    final bloc = await loaded();
    final before = adapter.requests.where((r) => r.path == '/maintenance/calendar').length;
    handler = (options) => options.method == 'PATCH' ? jsonResponse(200, scheduleJson()) : calendarResponse([calendarEventJson()]);

    await repository.setActive(4, active: false);
    await bloc.stream.firstWhere((state) => state.status == CalendarStatus.ready);

    expect(adapter.requests.where((r) => r.path == '/maintenance/calendar').length, before + 1);
  });
}
