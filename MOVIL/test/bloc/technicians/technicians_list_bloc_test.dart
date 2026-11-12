import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/bloc/technicians/technicians_list_bloc.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/technicians/technician_filters.dart';
import 'package:mantix/models/technicians/technician_models.dart';
import 'package:mantix/repositories/technicians/technicians_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';
import '../../support/technicians_support.dart';

void main() {
  late FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) handler;
  late TechniciansRepository repository;

  final four = [
    technicianJson(id: 1, name: 'Ana Demo', specialization: 'Redes'),
    technicianJson(id: 2, name: 'Luis Demo', specialization: 'Hardware'),
    technicianJson(id: 3, name: 'Marta Demo', specialization: 'Software', available: false),
    technicianJson(id: 4, name: 'Suley Suárez', specialization: 'Redes'),
  ];
  final loads = workloadJson({1: (1, 21), 2: (3, 15), 3: (0, 2)});

  setUp(() {
    handler = (options) => techniciansApi(options, technicians: four, workload: loads);
    adapter = FakeAdapter((options) => handler(options));
    repository = TechniciansRepository(dioWith(adapter));
  });

  TechniciansListBloc build() => TechniciansListBloc(repository: repository);

  /// Un bloc ya cargado con los cuatro técnicos y su carga.
  Future<TechniciansListBloc> loaded() async {
    final bloc = build()..add(const TechniciansRequested());
    addTearDown(bloc.close);
    await bloc.stream.firstWhere((state) => state.status == TechniciansStatus.ready);
    return bloc;
  }

  List<String> names(TechniciansListState state) => [for (final t in state.pageItems) t.fullName];

  group('carga', () {
    blocTest<TechniciansListBloc, TechniciansListState>(
      'trae los técnicos y la carga, ordenados por menor carga',
      build: build,
      act: (bloc) => bloc.add(const TechniciansRequested()),
      wait: const Duration(milliseconds: 50),
      skip: 1,
      verify: (bloc) {
        final state = bloc.state;
        expect(state.status, TechniciansStatus.ready);
        expect(state.hasWorkload, isTrue);
        expect(names(state), ['Marta Demo', 'Suley Suárez', 'Ana Demo', 'Luis Demo']);
        expect(state.summary, const TechnicianSummary(total: 4, available: 3, busy: 2, unavailable: 1, openTickets: 4, resolved: 38, overloaded: 1));
        expect(state.specialties, ['Hardware', 'Redes', 'Software']);
        expect(adapter.requests.map((r) => r.path), containsAll(['/technicians', '/dashboard/workload']));
      },
    );

    blocTest<TechniciansListBloc, TechniciansListState>(
      'si la carga falla, la lista sigue y los indicadores quedan no disponibles',
      setUp: () => handler = (options) => techniciansApi(options, technicians: four),
      build: build,
      act: (bloc) => bloc.add(const TechniciansRequested()),
      wait: const Duration(milliseconds: 50),
      skip: 1,
      verify: (bloc) {
        final state = bloc.state;
        expect(state.status, TechniciansStatus.ready);
        expect(state.hasWorkload, isFalse);
        expect(state.workloadFailure, isA<ServerFailure>());
        expect(state.failure, isNull);
        expect(names(state), ['Ana Demo', 'Luis Demo', 'Marta Demo', 'Suley Suárez'], reason: 'sin carga, por nombre');
        expect(state.summary.busy, 0);
      },
    );

    blocTest<TechniciansListBloc, TechniciansListState>(
      'sin permiso para ver la carga (403) la lista también sigue',
      setUp: () => handler = (options) => options.path == '/dashboard/workload' ? errorResponse(403, code: 'forbidden') : techniciansApi(options, technicians: four),
      build: build,
      act: (bloc) => bloc.add(const TechniciansRequested()),
      wait: const Duration(milliseconds: 50),
      skip: 1,
      verify: (bloc) {
        expect(bloc.state.status, TechniciansStatus.ready);
        expect(bloc.state.workloadFailure, isA<ForbiddenFailure>());
        expect(bloc.state.technicians, hasLength(4));
      },
    );

    blocTest<TechniciansListBloc, TechniciansListState>(
      'si fallan los técnicos, la pantalla queda en error con reintento',
      setUp: () => handler = (options) => options.path == '/technicians' ? errorResponse(500) : techniciansApi(options, workload: loads),
      build: build,
      act: (bloc) => bloc.add(const TechniciansRequested()),
      wait: const Duration(milliseconds: 50),
      skip: 1,
      verify: (bloc) {
        expect(bloc.state.status, TechniciansStatus.failure);
        expect(bloc.state.unavailable, isTrue);
        expect(bloc.state.failure, isA<ServerFailure>());
      },
    );

    blocTest<TechniciansListBloc, TechniciansListState>(
      'sin red llega un NetworkFailure',
      setUp: () => handler = (options) => throw DioException.connectionError(requestOptions: options, reason: 'sin red'),
      build: build,
      act: (bloc) => bloc.add(const TechniciansRequested()),
      wait: const Duration(milliseconds: 50),
      skip: 1,
      verify: (bloc) => expect(bloc.state.failure, isA<NetworkFailure>()),
    );

    test('sin técnicos queda lista y vacía', () async {
      handler = (options) => techniciansApi(options, workload: workloadJson({}));
      final bloc = await loaded();
      expect(bloc.state.technicians, isEmpty);
      expect(bloc.state.initialLoading, isFalse);
      expect(bloc.state.totalPages, 1);
    });

    test('una recarga que falla conserva lo que ya se veía', () async {
      final bloc = await loaded();
      handler = (_) => errorResponse(500);
      final done = Completer<void>();
      bloc.add(TechniciansRequested(done: done));
      await done.future;

      expect(bloc.state.status, TechniciansStatus.failure);
      expect(bloc.state.unavailable, isFalse);
      expect(bloc.state.technicians, hasLength(4));
      expect(bloc.state.hasWorkload, isTrue);
    });

    test('tirar para refrescar espera a que termine la carga', () async {
      final bloc = await loaded();
      final before = adapter.requests.length;
      final done = Completer<void>();
      bloc.add(TechniciansRequested(done: done));
      await done.future;
      expect(adapter.requests.length, before + 2);
      expect(bloc.state.status, TechniciansStatus.ready);
    });

    test('se recarga sola cuando alguien registra o edita un técnico', () async {
      final bloc = await loaded();
      final before = adapter.requests.where((r) => r.path == '/technicians' && r.method == 'GET').length;
      handler = (options) => options.method == 'PATCH' ? jsonResponse(200, technicianJson(id: 1, name: 'Ana Demo', available: false)) : techniciansApi(options, technicians: four, workload: loads);

      await repository.update(1, isAvailable: false);
      await bloc.stream.firstWhere((state) => state.status == TechniciansStatus.ready);

      expect(adapter.requests.where((r) => r.path == '/technicians' && r.method == 'GET').length, before + 1);
    });
  });

  group('búsqueda, filtros y orden', () {
    test('la búsqueda filtra en la app y vuelve a la página 1', () async {
      final bloc = await loaded();
      final before = adapter.requests.length;
      bloc
        ..add(const TechniciansPageSizeChanged(2))
        ..add(const TechniciansPageChanged(2))
        ..add(const TechniciansSearchChanged('suárez'));
      await pumpEventQueue();

      expect(names(bloc.state), ['Suley Suárez']);
      expect(bloc.state.page, 1);
      expect(adapter.requests.length, before, reason: 'no se pide nada al servidor');
    });

    test('los filtros de la hoja y la tarjeta de resumen', () async {
      final bloc = await loaded();
      bloc.add(const TechniciansFiltersChanged(TechnicianFilters(specialties: {'redes'})));
      await pumpEventQueue();
      expect(names(bloc.state), ['Suley Suárez', 'Ana Demo']);

      bloc.add(const TechniciansFiltersChanged(TechnicianFilters(status: TechnicianStatus.busy)));
      await pumpEventQueue();
      expect(names(bloc.state), ['Ana Demo', 'Luis Demo']);

      bloc.add(const TechniciansFiltersChanged(TechnicianFilters(loads: {LoadBucket.high})));
      await pumpEventQueue();
      expect(names(bloc.state), ['Luis Demo']);

      bloc.add(const TechniciansFiltersChanged(TechnicianFilters()));
      await pumpEventQueue();
      expect(bloc.state.filtered, hasLength(4));
    });

    test('cambiar el orden', () async {
      final bloc = await loaded();
      bloc.add(const TechniciansOrderChanged(TechnicianOrder.name));
      await pumpEventQueue();
      expect(names(bloc.state), ['Ana Demo', 'Luis Demo', 'Marta Demo', 'Suley Suárez']);
    });
  });

  group('paginación', () {
    test('reparte en páginas del tamaño elegido y no pasa de la última', () async {
      final bloc = await loaded();
      bloc.add(const TechniciansPageSizeChanged(3));
      await pumpEventQueue();
      expect(bloc.state.totalPages, 2);
      expect(names(bloc.state), hasLength(3));

      bloc.add(const TechniciansPageChanged(2));
      await pumpEventQueue();
      expect(names(bloc.state), ['Luis Demo']);

      bloc.add(const TechniciansPageChanged(9));
      await pumpEventQueue();
      expect(bloc.state.page, 2);
    });

    test('con todo en una página solo hay una', () async {
      final bloc = await loaded();
      expect(bloc.state.totalPages, 1);
      expect(bloc.state.page, 1);
    });

    test('si al recargar hay menos técnicos, vuelve a la última página que exista', () async {
      final bloc = await loaded();
      bloc
        ..add(const TechniciansPageSizeChanged(3))
        ..add(const TechniciansPageChanged(2));
      await pumpEventQueue();
      handler = (options) => techniciansApi(options, technicians: four.take(2).toList(), workload: loads);
      final done = Completer<void>();
      bloc.add(TechniciansRequested(done: done));
      await done.future;
      await pumpEventQueue();

      expect(bloc.state.page, 1);
      expect(names(bloc.state), hasLength(2));
    });
  });

  group('técnico recién registrado', () {
    final created = Technician.fromJson(technicianJson(id: 9, name: 'Zoe Nueva'));

    test('vuelve a la página 1 sin filtros y sale de primero', () async {
      final bloc = await loaded();
      bloc
        ..add(const TechniciansPageSizeChanged(2))
        ..add(const TechniciansPageChanged(2))
        ..add(const TechniciansFiltersChanged(TechnicianFilters(search: 'ana')))
        ..add(TechnicianCreatedShown(created));
      await pumpEventQueue();

      expect(bloc.state.filters, const TechnicianFilters());
      expect(bloc.state.page, 1);
      expect(bloc.state.pinnedId, 9);
      expect(names(bloc.state).first, 'Zoe Nueva');
      expect(bloc.state.technicians, hasLength(5));
    });

    test('deja de ir primero al cambiar los filtros o el orden', () async {
      final bloc = await loaded();
      bloc
        ..add(TechnicianCreatedShown(created))
        ..add(const TechniciansOrderChanged(TechnicianOrder.name));
      await pumpEventQueue();

      expect(bloc.state.pinnedId, isNull);
      expect(names(bloc.state).last, 'Zoe Nueva');
    });
  });
}
