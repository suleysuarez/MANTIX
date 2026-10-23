import { FormControl } from '@angular/forms';

import { InventoryItem } from '../../core/inventory.service';
import {
  categoryLabel, hasRangeErrors, minMarker, money, movementQuantity, optionsOf, rangeErrors, skuValidator, validateImportFile,
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

  describe('range filters', () => {
    const none = { stockMin: '', stockMax: '', costMin: '', costMax: '', createdFrom: '', createdTo: '', movedFrom: '', movedTo: '' };

    it('accepts empty, one-sided and coherent ranges', () => {
      expect(hasRangeErrors(rangeErrors(none))).toBeFalse();
      expect(hasRangeErrors(rangeErrors({ ...none, stockMin: '5' }))).toBeFalse();
      expect(hasRangeErrors(rangeErrors({ ...none, stockMin: '5', stockMax: '5', costMin: '0', costMax: '99.5' }))).toBeFalse();
    });

    it('rejects negatives, non-numbers and wrong decimals in Spanish', () => {
      expect(rangeErrors({ ...none, stockMin: '-1' }).stock).toBe('Stock mínimo: no puede ser negativo.');
      expect(rangeErrors({ ...none, stockMax: '2.5' }).stock).toBe('Stock máximo: escribe un número entero.');
      expect(rangeErrors({ ...none, stockMax: 'abc' }).stock).toBe('Stock máximo: escribe un número entero.');
      expect(rangeErrors({ ...none, costMax: '1.234' }).cost).toBe('Precio máximo: escribe un importe válido (máximo 2 decimales).');
      expect(rangeErrors({ ...none, costMin: '-0.5' }).cost).toBe('Precio mínimo: no puede ser negativo.');
      expect(rangeErrors({ ...none, stockMin: '2000000' }).stock).toContain('no puede superar');
    });

    it('requires the minimum not to exceed the maximum', () => {
      expect(rangeErrors({ ...none, stockMin: '10', stockMax: '4' }).stock).toBe('El stock mínimo no puede ser mayor que el máximo.');
      expect(rangeErrors({ ...none, costMin: '9.99', costMax: '1' }).cost).toBe('El precio mínimo no puede ser mayor que el máximo.');
    });

    it('validates the entry and movement dates with the shared rule', () => {
      expect(rangeErrors({ ...none, createdFrom: '2026-10-10', createdTo: '2026-10-01' }).created).toBe('La fecha final no puede ser anterior a la inicial.');
      expect(rangeErrors({ ...none, movedFrom: '2026-02-30' }).moved).toBe('La fecha no existe en el calendario.');
      expect(hasRangeErrors(rangeErrors({ ...none, createdFrom: '2026-10-01', createdTo: '2026-10-10' }))).toBeFalse();
    });
  });

  describe('options', () => {
    const options = [
      { kind: 'category' as const, value: 'equipo_de_red', label: 'Equipo de Red' },
      { kind: 'supplier' as const, value: 'Acme', label: 'Acme' },
    ];

    it('names categories from the server, then the built-in ones, then the code', () => {
      expect(categoryLabel('equipo_de_red', options)).toBe('Equipo de Red');
      expect(categoryLabel('tool', options)).toBe('Herramienta');
      expect(categoryLabel('zzz', options)).toBe('zzz');
    });

    it('filters the options of one drop-down', () => {
      expect(optionsOf(options, 'supplier')).toEqual([{ value: 'Acme', label: 'Acme' }]);
      expect(optionsOf(options, 'unit')).toEqual([]);
    });
  });
});
