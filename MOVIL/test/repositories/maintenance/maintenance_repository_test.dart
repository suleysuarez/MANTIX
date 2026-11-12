import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/error_messages.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/maintenance/maintenance_models.dart';
import 'package:mantix/repositories/maintenance/maintenance_repository.dart';

import '../../support/fakes.dart';
import '../../support/maintenance_support.dart';
import '../../support/requests_support.dart';

void main() {
  MaintenanceRepository repo(FakeAdapter adapter) => MaintenanceRepository(dioWith(adapter));
  Object? body(RequestOptions request) => request.data is String ? jsonDecode(request.data as String) : request.data;

  group('modelos', () {
    test('un plan lee todos sus campos y las fechas en hora local', () {
      final plan = MaintenanceSchedule.fromJson(scheduleJson());

      expect(plan.id, 4);
      expect(plan.title, 'Revisión de UPS');
      expect(plan.equipment.assetTag, 'SRV-0003');
      expect(plan.technician?.fullName, 'Luis Mora');
      expect(plan.technician?.userId, 8);
      expect(plan.intervalDays, 30);
      expect(plan.remindDaysBefore, 3);
      expect(plan.estimatedHours, 1.5);
      expect(plan.nextDueAt.isUtc, isFalse);
      expect(plan.nextDueAt.isAtSameMomentAs(DateTime.utc(2026, 12, 1, 15)), isTrue);
    });

    test('sin técnico, sin horas y sin descripción', () {
      final plan = MaintenanceSchedule.fromJson(scheduleJson(technician: null, hours: null, description: null));
      expect(plan.technician, isNull);
      expect(plan.estimatedHours, isNull);
      expect(plan.description, isNull);
    });

    test('el estado: inactivo manda sobre vencido, y vencido sobre programado', () {
      final now = DateTime.utc(2026, 12, 2);
      expect(MaintenanceSchedule.fromJson(scheduleJson()).stateAt(now), ScheduleState.overdue);
      expect(MaintenanceSchedule.fromJson(scheduleJson()).stateAt(DateTime.utc(2026, 11, 1)), ScheduleState.planned);
      expect(MaintenanceSchedule.fromJson(scheduleJson(active: false)).stateAt(now), ScheduleState.inactive);
    });

    test('un servicio del calendario conoce su tipo y, si está hecho, si fue a tiempo', () {
      expect(CalendarEvent.fromJson(calendarEventJson(kind: 'overdue')).kind, CalendarKind.overdue);
      expect(CalendarEvent.fromJson(calendarEventJson(kind: 'planned')).kind, CalendarKind.planned);
      final done = CalendarEvent.fromJson(calendarEventJson(kind: 'done', onTime: false));
      expect(done.kind, CalendarKind.done);
      expect(done.onTime, isFalse);
      expect(done.completedAt, isNotNull);
      expect(CalendarEvent.fromJson(calendarEventJson(technician: null)).technician, isNull);
    });

    test('un tipo desconocido cuenta como programado', () {
      expect(CalendarEvent.fromJson(calendarEventJson(kind: 'nuevo')).kind, CalendarKind.planned);
    });
  });

  group('calendar', () {
    test('pide el rango en UTC y lee los servicios y el aviso de tope', () async {
      final adapter = FakeAdapter((_) => calendarResponse([calendarEventJson(), calendarEventJson(kind: 'overdue', id: 5)], truncated: true));
      final data = await repo(adapter).calendar(DateTime(2026, 9, 28), DateTime(2026, 11, 2));

      expect(adapter.requests.single.path, '/maintenance/calendar');
      expect(adapter.requests.single.queryParameters['start'], DateTime(2026, 9, 28).toUtc().toIso8601String());
      expect(adapter.requests.single.queryParameters['end'], DateTime(2026, 11, 2).toUtc().toIso8601String());
      expect(data.events, hasLength(2));
      expect(data.truncated, isTrue);
    });

    test('sin permiso llega un ForbiddenFailure', () async {
      final adapter = FakeAdapter((_) => errorResponse(403, code: 'forbidden'));
      await expectLater(repo(adapter).calendar(DateTime(2026, 9, 28), DateTime(2026, 11, 2)), throwsA(isA<ForbiddenFailure>()));
    });
  });

  group('schedules', () {
    test('pide la página, el tamaño, el orden y la búsqueda recortada', () async {
      final adapter = FakeAdapter((_) => pagedResponse([scheduleJson()], page: 2, totalPages: 3, total: 41));
      final result = await repo(adapter).schedules(page: 2, size: 10, search: '  ups ', technicianId: 2, sort: '-created_at');

      expect(adapter.requests.single.path, '/maintenance/schedules');
      expect(adapter.requests.single.queryParameters, {'page': 2, 'size': 10, 'sort': '-created_at', 'search': 'ups', 'technician_id': 2});
      expect(result.items.single.title, 'Revisión de UPS');
      expect(result.info?.total, 41);
      expect(result.info?.page, 2);
    });

    test('sin filtros no manda search, técnico ni estado, y ordena por la próxima fecha', () async {
      final adapter = FakeAdapter((_) => pagedResponse([scheduleJson()]));
      await repo(adapter).schedules();
      final query = adapter.requests.single.queryParameters;
      expect(query, {'page': 1, 'size': 20, 'sort': 'next_due_at'});
    });

    test('cada filtro de estado se traduce a lo que entiende el servidor', () async {
      Future<Map<String, dynamic>> query(ScheduleStatusFilter status) async {
        final adapter = FakeAdapter((_) => pagedResponse([scheduleJson()]));
        await repo(adapter).schedules(status: status);
        return adapter.requests.single.queryParameters;
      }

      expect(await query(ScheduleStatusFilter.overdue), containsPair('overdue', true));
      expect(await query(ScheduleStatusFilter.active), containsPair('is_active', true));
      expect(await query(ScheduleStatusFilter.inactive), containsPair('is_active', false));
      final all = await query(ScheduleStatusFilter.all);
      expect(all.keys, isNot(anyOf(contains('overdue'), contains('is_active'))));
    });
  });

  test('schedule e history leen un plan y su historial', () async {
    final adapter = FakeAdapter((options) => options.path.endsWith('/history') ? jsonResponse(200, historyJson()) : jsonResponse(200, scheduleJson(id: 7)));
    final repository = repo(adapter);

    final plan = await repository.schedule(7);
    final history = await repository.history(7);

    expect(adapter.requests.map((r) => r.path), ['/maintenance/schedules/7', '/maintenance/schedules/7/history']);
    expect(plan.id, 7);
    expect(history.runs.single.onTime, isFalse);
    expect(history.runs.single.actualHours, 2.0);
    expect(history.reschedules.single.reason, 'Equipo en uso');
  });

  test('un plan que ya no existe llega como NotFoundFailure con su mensaje', () async {
    final adapter = FakeAdapter((_) => errorResponse(404, code: 'schedule_not_found'));
    await expectLater(
      repo(adapter).schedule(7),
      throwsA(isA<NotFoundFailure>().having((f) => f.message, 'mensaje', messagesByErrorCode['schedule_not_found'])),
    );
  });

  group('create', () {
    test('manda el plan con la fecha en UTC y las horas con dos decimales, y avisa', () async {
      final adapter = FakeAdapter((_) => jsonResponse(201, scheduleJson(id: 9)));
      final repository = repo(adapter);
      final changes = <void>[];
      final subscription = repository.changes.listen(changes.add);
      addTearDown(subscription.cancel);
      final due = DateTime(2026, 11, 26, 9);

      final created = await repository.create(equipmentId: 12, title: 'Revisión', description: 'Filtros', intervalDays: 30, remindDaysBefore: 3, firstDueAt: due, estimatedHours: 1.5, technicianId: 2);
      await pumpEventQueue();

      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/maintenance/schedules');
      expect(body(adapter.requests.single), {
        'equipment_id': 12,
        'technician_id': 2,
        'title': 'Revisión',
        'description': 'Filtros',
        'interval_days': 30,
        'estimated_hours': '1.50',
        'remind_days_before': 3,
        'first_due_at': due.toUtc().toIso8601String(),
      });
      expect(created.id, 9);
      expect(changes, hasLength(1));
    });

    test('sin técnico, sin horas y sin descripción no manda el técnico y manda null en lo demás', () async {
      final adapter = FakeAdapter((_) => jsonResponse(201, scheduleJson()));
      await repo(adapter).create(equipmentId: 12, title: 'Revisión', intervalDays: 30, remindDaysBefore: 3, firstDueAt: DateTime(2026, 11, 26, 9));
      final sent = body(adapter.requests.single)! as Map;
      expect(sent.containsKey('technician_id'), isFalse);
      expect(sent['estimated_hours'], isNull);
      expect(sent['description'], isNull);
    });

    test('un equipo que no admite planes llega como conflicto con su mensaje y no avisa de cambios', () async {
      final adapter = FakeAdapter((_) => errorResponse(409, code: 'schedule_equipment_unavailable'));
      final repository = repo(adapter);
      final changes = <void>[];
      final subscription = repository.changes.listen(changes.add);
      addTearDown(subscription.cancel);

      await expectLater(
        repository.create(equipmentId: 12, title: 'Revisión', intervalDays: 30, remindDaysBefore: 3, firstDueAt: DateTime(2026, 11, 26, 9)),
        throwsA(isA<ConflictFailure>().having((f) => f.message, 'mensaje', messagesByErrorCode['schedule_equipment_unavailable'])),
      );
      await pumpEventQueue();
      expect(changes, isEmpty);
    });

    test('los errores 422 llegan por campo', () async {
      final adapter = FakeAdapter((_) => errorResponse(422, code: 'validation_error', errors: [
            {'field': 'body.interval_days', 'message': 'demasiado grande', 'type': 'less_than_equal'},
          ]));
      await expectLater(
        repo(adapter).create(equipmentId: 12, title: 'Revisión', intervalDays: 30, remindDaysBefore: 3, firstDueAt: DateTime(2026, 11, 26, 9)),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  test('complete manda las horas reales con dos decimales (o null) y avisa', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, scheduleJson()));
    final repository = repo(adapter);
    final changes = <void>[];
    final subscription = repository.changes.listen(changes.add);
    addTearDown(subscription.cancel);

    await repository.complete(4, actualHours: 2.5);
    await repository.complete(4);
    await pumpEventQueue();

    expect(adapter.requests.first.method, 'POST');
    expect(adapter.requests.first.path, '/maintenance/schedules/4/complete');
    expect(body(adapter.requests.first), {'actual_hours': '2.50'});
    expect(body(adapter.requests.last), {'actual_hours': null});
    expect(changes, hasLength(2));
  });

  test('setActive manda is_active con PATCH y avisa', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, scheduleJson(active: false)));
    final repository = repo(adapter);
    final changes = <void>[];
    final subscription = repository.changes.listen(changes.add);
    addTearDown(subscription.cancel);

    final plan = await repository.setActive(4, active: false);
    await pumpEventQueue();

    expect(adapter.requests.single.method, 'PATCH');
    expect(adapter.requests.single.path, '/maintenance/schedules/4');
    expect(body(adapter.requests.single), {'is_active': false});
    expect(plan.isActive, isFalse);
    expect(changes, hasLength(1));
  });
}
