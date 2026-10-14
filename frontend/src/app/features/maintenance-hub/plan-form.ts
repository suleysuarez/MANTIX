import { AbstractControl, FormGroup, ValidationErrors, ValidatorFn } from '@angular/forms';

import { fromLocalInput } from '../../core/calendar-utils';

/** Límites de un plan preventivo: los mismos que impone el backend (la fuente de verdad). */
export const PLAN_LIMITS = {
  titleMin: 3,
  titleMax: 200,
  descriptionMax: 2000,
  intervalMin: 1,
  intervalMax: 3650,
  remindMax: 365,
  hoursMax: 999,
  reasonMax: 500,
} as const;

const textOf = (control: AbstractControl): string => String(control.value ?? '').trim();

/** Texto obligatorio sin contar espacios sobrantes (`'   '` no vale). */
export const requiredText =
  (min: number, max: number): ValidatorFn =>
  (control) => {
    const length = textOf(control).length;
    if (length === 0) {
      return { required: true };
    }
    if (length < min) {
      return { minlength: { requiredLength: min } };
    }
    return length > max ? { maxlength: { requiredLength: max } } : null;
  };

/** Texto opcional: vacío vale; si hay algo, solo espacios no vale y se respeta el máximo. */
export const optionalText =
  (max: number): ValidatorFn =>
  (control) => {
    const raw = String(control.value ?? '');
    if (raw === '') {
      return null;
    }
    if (raw.trim() === '') {
      return { blank: true };
    }
    return raw.trim().length > max ? { maxlength: { requiredLength: max } } : null;
  };

/** Entero obligatorio entre `min` y `max`. */
export const integerRange =
  (min: number, max: number): ValidatorFn =>
  (control) => {
    const raw = control.value;
    if (raw === null || raw === undefined || raw === '') {
      return { required: true };
    }
    const value = Number(raw);
    if (!Number.isInteger(value)) {
      return { integer: true };
    }
    if (value < min) {
      return { min: { min } };
    }
    return value > max ? { max: { max } } : null;
  };

/** Horas opcionales: mayores que 0, hasta `max` y con 2 decimales como mucho. */
export const optionalHours =
  (max: number): ValidatorFn =>
  (control) => {
    const raw = String(control.value ?? '').trim().replace(',', '.');
    if (raw === '') {
      return null;
    }
    if (!/^\d+(\.\d+)?$/.test(raw)) {
      return { number: true };
    }
    const value = Number(raw);
    if (value <= 0) {
      return { positive: true };
    }
    if (value > max) {
      return { max: { max } };
    }
    return /\.\d{3,}/.test(raw) ? { decimals: true } : null;
  };

/** Fecha y hora (`datetime-local`): obligatoria, existente y no anterior a `now`. */
export const futureDateTime =
  (now: () => Date = () => new Date()): ValidatorFn =>
  (control) => {
    const value = String(control.value ?? '');
    if (!value) {
      return { required: true };
    }
    const iso = fromLocalInput(value);
    if (iso === null) {
      return { invalidDate: true };
    }
    return new Date(iso).getTime() < now().getTime() ? { past: true } : null;
  };

/** El recordatorio no puede darse con más días de antelación que el intervalo entre servicios. */
export const reminderFitsInterval: ValidatorFn = (group: AbstractControl): ValidationErrors | null => {
  const interval = Number(group.get('intervalDays')?.value);
  const remind = Number(group.get('remindDaysBefore')?.value);
  return Number.isFinite(interval) && Number.isFinite(remind) && remind > interval ? { reminderTooEarly: true } : null;
};

/** Parsea horas escritas con punto o coma; `null` si está vacío. */
export function parseHours(value: unknown): number | null {
  const raw = String(value ?? '').trim().replace(',', '.');
  return raw === '' ? null : Number(raw);
}

const MESSAGES: Record<string, (error: ValidationErrors[string]) => string> = {
  required: () => 'Este campo es obligatorio.',
  blank: () => 'No puede contener solo espacios.',
  minlength: (e) => `Debe tener al menos ${e.requiredLength} caracteres.`,
  maxlength: (e) => `Debe tener como máximo ${e.requiredLength} caracteres.`,
  integer: () => 'Debe ser un número entero.',
  min: (e) => `Debe ser al menos ${e.min}.`,
  max: (e) => `No puede ser mayor que ${e.max}.`,
  number: () => 'Escribe un número válido.',
  positive: () => 'Debe ser mayor que 0.',
  decimals: () => 'Usa como máximo 2 decimales.',
  invalidDate: () => 'La fecha no existe en el calendario.',
  past: () => 'No se puede programar en el pasado.',
  reminderTooEarly: () => 'El recordatorio no puede superar el intervalo entre servicios.',
  server: (e) => String(e),
};

/** Primer mensaje en español del control (o `''` si es válido o aún no se tocó). */
export function fieldError(control: AbstractControl | null, showUntouched = false): string {
  if (!control || !control.errors || (!control.touched && !showUntouched)) {
    return '';
  }
  const [name, detail] = Object.entries(control.errors)[0];
  return (MESSAGES[name] ?? (() => 'El valor no es válido.'))(detail);
}

export function groupError(group: FormGroup): string {
  return group.errors ? fieldError(group, true) : '';
}
