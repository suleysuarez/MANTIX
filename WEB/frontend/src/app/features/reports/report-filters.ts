import { AbstractControl, ValidationErrors, ValidatorFn } from '@angular/forms';

import { ReportDefinition, ReportFilters } from '../../core/reports.service';

/** Valores del constructor de filtros y su traducción a la API. Funciones puras. */

export interface FilterValues {
  statuses: string[];
  priorities: string[];
  categories: string[];
  kinds: string[];
  equipment_type_ids: string[];
  /** `YYYY-MM-DD` (día local); vacío = sin límite. */
  dateFrom: string;
  dateTo: string;
  days: string;
}

export const EMPTY_VALUES: FilterValues = {
  statuses: [], priorities: [], categories: [], kinds: [], equipment_type_ids: [], dateFrom: '', dateTo: '', days: '30',
};

/** Límite máximo del rango de fechas, igual que el backend. */
export const MAX_RANGE_DAYS = 366;
const DAY_MS = 86_400_000;

/** Día `YYYY-MM-DD` real (sin 30 de febrero) como fecha local; `null` si no existe. */
export function parseDay(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) {
    return null;
  }
  const [year, month, day] = match.slice(1).map(Number);
  const date = new Date(year, month - 1, day);
  return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day ? date : null;
}

/** Inicio (00:00) o fin (23:59:59.999) del día local, como ISO UTC. */
export function dayBoundaryIso(value: string, end: boolean): string | null {
  const day = parseDay(value);
  if (!day) {
    return null;
  }
  const boundary = end
    ? new Date(day.getFullYear(), day.getMonth(), day.getDate(), 23, 59, 59, 999)
    : new Date(day.getFullYear(), day.getMonth(), day.getDate(), 0, 0, 0, 0);
  return boundary.toISOString();
}

/** Rango de fechas coherente: fechas reales, fin ≥ inicio y como máximo 366 días. */
export const dateRangeValidator: ValidatorFn = (group: AbstractControl): ValidationErrors | null => {
  const from = String(group.get('dateFrom')?.value ?? '');
  const to = String(group.get('dateTo')?.value ?? '');
  if ((from && !parseDay(from)) || (to && !parseDay(to))) {
    return { invalidDate: true };
  }
  if (from && to) {
    const start = parseDay(from)!;
    const end = parseDay(to)!;
    if (end < start) {
      return { rangeInverted: true };
    }
    const span = Math.round((end.getTime() - start.getTime()) / DAY_MS) + 1;
    if (span > MAX_RANGE_DAYS) {
      return { rangeTooLong: { max: MAX_RANGE_DAYS } };
    }
  }
  return null;
};

export function rangeError(errors: ValidationErrors | null): string {
  if (!errors) {
    return '';
  }
  if (errors['invalidDate']) {
    return 'La fecha no existe en el calendario.';
  }
  if (errors['rangeInverted']) {
    return 'La fecha final no puede ser anterior a la inicial.';
  }
  return errors['rangeTooLong'] ? `El rango no puede superar ${errors['rangeTooLong'].max} días.` : '';
}

/**
 * Filtros de la API para el reporte elegido. Solo se envía lo que el reporte admite: cambiar
 * de reporte no arrastra filtros de otro (la API rechazaría uno que no acepta).
 */
export function toApiFilters(definition: ReportDefinition, values: FilterValues): ReportFilters {
  const filters: ReportFilters = {};
  for (const filter of definition.filters) {
    switch (filter.key) {
      case 'statuses':
      case 'priorities':
      case 'categories':
      case 'kinds':
        if (values[filter.key].length) {
          filters[filter.key] = values[filter.key];
        }
        break;
      case 'equipment_type_ids':
        if (values.equipment_type_ids.length) {
          filters.equipment_type_ids = values.equipment_type_ids.map(Number);
        }
        break;
      case 'dates': {
        const from = dayBoundaryIso(values.dateFrom, false);
        const to = dayBoundaryIso(values.dateTo, true);
        if (from) {
          filters.date_from = from;
        }
        if (to) {
          filters.date_to = to;
        }
        break;
      }
      case 'days':
        filters.days = Number(values.days);
        break;
    }
  }
  return filters;
}

/** Resumen legible de los filtros activos (para el historial y el pie de la vista previa). */
export function describeFilters(definition: ReportDefinition, values: FilterValues): string {
  const parts: string[] = [];
  for (const filter of definition.filters) {
    if (filter.kind === 'multiselect') {
      const chosen = values[filter.key as 'statuses'] ?? [];
      if (chosen.length) {
        const labels = chosen.map((v) => filter.options.find((o) => o.value === v)?.label ?? v);
        parts.push(`${filter.label}: ${labels.join(', ')}`);
      }
    } else if (filter.kind === 'dates' && (values.dateFrom || values.dateTo)) {
      parts.push(`${filter.label}: ${values.dateFrom || '…'} a ${values.dateTo || '…'}`);
    } else if (filter.kind === 'days') {
      parts.push(filter.options.find((o) => o.value === values.days)?.label ?? `Últimos ${values.days} días`);
    }
  }
  return parts.join(' · ') || 'Sin filtros';
}

/** El comparativo necesita las dos fechas del rango. */
export const canCompare = (definition: ReportDefinition, values: FilterValues): boolean =>
  definition.supports_compare && !!parseDay(values.dateFrom) && !!parseDay(values.dateTo);
