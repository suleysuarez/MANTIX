import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/technicians/technician_actions_bloc.dart';
import 'package:mantix/core/errors/error_messages.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/technicians/technician_models.dart';
import 'package:mantix/repositories/technicians/technicians_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';
import '../../support/technicians_support.dart';

Technician _tech({bool available = true, String? specialization = 'Hardware', String? rate = '35.00'}) =>
    Technician.fromJson(technicianJson(id: 5, name: 'Luis Demo', available: available, specialization: specialization, rate: rate));

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;

  setUp(() {
    handler = (_) => jsonResponse(200, technicianJson(id: 5, name: 'Luis Demo'));
    adapter = FakeAdapter((options) => handler(options));
  });

  TechnicianActionsBloc build() => TechnicianActionsBloc(repository: TechniciansRepository(dioWith(adapter)));

  Object? body(RequestOptions request) => request.data is String ? jsonDecode(request.data as String) : request.data;

  /// Los estados que debe emitir una acción que llega al servidor: en curso y resultado.
  List<Matcher> ranWith(TechnicianOutcomeKind kind) => [
        isA<TechnicianActionsState>().having((s) => s.busy, 'busy', isTrue),
        isA<TechnicianActionsState>().having((s) => s.busy, 'busy', isFalse).having((s) => s.outcome?.kind, 'resultado', kind),
      ];

  /// El único estado de una acción que ni se pide: bloqueada con [message].
  List<Matcher> blockedWith(String message) => [
        isA<TechnicianActionsState>()
            .having((s) => s.busy, 'busy', isFalse)
            .having((s) => s.outcome?.kind, 'resultado', TechnicianOutcomeKind.blocked)
            .having((s) => s.outcome?.message, 'mensaje', message),
      ];

  group('registrar', () {
    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'manda el alta con los textos recortados y la tarifa con coma, y avisa en español',
      setUp: () => handler = (_) => jsonResponse(201, technicianJson(id: 9, name: 'Nueva Persona', rate: '35.50')),
      build: build,
      act: (bloc) => bloc.add(const TechnicianCreateRequested(userId: 7, specialization: '  Redes, Hardware ', rate: ' 35,5 ')),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.succeeded),
      verify: (bloc) {
        expect(adapter.requests.single.method, 'POST');
        expect(body(adapter.requests.single), {'user_id': 7, 'specialization': 'Redes, Hardware', 'hourly_rate': '35.50'});
        final outcome = bloc.state.outcome!;
        expect(outcome.message, 'Técnico «Nueva Persona» registrado.');
        expect(outcome.created, isTrue);
        expect(outcome.technician?.id, 9);
        expect(outcome.isError, isFalse);
      },
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'sin especialización ni tarifa manda null',
      build: build,
      act: (bloc) => bloc.add(const TechnicianCreateRequested(userId: 7, specialization: '   ', rate: '')),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.succeeded),
      verify: (_) => expect(body(adapter.requests.single), {'user_id': 7, 'specialization': null, 'hourly_rate': null}),
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'sin usuario elegido no pide nada',
      build: build,
      act: (bloc) => bloc.add(const TechnicianCreateRequested(userId: null, specialization: 'Redes')),
      wait: const Duration(milliseconds: 50),
      expect: () => blockedWith('Selecciona el usuario al que pertenece el perfil de técnico.'),
      verify: (_) => expect(adapter.requests, isEmpty),
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'una tarifa negativa no pide nada',
      build: build,
      act: (bloc) => bloc.add(const TechnicianCreateRequested(userId: 7, rate: '-5')),
      wait: const Duration(milliseconds: 50),
      expect: () => blockedWith('La tarifa por hora debe ser un número igual o mayor a cero.'),
      verify: (_) => expect(adapter.requests, isEmpty),
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'una tarifa con tres decimales no pide nada',
      build: build,
      act: (bloc) => bloc.add(const TechnicianCreateRequested(userId: 7, rate: '35,123')),
      wait: const Duration(milliseconds: 50),
      expect: () => blockedWith('La tarifa por hora admite como máximo dos decimales.'),
      verify: (_) => expect(adapter.requests, isEmpty),
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'una especialización de más de 100 caracteres no pide nada',
      build: build,
      act: (bloc) => bloc.add(TechnicianCreateRequested(userId: 7, specialization: 'a' * 101)),
      wait: const Duration(milliseconds: 50),
      expect: () => blockedWith('La especialización no puede superar los 100 caracteres.'),
      verify: (_) => expect(adapter.requests, isEmpty),
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      '409: el usuario ya tiene perfil de técnico',
      setUp: () => handler = (_) => errorResponse(409, code: 'technician_profile_exists'),
      build: build,
      act: (bloc) => bloc.add(const TechnicianCreateRequested(userId: 7)),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.failed),
      verify: (bloc) {
        final outcome = bloc.state.outcome!;
        expect(outcome.failure, isA<ConflictFailure>());
        expect(outcome.message, 'No se pudo registrar el técnico: ${messagesByErrorCode['technician_profile_exists']}');
        expect(outcome.message, isNot(contains('detalle interno')));
        expect(outcome.isError, isTrue);
      },
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      '404: el usuario ya no existe o está inactivo',
      setUp: () => handler = (_) => errorResponse(404, code: 'user_not_found'),
      build: build,
      act: (bloc) => bloc.add(const TechnicianCreateRequested(userId: 7)),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.failed),
      verify: (bloc) => expect(bloc.state.outcome!.message, contains(messagesByErrorCode['user_not_found']!)),
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      '403: sin permiso para registrar',
      setUp: () => handler = (_) => errorResponse(403, code: 'forbidden'),
      build: build,
      act: (bloc) => bloc.add(const TechnicianCreateRequested(userId: 7)),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.failed),
      verify: (bloc) {
        expect(bloc.state.outcome!.failure, isA<ForbiddenFailure>());
        expect(bloc.state.outcome!.message, contains('No tienes permiso'));
      },
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'sin red',
      setUp: () => handler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red'),
      build: build,
      act: (bloc) => bloc.add(const TechnicianCreateRequested(userId: 7)),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.failed),
      verify: (bloc) => expect(bloc.state.outcome!.failure, isA<NetworkFailure>()),
    );
  });

  group('editar', () {
    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'solo manda lo que cambió',
      build: build,
      act: (bloc) => bloc.add(TechnicianEditRequested(_tech(), specialization: 'Hardware', rate: '40')),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.succeeded),
      verify: (bloc) {
        expect(adapter.requests.single.method, 'PATCH');
        expect(adapter.requests.single.path, '/technicians/5');
        expect(body(adapter.requests.single), {'hourly_rate': '40.00'});
        expect(bloc.state.outcome!.message, 'Perfil de Luis Demo actualizado.');
        expect(bloc.state.outcome!.created, isFalse);
      },
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'vaciar un campo lo borra',
      build: build,
      act: (bloc) => bloc.add(TechnicianEditRequested(_tech(), specialization: '  ', rate: '')),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.succeeded),
      verify: (_) => expect(body(adapter.requests.single), {'specialization': null, 'hourly_rate': null}),
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'sin cambios (la misma tarifa escrita de otra forma) no pide nada',
      build: build,
      act: (bloc) => bloc.add(TechnicianEditRequested(_tech(), specialization: ' Hardware ', rate: '35,0')),
      wait: const Duration(milliseconds: 50),
      expect: () => blockedWith('No hay cambios que guardar.'),
      verify: (_) => expect(adapter.requests, isEmpty),
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'una tarifa que no es número no pide nada',
      build: build,
      act: (bloc) => bloc.add(TechnicianEditRequested(_tech(), specialization: 'Hardware', rate: 'mucho')),
      wait: const Duration(milliseconds: 50),
      expect: () => blockedWith('La tarifa por hora debe ser un número igual o mayor a cero.'),
      verify: (_) => expect(adapter.requests, isEmpty),
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      '403: sin permiso para editar',
      setUp: () => handler = (_) => errorResponse(403, code: 'forbidden'),
      build: build,
      act: (bloc) => bloc.add(TechnicianEditRequested(_tech(), specialization: 'Redes', rate: '35')),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.failed),
      verify: (bloc) => expect(bloc.state.outcome!.message, startsWith('No se pudo actualizar a Luis Demo:')),
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      '404: el técnico ya no existe',
      setUp: () => handler = (_) => errorResponse(404, code: 'technician_not_found'),
      build: build,
      act: (bloc) => bloc.add(TechnicianEditRequested(_tech(), specialization: 'Redes', rate: '35')),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.failed),
      verify: (bloc) => expect(bloc.state.outcome!.message, contains(messagesByErrorCode['technician_not_found']!)),
    );
  });

  group('disponibilidad', () {
    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'marca como no disponible y avisa',
      build: build,
      act: (bloc) => bloc.add(TechnicianAvailabilityRequested(_tech(), available: false)),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.succeeded),
      verify: (bloc) {
        expect(body(adapter.requests.single), {'is_available': false});
        expect(bloc.state.outcome!.message, 'Luis Demo ahora está no disponible.');
      },
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'vuelve a marcar como disponible',
      build: build,
      act: (bloc) => bloc.add(TechnicianAvailabilityRequested(_tech(available: false), available: true)),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.succeeded),
      verify: (bloc) {
        expect(body(adapter.requests.single), {'is_available': true});
        expect(bloc.state.outcome!.message, 'Luis Demo ahora está disponible.');
      },
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'si ya está así no pide nada',
      build: build,
      act: (bloc) => bloc.add(TechnicianAvailabilityRequested(_tech(), available: true)),
      wait: const Duration(milliseconds: 50),
      expect: () => blockedWith('Luis Demo ya está disponible.'),
      verify: (_) => expect(adapter.requests, isEmpty),
    );

    blocTest<TechnicianActionsBloc, TechnicianActionsState>(
      'sin red',
      setUp: () => handler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red'),
      build: build,
      act: (bloc) => bloc.add(TechnicianAvailabilityRequested(_tech(), available: false)),
      wait: const Duration(milliseconds: 50),
      expect: () => ranWith(TechnicianOutcomeKind.failed),
      verify: (bloc) {
        expect(bloc.state.outcome!.failure, isA<NetworkFailure>());
        expect(bloc.state.outcome!.message, startsWith('No se pudo marcar a Luis Demo como no disponible:'));
      },
    );
  });

  test('mientras hay una acción en curso no empieza otra', () async {
    final bloc = build();
    addTearDown(bloc.close);
    bloc
      ..add(const TechnicianCreateRequested(userId: 7))
      ..add(const TechnicianCreateRequested(userId: 8));
    await bloc.stream.firstWhere((state) => !state.busy && state.outcome != null);
    await pumpEventQueue();

    expect(adapter.requests, hasLength(1));
  });

  test('dos resultados iguales seguidos son estados distintos', () async {
    final bloc = build();
    addTearDown(bloc.close);
    final outcomes = <TechnicianOutcome>[];
    final subscription = bloc.stream.listen((state) => outcomes.add(state.outcome!));
    addTearDown(subscription.cancel);
    bloc
      ..add(const TechnicianCreateRequested(userId: null))
      ..add(const TechnicianCreateRequested(userId: null));
    await pumpEventQueue();

    expect(outcomes, hasLength(2));
    expect(outcomes.first.id, isNot(outcomes.last.id));
  });
}
