import { AbstractControl, ValidationErrors, ValidatorFn } from '@angular/forms';

import { toCsv } from '../../core/csv';
import {
  INVENTORY_LIMITS,
  InventoryItem,
  ItemCategory,
  MovementKind,
  StockStatus,
} from '../../core/inventory.service';

/** Presentación y validación del inventario. Funciones puras, sin Angular salvo los validadores. */

export const CATEGORIES: { code: ItemCategory; label: string; icon: string }[] = [
  { code: 'spare_part', label: 'Repuesto', icon: 'memory' },
  { code: 'consumable', label: 'Consumible', icon: 'water_drop' },
  { code: 'accessory', label: 'Accesorio', icon: 'cable' },
  { code: 'tool', label: 'Herramienta', icon: 'build' },
  { code: 'other', label: 'Otro', icon: 'category' },
];

export const categoryLabel = (code: string): string => CATEGORIES.find((c) => c.code === code)?.label ?? code;
export const categoryIcon = (code: string): string => CATEGORIES.find((c) => c.code === code)?.icon ?? 'category';

/** Etiquetas y clases por estado de stock; todas con contraste AA sobre su fondo. */
export const STATUS_META: Record<StockStatus, { label: string; chip: string; bar: string }> = {
  ok: { label: 'En stock', chip: 'bg-primary-fixed text-on-primary-fixed-variant', bar: 'bg-brand-accentDeep' },
  low: { label: 'Bajo mínimo', chip: 'bg-secondary-fixed text-on-secondary-fixed', bar: 'bg-brand-mustard' },
  out: { label: 'Agotado', chip: 'bg-error-container text-on-error-container', bar: 'bg-error' },
};

export const KIND_LABELS: Record<MovementKind, string> = { in: 'Entrada', out: 'Consumo', adjust: 'Ajuste' };

/** Posición (0–100) del mínimo sobre la barra de nivel, para marcarlo; `null` si no cabe. */
export function minMarker(item: Pick<InventoryItem, 'stock' | 'min_stock' | 'max_stock'>): number | null {
  const reference = item.max_stock ?? Math.max(item.min_stock * 2, item.stock, 1);
  return item.min_stock > 0 && reference > 0 ? Math.min((item.min_stock / reference) * 100, 100) : null;
}

export const money = (value: string | number): string =>
  Number(value).toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export const SKU_PATTERN = /^[A-Z0-9][A-Z0-9._-]{2,39}$/;

/** SKU obligatorio: el backend lo guarda en mayúsculas, así que se valida ya normalizado. */
export const skuValidator: ValidatorFn = (control: AbstractControl): ValidationErrors | null => {
  const value = String(control.value ?? '').trim();
  if (value === '') {
    return { required: true };
  }
  return SKU_PATTERN.test(value.toUpperCase()) ? null : { sku: true };
};

/**
 * Cantidad de un movimiento. Entrada y consumo: entero positivo; ajuste: entero con signo y
 * distinto de 0. Un consumo no puede superar lo disponible (ni dejar el stock en negativo).
 */
export const movementQuantity =
  (kind: () => MovementKind, available: () => number): ValidatorFn =>
  (control) => {
    const raw = control.value;
    if (raw === null || raw === undefined || String(raw).trim() === '') {
      return { required: true };
    }
    const value = Number(raw);
    if (!Number.isInteger(value)) {
      return { integer: true };
    }
    const max = INVENTORY_LIMITS.maxQuantity;
    if (kind() === 'adjust') {
      if (value === 0) {
        return { nonZero: true };
      }
      if (Math.abs(value) > max) {
        return { max: { max } };
      }
      return value < 0 && -value > available() ? { insufficient: { available: available() } } : null;
    }
    if (value < 1) {
      return { min: { min: 1 } };
    }
    if (value > max) {
      return { max: { max } };
    }
    return kind() === 'out' && value > available() ? { insufficient: { available: available() } } : null;
  };

export function itemsToCsv(items: InventoryItem[]): string {
  const headers = ['SKU', 'Nombre', 'Categoría', 'Unidad', 'Costo unitario', 'Stock', 'Mínimo', 'Máximo', 'Valor', 'Ubicación', 'Proveedor', 'Estado'];
  const rows = items.map((item) => [
    item.sku, item.name, categoryLabel(item.category), item.unit, item.unit_cost, item.stock, item.min_stock,
    item.max_stock ?? '', item.stock_value, item.location ?? '', item.supplier ?? '',
    !item.is_active ? 'Inactivo' : STATUS_META[item.status].label,
  ]);
  return toCsv([headers, ...rows]);
}

export const IMPORT_MAX_BYTES = 5 * 1024 * 1024;
export const IMPORT_EXTENSIONS = ['.csv', '.xlsx'];

/** Revisión previa de un archivo de importación: tipo y tamaño (el backend vuelve a validar). */
export function validateImportFile(file: { name: string; size: number }): string {
  const extension = file.name.slice(file.name.lastIndexOf('.')).toLowerCase();
  if (!IMPORT_EXTENSIONS.includes(extension)) {
    return 'Solo se admiten archivos .csv o .xlsx.';
  }
  if (file.size === 0) {
    return 'El archivo está vacío.';
  }
  return file.size > IMPORT_MAX_BYTES ? 'El archivo supera los 5 MB permitidos.' : '';
}
