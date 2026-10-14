import { FormControl } from '@angular/forms';

import { csvCell, toCsv } from '../../core/csv';
import { InventoryItem } from '../../core/inventory.service';
import {
  itemsToCsv, minMarker, money, movementQuantity, skuValidator, validateImportFile,
} from './inventory-ui';
import { integerRange, maxNotBelowMin, optionalInteger, optionalMoney, fieldError } from '../../core/form-validation';
import { FormGroup } from '@angular/forms';

const item = (overrides: Partial<InventoryItem> = {}): InventoryItem => ({
  id: 1, sku: 'SSD-512', name: 'SSD 512 GB', description: null, category: 'spare_part', unit: 'unidad',
  unit_cost: '64.90', stock: 12, min_stock: 5, max_stock: 40, location: null, supplier: null, is_active: true,
  status: 'ok', stock_value: '778.80', level_pct: 30, last_movement_at: null, created_at: '', updated_at: '',
  ...overrides,
});

describe('inventory validators', () => {
  describe('skuValidator', () => {
    it('requires a code of 3 to 40 valid characters, case-insensitive', () => {
      expect(skuValidator(new FormControl(''))).toEqual({ required: true });
      expect(skuValidator(new FormControl('   '))).toEqual({ required: true });
      for (const bad of ['ab', 'SSD 512', 'SSD/512', '-SSD', 'x'.repeat(41), 'ñandú']) {
        expect(skuValidator(new FormControl(bad))).toEqual({ sku: true });
      }
      for (const good of ['ssd-512', ' SSD_512 ', 'A.1', '123']) {
        expect(skuValidator(new FormControl(good))).toBeNull();
      }
    });
  });

  describe('numbers never go negative', () => {
    it('validates required integers within bounds', () => {
      const v = integerRange(0, 1_000_000);
      expect(v(new FormControl(-1))).toEqual({ min: { min: 0 } });
      expect(v(new FormControl(1.5))).toEqual({ integer: true });
      expect(v(new FormControl(1_000_001))).toEqual({ max: { max: 1_000_000 } });
      expect(v(new FormControl(0))).toBeNull();
    });

    it('treats an empty optional integer as unset but still checks a value', () => {
      const v = optionalInteger(0, 100);
      expect(v(new FormControl(''))).toBeNull();
      expect(v(new FormControl(null))).toBeNull();
      expect(v(new FormControl(-3))).toEqual({ min: { min: 0 } });
    });

    it('validates money with 2 decimals, no negatives and a ceiling', () => {
      const v = optionalMoney(1_000_000);
      expect(v(new FormControl(''))).toBeNull();
      expect(v(new FormControl('-0.5'))).toEqual({ negative: true });
      expect(v(new FormControl('1.234'))).toEqual({ decimals: true });
      expect(v(new FormControl('abc'))).toEqual({ number: true });
      expect(v(new FormControl('1000000.01'))).toEqual({ max: { max: 1_000_000 } });
      expect(v(new FormControl('64,90'))).toBeNull();
      expect(v(new FormControl('0'))).toBeNull();
    });

    it('requires the maximum to be at least the minimum', () => {
      const group = (min: unknown, max: unknown) =>
        new FormGroup({ minStock: new FormControl(min), maxStock: new FormControl(max) });
      const v = maxNotBelowMin('minStock', 'maxStock');
      expect(v(group(10, 5))).toEqual({ maxBelowMin: true });
      expect(v(group(10, 10))).toBeNull();
      expect(v(group(10, ''))).toBeNull();
      expect(v(group(10, null))).toBeNull();
    });
  });

  describe('movementQuantity', () => {
    const validator = (kind: 'in' | 'out' | 'adjust', available = 10) => movementQuantity(() => kind, () => available);

    it('accepts only positive whole units for entries and consumption', () => {
      for (const kind of ['in', 'out'] as const) {
        const v = validator(kind);
        expect(v(new FormControl(''))).toEqual({ required: true });
        expect(v(new FormControl(0))).toEqual({ min: { min: 1 } });
        expect(v(new FormControl(-2))).toEqual({ min: { min: 1 } });
        expect(v(new FormControl(2.5))).toEqual({ integer: true });
      }
    });

    it('does not let consumption exceed the available stock, and allows consuming it all', () => {
      expect(validator('out', 10)(new FormControl(11))).toEqual({ insufficient: { available: 10 } });
      expect(validator('out', 10)(new FormControl(10))).toBeNull();
      expect(validator('out', 0)(new FormControl(1))).toEqual({ insufficient: { available: 0 } });
      expect(validator('in', 0)(new FormControl(500))).toBeNull(); // las entradas no dependen del stock
    });

    it('lets an adjustment be signed but never zero or below the available stock', () => {
      const v = validator('adjust', 10);
      expect(v(new FormControl(0))).toEqual({ nonZero: true });
      expect(v(new FormControl(-11))).toEqual({ insufficient: { available: 10 } });
      expect(v(new FormControl(-10))).toBeNull();
      expect(v(new FormControl(5))).toBeNull();
      expect(v(new FormControl(2_000_000))).toEqual({ max: { max: 1_000_000 } });
    });

    it('re-evaluates against the current kind and stock', () => {
      let kind: 'in' | 'out' = 'in';
      const v = movementQuantity(() => kind, () => 3);
      expect(v(new FormControl(5))).toBeNull();
      kind = 'out';
      expect(v(new FormControl(5))).toEqual({ insufficient: { available: 3 } });
    });
  });

  it('shows the Spanish messages for the new error codes', () => {
    const c = new FormControl('', skuValidator);
    c.markAsTouched();
    expect(fieldError(c)).toBe('Este campo es obligatorio.');
    c.setValue('ab');
    expect(fieldError(c)).toBe('Usa 3 a 40 caracteres: letras, números, punto, guion o guion bajo.');
    const q = new FormControl(11, movementQuantity(() => 'out', () => 4));
    q.markAsTouched();
    expect(fieldError(q)).toBe('Solo hay 4 disponibles.');
  });
});

