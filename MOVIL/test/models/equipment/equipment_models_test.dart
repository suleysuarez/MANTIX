import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/equipment/equipment_models.dart';

Map<String, Object?> equipmentItemJson({Map<String, Object?>? overrides}) => {
      'id': 7,
      'asset_tag': 'DEMO-007',
      'serial_number': 'SN-1',
      'equipment_type_id': 1,
      'equipment_type': {'id': 1, 'code': 'LAPTOP', 'name': 'Laptop'},
      'brand': 'Dell',
      'model': 'Latitude 5420',
      'description': null,
      'status': 'assigned',
      'created_at': '2026-10-01T10:00:00Z',
      'current_location': {'id': 3, 'code': 'HQ', 'name': 'Sede central'},
      'current_custodian': {'id': 9, 'full_name': 'Ana Pérez', 'email': 'ana@example.com'},
      'last_maintenance': {'performed_at': '2026-10-20T15:00:00Z', 'work_type': 'preventive', 'result': 'ok', 'technician_name': 'Luis'},
      ...?overrides,
    };

void main() {
  group('Equipment.fromJson', () {
    test('lee los datos del listado', () {
      final item = Equipment.fromJson(equipmentItemJson());

      expect(item.id, 7);
      expect(item.assetTag, 'DEMO-007');
      expect(item.brand, 'Dell');
      expect(item.model, 'Latitude 5420');
      expect(item.status, 'assigned');
      expect(item.typeCode, 'LAPTOP');
      expect(item.typeName, 'Laptop');
      expect(item.locationName, 'Sede central');
      expect(item.custodianName, 'Ana Pérez');
      expect(item.lastMaintenanceAt, DateTime.utc(2026, 10, 20, 15));
    });

    test('ubicación, custodio y mantenimiento pueden faltar', () {
      final item = Equipment.fromJson(equipmentItemJson(overrides: {'current_location': null, 'current_custodian': null, 'last_maintenance': null, 'serial_number': null}));

      expect(item.locationName, isNull);
      expect(item.custodianName, isNull);
      expect(item.lastMaintenanceAt, isNull);
      expect(item.serialNumber, isNull);
    });

    test('una categoría ausente no rompe la lectura', () {
      final item = Equipment.fromJson(equipmentItemJson(overrides: {'equipment_type': null}));

      expect(item.typeCode, '');
      expect(item.typeName, 'Sin categoría');
    });
  });

  group('EquipmentSummary', () {
    final summary = EquipmentSummary.fromJson({
      'total': 38,
      'by_status': {'assigned': 20, 'in_storage': 11, 'in_repair': 3, 'lost': 1, 'retired': 2, 'disposed': 1},
    });

    test('agrupa los estados igual que la web', () {
      expect(summary.count(EquipmentGroup.all), 38);
      expect(summary.count(EquipmentGroup.operational), 31);
      expect(summary.count(EquipmentGroup.maintenance), 3);
      expect(summary.count(EquipmentGroup.offline), 4);
    });

    test('la tasa operativa es operativos entre el total', () {
      expect(summary.operationalRate!.toStringAsFixed(1), '81.6');
    });

    test('un estado que no viene cuenta como cero y sin equipos no hay tasa', () {
      const empty = EquipmentSummary(total: 0, byStatus: {});

      expect(empty.count(EquipmentGroup.offline), 0);
      expect(empty.operationalRate, isNull);
    });
  });

  test('cada grupo envía a la API la lista de estados separada por comas', () {
    expect(EquipmentGroup.all.filter, isNull);
    expect(EquipmentGroup.operational.filter, 'assigned,in_storage');
    expect(EquipmentGroup.maintenance.filter, 'in_repair');
    expect(EquipmentGroup.offline.filter, 'lost,retired,disposed');
  });
  group('EquipmentType', () {
    test('lee la categoría', () {
      final type = EquipmentType.fromJson(const {'id': 2, 'code': 'PRINTER', 'name': 'Impresora'});

      expect(type, const EquipmentType(id: 2, code: 'PRINTER', name: 'Impresora'));
    });
  });

  group('NewEquipment.toJson', () {
    test('solo envía lo obligatorio cuando el resto está vacío', () {
      const equipment = NewEquipment(assetTag: 'EQ-029', typeId: 1, brand: 'Dell', model: 'Latitude', serialNumber: '', description: '', purchaseCost: '');

      expect(equipment.toJson(), {'asset_tag': 'EQ-029', 'equipment_type_id': 1, 'brand': 'Dell', 'model': 'Latitude'});
    });

    test('envía los opcionales con fechas AAAA-MM-DD', () {
      final equipment = NewEquipment(
        assetTag: 'EQ-029',
        typeId: 1,
        brand: 'Dell',
        model: 'Latitude',
        serialNumber: 'SN-1',
        description: 'i7, 16 GB',
        purchaseDate: DateTime(2026, 1, 5),
        purchaseCost: '1250.50',
        warrantyStart: DateTime(2026, 1, 5),
        warrantyEnd: DateTime(2029, 11, 30),
      );

      expect(equipment.toJson(), {
        'asset_tag': 'EQ-029',
        'equipment_type_id': 1,
        'brand': 'Dell',
        'model': 'Latitude',
        'serial_number': 'SN-1',
        'description': 'i7, 16 GB',
        'purchase_date': '2026-01-05',
        'purchase_cost': '1250.50',
        'warranty_start_date': '2026-01-05',
        'warranty_end_date': '2029-11-30',
      });
    });
  });
}
