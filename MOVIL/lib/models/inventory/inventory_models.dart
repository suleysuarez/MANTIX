import 'package:equatable/equatable.dart';

import '../page_info.dart';

class InventoryOption extends Equatable {
  const InventoryOption({required this.kind, required this.value, required this.label});
  final String kind;
  final String value;
  final String label;

  factory InventoryOption.fromJson(Map<String, Object?> json) => InventoryOption(
    kind: json['kind'] as String? ?? '',
    value: json['value'] as String? ?? '',
    label: json['label'] as String? ?? json['value'] as String? ?? '',
  );

  @override
  List<Object?> get props => [kind, value, label];
}

class InventoryItem extends Equatable {
  const InventoryItem({
    required this.id, required this.sku, required this.name, required this.category,
    required this.unit, required this.unitCost, required this.stock, required this.minStock,
    required this.status, required this.stockValue, this.description, this.maxStock,
    this.location, this.supplier, this.createdAt, this.levelPct,
  });
  final int id;
  final String sku;
  final String name;
  final String category;
  final String unit;
  final String unitCost;
  final int stock;
  final int minStock;
  final int? maxStock;
  final String status;
  final String stockValue;
  final String? description;
  final String? location;
  final String? supplier;

  /// Cuándo se creó el ítem (`created_at`); `null` si el servidor no lo envía.
  final DateTime? createdAt;

  /// Stock frente al máximo (o al doble del mínimo si no hay máximo), de 0 a 100; `null` si no llega.
  final double? levelPct;

  factory InventoryItem.fromJson(Map<String, Object?> json) => InventoryItem(
    id: json['id'] as int,
    sku: json['sku'] as String? ?? '',
    name: json['name'] as String? ?? '',
    category: json['category'] as String? ?? 'other',
    unit: json['unit'] as String? ?? 'unidad',
    unitCost: '${json['unit_cost'] ?? '0'}',
    stock: json['stock'] as int? ?? 0,
    minStock: json['min_stock'] as int? ?? 0,
    maxStock: json['max_stock'] as int?,
    status: json['status'] as String? ?? 'ok',
    stockValue: '${json['stock_value'] ?? '0'}',
    description: json['description'] as String?,
    location: json['location'] as String?,
    supplier: json['supplier'] as String?,
    createdAt: _dateOrNull(json['created_at']),
    levelPct: json['level_pct'] is num ? (json['level_pct']! as num).toDouble() : null,
  );

  @override
  List<Object?> get props => [id, sku, name, category, unit, unitCost, stock, minStock, maxStock, status, stockValue, description, location, supplier, createdAt, levelPct];
}

DateTime? _dateOrNull(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// Una fila del historial de un ítem (`GET /inventory/items/{id}/movements`).
///
/// [quantity] lleva signo: las entradas son positivas y los consumos, negativos. La carga inicial
/// de un ítem nuevo llega como una entrada con la nota «Carga inicial».
class InventoryMovement extends Equatable {
  const InventoryMovement({
    required this.id, required this.itemId, required this.kind, required this.quantity,
    required this.stockAfter, this.unitCost, this.notes, this.createdBy, this.createdAt,
  });
  final int id;
  final int itemId;

  /// `in`, `out` o `adjust`.
  final String kind;
  final int quantity;
  final int stockAfter;
  final String? unitCost;
  final String? notes;
  final String? createdBy;
  final DateTime? createdAt;

  /// Es la entrada que el servidor crea al dar de alta un ítem con existencias.
  bool get isInitialLoad => kind == 'in' && notes == initialLoadNote;

  static const initialLoadNote = 'Carga inicial';

  factory InventoryMovement.fromJson(Map<String, Object?> json) => InventoryMovement(
    id: json['id'] as int,
    itemId: json['item_id'] as int? ?? 0,
    kind: json['kind'] as String? ?? 'adjust',
    quantity: json['quantity'] as int? ?? 0,
    stockAfter: json['stock_after'] as int? ?? 0,
    unitCost: json['unit_cost'] == null ? null : '${json['unit_cost']}',
    notes: json['notes'] as String?,
    createdBy: json['created_by'] as String?,
    createdAt: _dateOrNull(json['created_at']),
  );

  @override
  List<Object?> get props => [id, itemId, kind, quantity, stockAfter, unitCost, notes, createdBy, createdAt];
}

class InventoryOverview extends Equatable {
  const InventoryOverview({
    required this.stockValue, required this.lowStock, required this.outOfStock,
    required this.consumptionUnits, required this.consumptionValue, this.stockChangePct,
    this.activeItems = 0, this.previousConsumptionUnits = 0,
  });
  final String stockValue;

  /// Variación del valor del stock frente al inicio del periodo; `null` si no hay referencia.
  final double? stockChangePct;

  /// Ítems activos contados (`stock_value.items`): la base de las rayitas de «Por reponer» y «Agotados».
  final int activeItems;

  /// Unidades consumidas en el periodo anterior: la referencia de la rayita de «Consumo».
  final int previousConsumptionUnits;
  final int lowStock;
  final int outOfStock;
  final int consumptionUnits;
  final String consumptionValue;

  factory InventoryOverview.fromJson(Map<String, Object?> json) {
    final value = json['stock_value'] is Map ? (json['stock_value'] as Map).cast<String, Object?>() : const <String, Object?>{};
    final consumption = json['consumption'] is Map ? (json['consumption'] as Map).cast<String, Object?>() : const <String, Object?>{};
    return InventoryOverview(
      stockValue: '${value['total'] ?? '0'}',
      lowStock: json['low_stock'] as int? ?? 0,
      outOfStock: json['out_of_stock'] as int? ?? 0,
      consumptionUnits: consumption['units'] as int? ?? 0,
      consumptionValue: '${consumption['value'] ?? '0'}',
      activeItems: value['items'] as int? ?? 0,
      previousConsumptionUnits: consumption['previous_units'] as int? ?? 0,
      stockChangePct: value['change_pct'] is num ? (value['change_pct']! as num).toDouble() : null,
    );
  }

  @override
  List<Object?> get props => [stockValue, lowStock, outOfStock, consumptionUnits, consumptionValue, stockChangePct, activeItems, previousConsumptionUnits];
}

class InventoryPage extends Equatable {
  const InventoryPage({required this.items, this.info});
  final List<InventoryItem> items;
  final PageInfo? info;
  @override
  List<Object?> get props => [items, info];
}
