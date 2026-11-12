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
    this.location, this.supplier,
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
  );

  @override
  List<Object?> get props => [id, sku, name, category, unit, unitCost, stock, minStock, maxStock, status, stockValue, description, location, supplier];
}

class InventoryOverview extends Equatable {
  const InventoryOverview({
    required this.stockValue, required this.lowStock, required this.outOfStock,
    required this.consumptionUnits, required this.consumptionValue,
  });
  final String stockValue;
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
    );
  }

  @override
  List<Object?> get props => [stockValue, lowStock, outOfStock, consumptionUnits, consumptionValue];
}

class InventoryPage extends Equatable {
  const InventoryPage({required this.items, this.info});
  final List<InventoryItem> items;
  final PageInfo? info;
  @override
  List<Object?> get props => [items, info];
}