describe('inventory ui', () => {
  it('marks the minimum on the level bar against the maximum or twice the minimum', () => {
    expect(minMarker(item({ min_stock: 5, max_stock: 40 }))).toBe(12.5);
    expect(minMarker(item({ min_stock: 10, max_stock: null, stock: 5 }))).toBe(50);
    expect(minMarker(item({ min_stock: 0 }))).toBeNull();
  });

  it('formats money with two decimals', () => {
    expect(money('64.9')).toBe('64.90');
    expect(money(1234.5)).toBe('1,234.50');
  });

  it('exports the filtered items as CSV and neutralises formulas', () => {
    const csv = itemsToCsv([item(), item({ name: '=cmd|calc', stock: 0, status: 'out', is_active: false })]);
    const lines = csv.split('\r\n');
    expect(lines[0].startsWith('SKU,Nombre,Categoría')).toBeTrue();
    expect(lines[1]).toContain('SSD 512 GB');
    expect(lines[2]).toContain("'=cmd|calc");
    expect(lines[2].endsWith('Inactivo')).toBeTrue();
    expect(csvCell('a,b')).toBe('"a,b"');
    expect(toCsv([['a', 'b']])).toBe('a,b');
  });

  describe('validateImportFile', () => {
    it('accepts csv and xlsx within 5 MB', () => {
      expect(validateImportFile({ name: 'items.csv', size: 100 })).toBe('');
      expect(validateImportFile({ name: 'ITEMS.XLSX', size: 5 * 1024 * 1024 })).toBe('');
    });
    it('rejects other types, empty files and oversized ones with a clear message', () => {
      expect(validateImportFile({ name: 'virus.exe', size: 10 })).toBe('Solo se admiten archivos .csv o .xlsx.');
      expect(validateImportFile({ name: 'sin-extension', size: 10 })).toBe('Solo se admiten archivos .csv o .xlsx.');
      expect(validateImportFile({ name: 'a.csv', size: 0 })).toBe('El archivo está vacío.');
      expect(validateImportFile({ name: 'a.csv', size: 5 * 1024 * 1024 + 1 })).toBe('El archivo supera los 5 MB permitidos.');
    });
  });
});
