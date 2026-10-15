import { AbstractControl, ValidationErrors } from '@angular/forms';

import { formatHours } from '../dashboard/dashboard-format';
import { QueueStatus } from '../../core/pending-requests.store';
import { MAX_RANGE_DAYS, parseDay } from '../reports/report-filters';

/** Presentación de la bandeja de triaje. Funciones puras, sin Angular. */

export interface ColumnMeta {
  status: QueueStatus;
  title: string;
  hint: string;
  icon: string;
}

export const COLUMNS: readonly ColumnMeta[] = [
  { status: 'submitted', title: 'Recibidas', hint: 'Esperan clasificación', icon: 'inbox' },
  { status: 'triaged', title: 'Clasificadas', hint: 'Esperan técnico', icon: 'rule' },
  { status: 'assigned', title: 'Asignadas', hint: 'Con técnico, sin iniciar', icon: 'person_check' },
];

/** Horas que una solicitud lleva en cola; nunca negativas (relojes desfasados). */
export function waitHours(createdAt: string, now: Date = new Date()): number {
  return Math.max((now.getTime() - new Date(createdAt).getTime()) / 3_600_000, 0);
}

export type WaitTone = 'fresh' | 'aging' | 'stale';

/** Más de 1 día pide atención; más de 3 días es una espera que ya molesta. */
export const AGING_HOURS = 24;
export const STALE_HOURS = 72;

export function waitTone(hours: number): WaitTone {
  if (hours >= STALE_HOURS) {
    return 'stale';
  }
  return hours >= AGING_HOURS ? 'aging' : 'fresh';
}

/** Clases con contraste AA sobre su fondo (texto >= 4.5:1). */
export const WAIT_CLASSES: Record<WaitTone, string> = {
  fresh: 'bg-brand-accentLight/60 text-brand-accentDeep',
  aging: 'bg-secondary-fixed text-on-secondary-fixed',
  stale: 'bg-error-container text-on-error-container',
};

export const formatWait = (hours: number): string => formatHours(hours);

export const MAX_CLASSIFY_NOTES = 500;

const DAY_MS = 86_400_000;

/** Rango «recibidas entre»: fechas reales, la inicial no es futura, fin ≥ inicio y como máximo 366 días. Vacío = sin error. */
export function queueRangeError(from: string, to: string, today: Date = new Date()): string {
  const start = from ? parseDay(from) : null;
  const end = to ? parseDay(to) : null;
  if ((from && !start) || (to && !end)) {
    return 'La fecha no existe en el calendario.';
  }
  if (start && start.getTime() > today.getTime()) {
    return 'La fecha inicial no puede ser futura.';
  }
  if (start && end) {
    if (end < start) {
      return 'La fecha final no puede ser anterior a la inicial.';
    }
    if ((end.getTime() - start.getTime()) / DAY_MS + 1 > MAX_RANGE_DAYS) {
      return `El rango no puede superar ${MAX_RANGE_DAYS} días.`;
    }
  }
  return '';
}

export const MIN_REASON = 5;
export const MAX_REASON = 500;

/** Motivo de rechazo: obligatorio, sin contar los espacios sobrantes (igual que el backend). */
export function reasonValidator(control: AbstractControl): ValidationErrors | null {
  const length = String(control.value ?? '').trim().length;
  if (length === 0) {
    return { required: true };
  }
  if (length < MIN_REASON) {
    return { minlength: { requiredLength: MIN_REASON, actualLength: length } };
  }
  return length > MAX_REASON ? { maxlength: { requiredLength: MAX_REASON, actualLength: length } } : null;
}

export function reasonError(control: AbstractControl): string {
  const errors = control.errors;
  if (!errors) {
    return '';
  }
  if (errors['server']) {
    return String(errors['server']);
  }
  if (errors['required']) {
    return 'Escribe el motivo del rechazo.';
  }
  if (errors['minlength']) {
    return `El motivo debe tener al menos ${MIN_REASON} caracteres.`;
  }
  return errors['maxlength'] ? `El motivo admite como máximo ${MAX_REASON} caracteres.` : 'El motivo no es válido.';
}

/** Etiqueta de categoría con la del catálogo; «Sin categoría» cuando no hay. */
export function categoryLabel(code: string | null | undefined, names: Map<string, string>): string {
  if (!code || code === 'uncategorized') {
    return 'Sin categoría';
  }
  return names.get(code) ?? code;
}

/** Porcentaje de `part` sobre `whole`, con un mínimo visible para valores no nulos. */
export function share(part: number, whole: number): number {
  return whole > 0 ? Math.max((part / whole) * 100, part > 0 ? 4 : 0) : 0;
}
