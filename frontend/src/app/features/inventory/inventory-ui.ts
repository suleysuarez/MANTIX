import { AbstractControl, ValidationErrors, ValidatorFn } from '@angular/forms';

import {
  INVENTORY_LIMITS,
  InventoryItem,
  InventoryOption,
  ItemCategory,
  MovementKind,
  OptionKind,
  StockStatus,
} from '../../core/inventory.service';
import { dateRangeError } from '../../shared/date-range';

/** Presentación y validación del inventario. Funciones puras, sin Angular salvo los validadores. */

/** Categorías de fábrica con su icono; las que se agreguen usan el icono genérico. */
export const CATEGORIES: { code: ItemCategory; label: string; icon: string }[] = [
  { code: 'spare_part', label: 'Repuesto', icon: 'memory' },
  { code: 'consumable', label: 'Consumible', icon: 'water_drop' },
  { code: 'accessory', label: 'Accesorio', icon: 'cable' },
  { code: 'tool', label: 'Herramienta', icon: 'build' },
  { code: 'other', label: 'Otro', icon: 'category' },
];

/** Nombre de una categoría: el del servidor si ya llegó, el de fábrica o, al final, su código. */
export const categoryLabel = (code: string, options: readonly InventoryOption[] = []): string =>
  options.find((o) => o.kind === 'category' && o.value === code)?.label ?? CATEGORIES.find((c) => c.code === code)?.label ?? code;
export const categoryIcon = (code: string): string => CATEGORIES.find((c) => c.code === code)?.icon ?? 'category';

/** Opciones de un desplegable en el formato del selector con «+ Agregar nuevo». */
export const optionsOf = (options: readonly InventoryOption[], kind: OptionKind): { value: string; label: string }[] =>
  options.filter((o) => o.kind === kind).map((o) => ({ value: o.value, label: o.label }));

/** Valores de los filtros por rango, tal como se escriben (vacío = sin límite). */
export interface RangeFilters {
  stockMin: string;
  stockMax: string;
  costMin: string;
  costMax: string;
  createdFrom: string;
  createdTo: string;
  movedFrom: string;
  movedTo: string;
}

export interface RangeErrors {
  stock: string;
  cost: string;
  created: string;
  moved: string;
}

const NUMBER = /^\d+(\.\d{1,2})?$/;

function numberError(value: string, label: string, integer: boolean, max: number): string {
  const text = value.trim();
  if (text === '') {
    return '';
  }
  if (text.startsWith('-')) {
    return `${label}: no puede ser negativo.`;
  }
  if (!NUMBER.test(text) || (integer && text.includes('.'))) {
    return integer ? `${label}: escribe un número entero.` : `${label}: escribe un importe válido (máximo 2 decimales).`;
  }
  return Number(text) > max ? `${label}: no puede superar ${max.toLocaleString('es-MX')}.` : '';
}

/** Un par «mínimo / máximo»: cada valor válido y no negativo, y el mínimo no mayor que el máximo. */
function pairError(low: string, high: string, label: string, integer: boolean, max: number): string {
  const first = numberError(low, `${label} mínimo`, integer, max) || numberError(high, `${label} máximo`, integer, max);
  if (first) {
    return first;
  }
  return low.trim() !== '' && high.trim() !== '' && Number(low) > Number(high) ? `El ${label.toLowerCase()} mínimo no puede ser mayor que el máximo.` : '';
}

/** Errores de los filtros por rango, en español, uno por filtro (vacío = válido). Con errores no se consulta al servidor. */
export function rangeErrors(f: RangeFilters): RangeErrors {
  return {
    stock: pairError(f.stockMin, f.stockMax, 'Stock', true, INVENTORY_LIMITS.maxQuantity),
    cost: pairError(f.costMin, f.costMax, 'Precio', false, INVENTORY_LIMITS.maxCost),
    created: dateRangeError(f.createdFrom, f.createdTo),
    moved: dateRangeError(f.movedFrom, f.movedTo),
  };
}

export const hasRangeErrors = (errors: RangeErrors): boolean => Object.values(errors).some((message) => message !== '');

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

export const IMPORT_MAX_BYTES = 5 * 1024 * 1024;
/** Filas máximas por archivo (el servidor es quien lo hace cumplir). */
export const IMPORT_MAX_ROWS = 5000;
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
