import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/core/errors/failure.dart';
import 'package:mantix/models/equipment/equipment_models.dart';
import 'package:mantix/models/equipment/maintenance_record_models.dart';
import 'package:mantix/repositories/equipment/equipment_repository.dart';

import '../../support/fakes.dart';
import '../../support/requests_support.dart';

Map<String, Object?> record({String? total = '55.50'}) => {
      'id': 3,
      'equipment_id': 7,
      'request_id': null,
      'technician_id': 2,
      'work_type': 'corrective',
      'started_at': '2026-10-12T10:00:00Z',
      'completed_at': null,
      'diagnosis': 'Pantalla negra',
      'actions_taken': 'Cambio de cable',
      'result': 'resolved',
      'labor_cost': total == null ? null : '40.00',
      'parts_cost': total == null ? null : '15.50',
      'total_cost': total,
      'notes': null,
    };

void main() {
  group('maintenanceRecords', () {
    test('pide la página y el tamaño del equipo y lee los registros y el total', () async {
      final adapter = FakeAdapter((_) => pagedResponse([record()], total: 12, totalPages: 2));
      final result = await EquipmentRepository(dioWith(adapter)).maintenanceRecords(7, page: 1, size: 10);

      expect(adapter.requests.single.path, '/equipment/7/maintenance-records');
      expect(adapter.requests.single.queryParameters, {'page': 1, 'size': 10});
      expect(result.items.single.diagnosis, 'Pantalla negra');
      expect(result.info?.total, 12);
    });

    test('sin permiso llega un ForbiddenFailure y un equipo que no existe, un NotFoundFailure', () async {
      final repository = EquipmentRepository(dioWith(FakeAdapter((_) => errorResponse(403, code: 'forbidden'))));
      await expectLater(repository.maintenanceRecords(7), throwsA(isA<ForbiddenFailure>()));

      final missing = EquipmentRepository(dioWith(FakeAdapter((_) => errorResponse(404, code: 'equipment_not_found'))));
      await expectLater(missing.maintenanceRecords(7), throwsA(isA<NotFoundFailure>()));
    });
  });

  group('MaintenanceRecord', () {
    test('lee los campos, las fechas locales y los costos como texto', () {
      final parsed = MaintenanceRecord.fromJson(record());

      expect(parsed.id, 3);
      expect(parsed.workType, 'corrective');
      expect(parsed.workTypeLabel, 'Correctivo');
      expect(parsed.resultLabel, 'Resolved');
      expect(parsed.startedAt, DateTime.parse('2026-10-12T10:00:00Z').toLocal());
      expect(parsed.completedAt, isNull);
      expect(parsed.totalCost, '55.50');
    });

    test('sin permiso para ver costos llegan vacíos', () {
      final parsed = MaintenanceRecord.fromJson(record(total: null));
      expect([parsed.laborCost, parsed.partsCost, parsed.totalCost], everyElement(isNull));
    });

    test('los tipos de trabajo se traducen y uno nuevo del servidor se muestra tal cual', () {
      String label(String type) => MaintenanceRecord.fromJson({...record(), 'work_type': type}).workTypeLabel;
      expect([for (final type in ['corrective', 'preventive', 'inspection', 'installation', 'recovery', 'other']) label(type)], ['Correctivo', 'Preventivo', 'Inspección', 'Instalación', 'Recuperación', 'Otro']);
      expect(label('calibration'), 'calibration');
    });

    test('el resultado se muestra con mayúscula inicial y sin guiones bajos', () {
      expect(MaintenanceRecord.fromJson({...record(), 'result': 'partially_resolved'}).resultLabel, 'Partially resolved');
      expect(MaintenanceRecord.fromJson({...record(), 'result': ''}).resultLabel, '');
    });
  });

  group('createType', () {
    test('manda el nombre y lee la categoría creada', () async {
      final adapter = FakeAdapter((_) => jsonResponse(201, {'id': 9, 'code': 'PROYECTOR_HD', 'name': 'Proyector HD'}));
      final created = await EquipmentRepository(dioWith(adapter)).createType('Proyector HD');

      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/equipment/types');
      expect(adapter.requests.single.data, {'name': 'Proyector HD'});
      expect(created, const EquipmentType(id: 9, code: 'PROYECTOR_HD', name: 'Proyector HD'));
    });

    test('un nombre repetido llega como ConflictFailure con el código específico', () async {
      final repository = EquipmentRepository(dioWith(FakeAdapter((_) => errorResponse(409, code: 'equipment_type_name_taken'))));

      await expectLater(
        repository.createType('laptop'),
        throwsA(isA<ConflictFailure>().having((failure) => failure.code, 'code', 'equipment_type_name_taken')),
      );
    });

    test('un nombre inválido llega como ValidationFailure con el campo', () async {
      final repository = EquipmentRepository(dioWith(FakeAdapter((_) => errorResponse(422, code: 'validation_error', errors: [
            {'field': 'body.name', 'message': 'demasiado corto', 'type': 'string_too_short'},
          ]))));

      await expectLater(repository.createType('a'), throwsA(isA<ValidationFailure>()));
    });
  });
}
