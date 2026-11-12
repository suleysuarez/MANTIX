import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/maintenance/schedule_actions_bloc.dart';
import 'package:mantix/core/errors/error_messages.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/maintenance/maintenance_models.dart';
import 'package:mantix/repositories/maintenance/maintenance_repository.dart';

import '../../support/fakes.dart';
import '../../support/maintenance_support.dart';
import '../../support/requests_support.dart';

MaintenanceSchedule _plan({bool active = true}) => MaintenanceSchedule.fromJson(scheduleJson(active: active));

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;
  final now = DateTime(2026, 10, 25, 10);
  final due = DateTime(2026, 11, 26, 9);

  setUp(() {
    handler = (_) => jsonResponse(201, scheduleJson(id: 9, title: 'Revisión'));
    adapter = FakeAdapter((options) => handler(options));
  });

  ScheduleActionsBloc build() => ScheduleActionsBloc(repository: MaintenanceRepository(dioWith(adapter)), clock: () => now);

  Object? body(RequestOptions request) => request.data is String ? jsonDecode(request.data as String) : request.data;

  /// Una petición de alta válida; cada prueba cambia lo que necesite.
  ScheduleCreateRequested create({int? equipmentId = 12, String title = '  Revisión  ', String? description = 'Filtros', String interval = '30', String remind = '3', DateTime? firstDueAt, String? hours = '1,5', int? technicianId = 2}) =>
      ScheduleCreateRequested(equipmentId: equipmentId, title: title, description: description, intervalDays: interval, remindDays: remind, firstDueAt: firstDueAt ?? due, estimatedHours: hours, technicianId: technicianId);

  List<Matcher> ranWith(ScheduleOutcomeKind kind) => [
        isA<ScheduleActionsState>().having((s) => s.busy, 'busy', isTrue),
        isA<ScheduleActionsState>().having((s) => s.busy, 'busy', isFalse).having((s) => s.outcome?.kind, 'resultado', kind),
      ];

  List<Matcher> blockedWith(String message) => [
        isA<ScheduleActionsState>()
            .having((s) => s.busy, 'busy', isFalse)
            .having((s) => s.outcome?.kind, 'resultado', ScheduleOutcomeKind.blocked)
            .having((s) => s.outcome?.message, 'mensaje', message),
      ];

  group('programar', () {
    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      'manda el plan con los textos recortados, las horas con coma y la fecha en UTC, y avisa',
      build: build,
      act: (bloc) => bloc.add(create()),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.succeeded),
      verify: (bloc) {
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
        final outcome = bloc.state.outcome!;
        expect(outcome.message, 'Mantenimiento programado.');
        expect(outcome.created, isTrue);
        expect(outcome.schedule?.id, 9);
        expect(outcome.isError, isFalse);
      },
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      'sin descripción, sin horas y sin técnico no manda el técnico y manda null en lo demás',
      build: build,
      act: (bloc) => bloc.add(create(description: '', hours: '', technicianId: null)),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.succeeded),
      verify: (_) {
        final sent = body(adapter.requests.single)! as Map;
        expect(sent.containsKey('technician_id'), isFalse);
        expect(sent['description'], isNull);
        expect(sent['estimated_hours'], isNull);
      },
    );

    for (final (name, event, message) in <(String, ScheduleCreateRequested, String)>[
      ('sin equipo elegido', create(equipmentId: null), 'Selecciona el equipo.'),
      ('un título vacío', create(title: '   '), 'Este campo es obligatorio.'),
      ('un título demasiado corto', create(title: 'ab'), 'Debe tener al menos 3 caracteres.'),
      ('una descripción de solo espacios', create(description: '  '), 'No puede contener solo espacios.'),
      ('un intervalo que no es número', create(interval: 'a'), 'Debe ser un número entero.'),
      ('un intervalo de cero días', create(interval: '0'), 'Debe ser al menos 1.'),
      ('un recordatorio mayor que el intervalo', create(interval: '10', remind: '11'), 'El recordatorio no puede superar el intervalo entre servicios.'),
      ('un recordatorio negativo', create(remind: '-1'), 'Debe ser al menos 0.'),
      ('sin fecha del primer servicio', const ScheduleCreateRequested(equipmentId: 12, title: 'Revisión', intervalDays: '30', remindDays: '3', firstDueAt: null), 'Este campo es obligatorio.'),
      ('una fecha en el pasado', create(firstDueAt: DateTime(2026, 10, 25, 9)), 'No se puede programar en el pasado.'),
      ('unas horas negativas', create(hours: '-2'), 'Escribe un número válido.'),
      ('unas horas con tres decimales', create(hours: '1,234'), 'Usa como máximo 2 decimales.'),
      ('unas horas en cero', create(hours: '0'), 'Debe ser mayor que 0.'),
    ]) {
      blocTest<ScheduleActionsBloc, ScheduleActionsState>(
        '$name no pide nada',
        build: build,
        act: (bloc) => bloc.add(event),
        wait: const Duration(milliseconds: 50),
        expect: () => blockedWith(message),
        verify: (_) => expect(adapter.requests, isEmpty),
      );
    }

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      '409: el equipo no admite planes en su estado actual',
      setUp: () => handler = (_) => errorResponse(409, code: 'schedule_equipment_unavailable'),
      build: build,
      act: (bloc) => bloc.add(create()),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.failed),
      verify: (bloc) {
        final outcome = bloc.state.outcome!;
        expect(outcome.failure, isA<ConflictFailure>());
        expect(outcome.message, 'No se pudo programar el mantenimiento: ${messagesByErrorCode['schedule_equipment_unavailable']}');
        expect(outcome.message, isNot(contains('detalle interno')));
        expect(outcome.isError, isTrue);
      },
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      '409: el técnico elegido está inactivo',
      setUp: () => handler = (_) => errorResponse(409, code: 'schedule_technician_inactive'),
      build: build,
      act: (bloc) => bloc.add(create()),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.failed),
      verify: (bloc) => expect(bloc.state.outcome!.message, contains(messagesByErrorCode['schedule_technician_inactive']!)),
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      '404: el equipo ya no existe',
      setUp: () => handler = (_) => errorResponse(404, code: 'equipment_not_found'),
      build: build,
      act: (bloc) => bloc.add(create()),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.failed),
      verify: (bloc) {
        expect(bloc.state.outcome!.failure, isA<NotFoundFailure>());
        expect(bloc.state.outcome!.message, contains(messagesByErrorCode['equipment_not_found']!));
      },
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      '403: sin permiso para programar',
      setUp: () => handler = (_) => errorResponse(403, code: 'forbidden'),
      build: build,
      act: (bloc) => bloc.add(create()),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.failed),
      verify: (bloc) {
        expect(bloc.state.outcome!.failure, isA<ForbiddenFailure>());
        expect(bloc.state.outcome!.message, contains('No tienes permiso'));
      },
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      '422 del servidor: el motivo llega por campo',
      setUp: () => handler = (_) => errorResponse(422, code: 'validation_error', errors: [
            {'field': 'body.interval_days', 'message': 'demasiado grande', 'type': 'less_than_equal'},
          ]),
      build: build,
      act: (bloc) => bloc.add(create()),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.failed),
      verify: (bloc) => expect((bloc.state.outcome!.failure! as ValidationFailure).fieldErrors, containsPair('body.interval_days', 'demasiado grande')),
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      'sin red',
      setUp: () => handler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red'),
      build: build,
      act: (bloc) => bloc.add(create()),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.failed),
      verify: (bloc) => expect(bloc.state.outcome!.failure, isA<NetworkFailure>()),
    );
  });

  group('marcar como hecho', () {
    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      'manda las horas reales con dos decimales y avisa con el nombre del plan',
      setUp: () => handler = (_) => jsonResponse(200, scheduleJson()),
      build: build,
      act: (bloc) => bloc.add(ScheduleCompleteRequested(_plan(), actualHours: '2,5')),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.succeeded),
      verify: (bloc) {
        expect(adapter.requests.single.path, '/maintenance/schedules/4/complete');
        expect(body(adapter.requests.single), {'actual_hours': '2.50'});
        expect(bloc.state.outcome!.message, 'Servicio «Revisión de UPS» registrado como hecho.');
        expect(bloc.state.outcome!.created, isFalse);
      },
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      'sin horas manda null',
      setUp: () => handler = (_) => jsonResponse(200, scheduleJson()),
      build: build,
      act: (bloc) => bloc.add(ScheduleCompleteRequested(_plan())),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.succeeded),
      verify: (_) => expect(body(adapter.requests.single), {'actual_hours': null}),
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      'unas horas que no son válidas no piden nada',
      build: build,
      act: (bloc) => bloc.add(ScheduleCompleteRequested(_plan(), actualHours: '-1')),
      wait: const Duration(milliseconds: 50),
      expect: () => blockedWith('Escribe un número válido.'),
      verify: (_) => expect(adapter.requests, isEmpty),
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      '404: el plan ya no existe',
      setUp: () => handler = (_) => errorResponse(404, code: 'schedule_not_found'),
      build: build,
      act: (bloc) => bloc.add(ScheduleCompleteRequested(_plan())),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.failed),
      verify: (bloc) => expect(bloc.state.outcome!.message, 'No se pudo registrar el servicio: ${messagesByErrorCode['schedule_not_found']}'),
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      '403: sin permiso para editar planes',
      setUp: () => handler = (_) => errorResponse(403, code: 'forbidden'),
      build: build,
      act: (bloc) => bloc.add(ScheduleCompleteRequested(_plan())),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.failed),
      verify: (bloc) => expect(bloc.state.outcome!.failure, isA<ForbiddenFailure>()),
    );
  });

  group('activar o desactivar', () {
    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      'desactiva un plan activo y avisa',
      setUp: () => handler = (_) => jsonResponse(200, scheduleJson(active: false)),
      build: build,
      act: (bloc) => bloc.add(ScheduleActiveChangeRequested(_plan(), active: false)),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.succeeded),
      verify: (bloc) {
        expect(adapter.requests.single.method, 'PATCH');
        expect(body(adapter.requests.single), {'is_active': false});
        expect(bloc.state.outcome!.message, 'El plan «Revisión de UPS» fue desactivado.');
      },
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      'activa un plan inactivo',
      setUp: () => handler = (_) => jsonResponse(200, scheduleJson()),
      build: build,
      act: (bloc) => bloc.add(ScheduleActiveChangeRequested(_plan(active: false), active: true)),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.succeeded),
      verify: (bloc) {
        expect(body(adapter.requests.single), {'is_active': true});
        expect(bloc.state.outcome!.message, 'El plan «Revisión de UPS» fue activado.');
      },
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      'si ya está así no pide nada',
      build: build,
      act: (bloc) => bloc.add(ScheduleActiveChangeRequested(_plan(), active: true)),
      wait: const Duration(milliseconds: 50),
      expect: () => blockedWith('El plan «Revisión de UPS» ya está activo.'),
      verify: (_) => expect(adapter.requests, isEmpty),
    );

    blocTest<ScheduleActionsBloc, ScheduleActionsState>(
      'sin red',
      setUp: () => handler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red'),
      build: build,
      act: (bloc) => bloc.add(ScheduleActiveChangeRequested(_plan(), active: false)),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(ScheduleOutcomeKind.failed),
      verify: (bloc) {
        expect(bloc.state.outcome!.failure, isA<NetworkFailure>());
        expect(bloc.state.outcome!.message, startsWith('No se pudo desactivar el plan:'));
      },
    );
  });

  test('mientras hay una acción en curso no empieza otra', () async {
    final bloc = build();
    addTearDown(bloc.close);
    bloc
      ..add(create())
      ..add(create());
    await bloc.stream.firstWhere((state) => !state.busy && state.outcome != null);
    await pumpEventQueue();

    expect(adapter.requests, hasLength(1));
  });

  test('dos resultados iguales seguidos son estados distintos', () async {
    final bloc = build();
    addTearDown(bloc.close);
    final outcomes = <ScheduleOutcome>[];
    final subscription = bloc.stream.listen((state) => outcomes.add(state.outcome!));
    addTearDown(subscription.cancel);
    bloc
      ..add(create(equipmentId: null))
      ..add(create(equipmentId: null));
    await pumpEventQueue();

    expect(outcomes, hasLength(2));
    expect(outcomes.first.id, isNot(outcomes.last.id));
  });
}
