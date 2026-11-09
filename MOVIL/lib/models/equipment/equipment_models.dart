import 'package:equatable/equatable.dart';

/// Agrupación de estados de las tarjetas de resumen; es la misma que usa la web.
enum EquipmentGroup {
  all(null),
  operational(['assigned', 'in_storage']),
  maintenance(['in_repair']),
  offline(['lost', 'retired', 'disposed']);

  const EquipmentGroup(this.statuses);

  /// Estados del grupo; `null` para el catálogo completo.
  final List<String>? statuses;

  /// Valor del filtro `status` de la API (lista separada por comas); `null`: todo.
  String? get filter => statuses?.join(',');
}

Map<String, Object?>? _map(Object? value) => value is Map ? value.cast<String, Object?>() : null;

/// Un equipo del catálogo, con lo que muestra el listado.
class Equipment extends Equatable {
  const Equipment({
    required this.id,
    required this.assetTag,
    required this.brand,
    required this.model,
    required this.status,
    required this.typeCode,
    required this.typeName,
    this.serialNumber,
    this.locationName,
    this.custodianName,
    this.lastMaintenanceAt,
  });

  factory Equipment.fromJson(Map<String, Object?> json) {
    final type = _map(json['equipment_type']);
    final lastMaintenance = _map(json['last_maintenance']);
    return Equipment(
      id: json['id']! as int,
      assetTag: json['asset_tag']! as String,
      serialNumber: json['serial_number'] as String?,
      brand: json['brand']! as String,
      model: json['model']! as String,
      status: json['status']! as String,
      typeCode: (type?['code'] as String?) ?? '',
      typeName: (type?['name'] as String?) ?? 'Sin categoría',
      locationName: _map(json['current_location'])?['name'] as String?,
      custodianName: _map(json['current_custodian'])?['full_name'] as String?,
      lastMaintenanceAt: DateTime.tryParse((lastMaintenance?['performed_at'] as String?) ?? ''),
    );
  }

  final int id;
  final String assetTag;
  final String? serialNumber;
  final String brand;
  final String model;
  final String status;
  final String typeCode;
  final String typeName;
  final String? locationName;
  final String? custodianName;
  final DateTime? lastMaintenanceAt;

  @override
  List<Object?> get props => [id, assetTag, serialNumber, brand, model, status, typeCode, typeName, locationName, custodianName, lastMaintenanceAt];
}

/// Contadores del catálogo por estado (`GET /equipment/summary`).
class EquipmentSummary extends Equatable {
  const EquipmentSummary({required this.total, required this.byStatus});

  factory EquipmentSummary.fromJson(Map<String, Object?> json) {
    final byStatus = _map(json['by_status']) ?? const <String, Object?>{};
    return EquipmentSummary(
      total: (json['total']! as num).toInt(),
      byStatus: {for (final entry in byStatus.entries) entry.key: (entry.value as num).toInt()},
    );
  }

  final int total;
  final Map<String, int> byStatus;

  int count(EquipmentGroup group) {
    final statuses = group.statuses;
    if (statuses == null) return total;
    return statuses.fold(0, (sum, status) => sum + (byStatus[status] ?? 0));
  }

  /// Porcentaje de equipos operativos sobre el total (`null` sin equipos).
  double? get operationalRate => total == 0 ? null : count(EquipmentGroup.operational) / total * 100;

  @override
  List<Object?> get props => [total, byStatus];
}

/// Categoría de equipo (`GET /equipment/types`).
class EquipmentType extends Equatable {
  const EquipmentType({required this.id, required this.code, required this.name});

  factory EquipmentType.fromJson(Map<String, Object?> json) => EquipmentType(
        id: json['id']! as int,
        code: (json['code'] as String?) ?? '',
        name: json['name']! as String,
      );

  final int id;
  final String code;
  final String name;

  @override
  List<Object?> get props => [id, code, name];
}

String _isoDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Datos del formulario «Nuevo equipo» (`POST /equipment`). El estado inicial lo fija el servidor.
class NewEquipment extends Equatable {
  const NewEquipment({
    required this.assetTag,
    required this.typeId,
    required this.brand,
    required this.model,
    this.serialNumber,
    this.description,
    this.purchaseDate,
    this.purchaseCost,
    this.warrantyStart,
    this.warrantyEnd,
  });

  final String assetTag;
  final int typeId;
  final String brand;
  final String model;
  final String? serialNumber;
  final String? description;
  final DateTime? purchaseDate;

  /// Importe con punto decimal y como máximo dos decimales (por ejemplo `1250.50`).
  final String? purchaseCost;
  final DateTime? warrantyStart;
  final DateTime? warrantyEnd;

  /// Solo se envían los campos opcionales que tienen valor.
  Map<String, Object?> toJson() => {
        'asset_tag': assetTag,
        'equipment_type_id': typeId,
        'brand': brand,
        'model': model,
        if (serialNumber != null && serialNumber!.isNotEmpty) 'serial_number': serialNumber,
        if (description != null && description!.isNotEmpty) 'description': description,
        if (purchaseDate != null) 'purchase_date': _isoDate(purchaseDate!),
        if (purchaseCost != null && purchaseCost!.isNotEmpty) 'purchase_cost': purchaseCost,
        if (warrantyStart != null) 'warranty_start_date': _isoDate(warrantyStart!),
        if (warrantyEnd != null) 'warranty_end_date': _isoDate(warrantyEnd!),
      };

  @override
  List<Object?> get props => [assetTag, typeId, brand, model, serialNumber, description, purchaseDate, purchaseCost, warrantyStart, warrantyEnd];
}
