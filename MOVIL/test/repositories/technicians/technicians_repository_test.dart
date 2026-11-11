import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/error_messages.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/technicians/technician_models.dart';
import 'package:mantix/repositories/technicians/technicians_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';
import '../../support/technicians_support.dart';

void main() {
  TechniciansRepository repo(FakeAdapter adapter) => TechniciansRepository(dioWith(adapter));

  Object? body(RequestOptions request) => request.data is String ? jsonDecode(request.data as String) : request.data;

  group('list', () {
    test('pide la página, el tamaño, el orden, la búsqueda y el filtro de cuenta activa', () async {
      final adapter = FakeAdapter((_) => pagedResponse([technicianJson(specialization: 'Redes', available: false)], page: 2, totalPages: 3, total: 41));
      final result = await repo(adapter).list(search: '  luis ', page: 2, size: 10, isActive: true);

      expect(adapter.requests.single.path, '/technicians');
      expect(adapter.requests.single.queryParameters, {'page': 2, 'size': 10, 'sort': 'name', 'search': 'luis', 'is_active': true});
      expect(result.items.single.fullName, 'Luis Demo');
      expect(result.items.single.isAvailable, isFalse);
      expect(result.info?.total, 41);
      expect(result.info?.page, 2);
    });

    test('sin texto ni filtro no manda search ni is_active', () async {
      final adapter = FakeAdapter((_) => pagedResponse([technicianJson()]));
      await repo(adapter).list();
      expect(adapter.requests.single.queryParameters.keys, isNot(anyOf(contains('search'), contains('is_active'))));
    });

    test('sin el permiso de ver técnicos llega un ForbiddenFailure', () async {
      final adapter = FakeAdapter((_) => errorResponse(403, code: 'forbidden'));
      await expectLater(repo(adapter).list(), throwsA(isA<ForbiddenFailure>()));
    });
  });

  group('modelo', () {
    test('lee todos los campos; la tarifa llega como texto decimal', () {
      final technician = Technician.fromJson(technicianJson(id: 7, name: 'Ana Demo', code: 'TEC-07', specialization: 'Redes', rate: '35.00'));
      expect(technician.id, 7);
      expect(technician.userId, 107);
      expect(technician.email, 'tech7@demo.mantix.co');
      expect(technician.employeeCode, 'TEC-07');
      expect(technician.hourlyRate, 35.0);
      expect(technician.createdAt, DateTime.utc(2026, 10, 1, 10));
    });

    test('sin tarifa (oculta a quien no edita) y sin is_active (servidor antiguo)', () {
      final technician = Technician.fromJson({'id': 1, 'full_name': 'X'});
      expect(technician.hourlyRate, isNull);
      expect(technician.isActive, isTrue);
      expect(technician.isAvailable, isTrue);
      expect(technician.email, '');
    });
  });

  group('all', () {
    test('trae el catálogo completo, siguiendo las páginas que haya', () async {
      final adapter = FakeAdapter((options) {
        final page = options.queryParameters['page'] as int;
        return pagedResponse([technicianJson(id: page, name: 'Técnico $page')], page: page, totalPages: 3, total: 3);
      });
      final technicians = await repo(adapter).all();

      expect(technicians.map((t) => t.id), [1, 2, 3]);
      expect(adapter.requests.map((r) => r.queryParameters['page']), [1, 2, 3]);
      expect(adapter.requests.first.queryParameters['size'], TechniciansRepository.allPageSize);
    });

    test('sin cabeceras de paginación se queda con la primera respuesta', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, [technicianJson()]));
      expect(await repo(adapter).all(), hasLength(1));
      expect(adapter.requests, hasLength(1));
    });
  });

  test('workload lee la ventana y la carga por técnico', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, workloadJson({5: (3, 15), 6: (0, 2)}, days: 30, scope: 'own')));
    final workload = await repo(adapter).workload();

    expect(adapter.requests.single.path, '/dashboard/workload');
    expect(adapter.requests.single.queryParameters, {'days': 30});
    expect(workload.windowDays, 30);
    expect(workload.scope, 'own');
    expect(workload.openOf(5), 3);
    expect(workload.resolvedOf(5), 15);
    expect(workload.openOf(99), 0, reason: 'un técnico sin fila no tiene tickets');
  });

  test('performance lee los indicadores, con sus avisos de pocos datos y los excluidos del SLA', () async {
    final adapter = FakeAdapter((_) => jsonResponse(200, performanceJson([
          performanceRowJson(id: 5, mttr: 12.5, sla: 86.7, slaN: 12, excluded: 3, reopened: 1),
          performanceRowJson(id: 6, resolved: 2, mttr: 4, lowSample: true, sla: null, slaN: 0, excluded: 2, reopened: 0),
        ])));
    final report = await repo(adapter).performance();

    expect(adapter.requests.single.path, '/dashboard/technicians');
    expect(adapter.requests.single.queryParameters, {'period': '30d'});
    expect(report.period, '30d');
    expect(
      report.byTechnician[5],
      const TechnicianPerformance(technicianId: 5, openTickets: 3, resolved: 15, mttrMedianHours: 12.5, sampleSize: 15, slaCompliancePct: 86.7, slaSampleSize: 12, slaExcludedNoSla: 3, reopened: 1),
    );
    final few = report.byTechnician[6]!;
    expect(few.lowSample, isTrue);
    expect(few.mttrMedianHours, 4.0);
    expect(few.slaCompliancePct, isNull);
    expect(few.slaExcludedNoSla, 2);
  });

  group('create', () {
    test('manda POST con el usuario, la especialización y la tarifa con dos decimales, y avisa', () async {
      final adapter = FakeAdapter((_) => jsonResponse(201, technicianJson(id: 9, name: 'Nueva Persona', rate: '35.50')));
      final repository = repo(adapter);
      final changes = <void>[];
      final subscription = repository.changes.listen(changes.add);
      addTearDown(subscription.cancel);

      final created = await repository.create(userId: 7, specialization: 'Redes', hourlyRate: 35.5);
      await pumpEventQueue();

      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/technicians');
      expect(body(adapter.requests.single), {'user_id': 7, 'specialization': 'Redes', 'hourly_rate': '35.50'});
      expect(created.id, 9);
      expect(created.hourlyRate, 35.5);
      expect(changes, hasLength(1));
    });

    test('un usuario que ya tiene perfil llega como conflicto con su mensaje', () async {
      final adapter = FakeAdapter((_) => errorResponse(409, code: 'technician_profile_exists'));
      final repository = repo(adapter);
      final changes = <void>[];
      final subscription = repository.changes.listen(changes.add);
      addTearDown(subscription.cancel);

      await expectLater(
        repository.create(userId: 7),
        throwsA(isA<ConflictFailure>().having((f) => f.message, 'mensaje', messagesByErrorCode['technician_profile_exists'])),
      );
      await pumpEventQueue();
      expect(changes, isEmpty, reason: 'un alta fallida no recarga la lista');
    });
  });

  group('update', () {
    test('solo viaja lo que se pasa; null borra el dato', () async {
      final adapter = FakeAdapter((_) => jsonResponse(200, technicianJson()));
      final repository = repo(adapter);

      await repository.update(5, specialization: (value: null), hourlyRate: (value: 40));
      expect(adapter.requests.last.method, 'PATCH');
      expect(adapter.requests.last.path, '/technicians/5');
      expect(body(adapter.requests.last), {'specialization': null, 'hourly_rate': '40.00'});

      await repository.update(5, isAvailable: false);
      expect(body(adapter.requests.last), {'is_available': false});
    });

    test('un técnico que ya no existe llega como NotFoundFailure', () async {
      final adapter = FakeAdapter((_) => errorResponse(404, code: 'technician_not_found'));
      await expectLater(repo(adapter).update(5, isAvailable: true), throwsA(isA<NotFoundFailure>()));
    });
  });
}
