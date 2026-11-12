import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/models/inventory/inventory_models.dart';

void main() {
  test('decodifica un insumo y conserva los datos de existencias', () {
    final item = InventoryItem.fromJson({
      'id': 7,
      'sku': 'CAB-USB-01',
      'name': 'Cable USB-C',
      'description': null,
      'category': 'accessory',
      'unit': 'unidad',
      'unit_cost': '12.50',
      'stock': 8,
      'min_stock': 3,
      'max_stock': 20,
      'location': 'Almacén',
      'supplier': 'Proveedor Demo',
      'status': 'ok',
      'stock_value': '100.00',
    });

    expect(item.id, 7);
    expect(item.sku, 'CAB-USB-01');
    expect(item.stock, 8);
    expect(item.stockValue, '100.00');
    expect(item.status, 'ok');
  });

  test('decodifica los indicadores principales del inventario', () {
    final overview = InventoryOverview.fromJson({
      'stock_value': {'total': '245000.00'},
      'low_stock': 4,
      'out_of_stock': 2,
      'consumption': {'units': 18, 'value': '32000.00'},
    });

    expect(overview.stockValue, '245000.00');
    expect(overview.lowStock, 4);
    expect(overview.outOfStock, 2);
    expect(overview.consumptionUnits, 18);
    expect(overview.consumptionValue, '32000.00');
  });

  test('tolera campos opcionales ausentes en el resumen', () {
    final overview = InventoryOverview.fromJson(const {});
    expect(overview.stockValue, '0');
    expect(overview.lowStock, 0);
    expect(overview.outOfStock, 0);
    expect(overview.consumptionUnits, 0);
  });
}
