import { AbstractControl, FormGroup, ValidationErrors, ValidatorFn } from '@angular/forms';

/** Validadores y mensajes en español de los formularios reactivos (el backend es la fuente de verdad). */

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

/** Entero obligatorio entre `min` y `max` (ambos inclusive). */
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

/** Entero opcional (vacío vale) entre `min` y `max`. */
export const optionalInteger =
  (min: number, max: number): ValidatorFn =>
  (control) =>
    String(control.value ?? '').trim() === '' ? null : integerRange(min, max)(control);

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

/** Importe opcional (vacío vale 0): nunca negativo, hasta `max` y con 2 decimales como mucho. */
export const optionalMoney =
  (max: number): ValidatorFn =>
  (control) => {
    const raw = String(control.value ?? '').trim().replace(',', '.');
    if (raw === '') {
      return null;
    }
    if (!/^-?\d+(\.\d+)?$/.test(raw)) {
      return { number: true };
    }
    const value = Number(raw);
    if (value < 0) {
      return { negative: true };
    }
    if (value > max) {
      return { max: { max } };
    }
    return /\.\d{3,}/.test(raw) ? { decimals: true } : null;
  };

/** Parsea números escritos con punto o coma; `null` si está vacío. */
export function parseDecimal(value: unknown): number | null {
  const raw = String(value ?? '').trim().replace(',', '.');
  return raw === '' ? null : Number(raw);
}

export const parseHours = parseDecimal;

/** El máximo (opcional) no puede ser menor que el mínimo. */
export const maxNotBelowMin =
  (minField: string, maxField: string): ValidatorFn =>
  (group: AbstractControl): ValidationErrors | null => {
    const min = Number(group.get(minField)?.value);
    const rawMax = group.get(maxField)?.value;
    if (rawMax === null || rawMax === undefined || String(rawMax).trim() === '') {
      return null;
    }
    const max = Number(rawMax);
    return Number.isFinite(min) && Number.isFinite(max) && max < min ? { maxBelowMin: true } : null;
  };

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
  negative: () => 'No puede ser negativo.',
  decimals: () => 'Usa como máximo 2 decimales.',
  invalidDate: () => 'La fecha no existe en el calendario.',
  past: () => 'No se puede programar en el pasado.',
  reminderTooEarly: () => 'El recordatorio no puede superar el intervalo entre servicios.',
  maxBelowMin: () => 'El máximo no puede ser menor que el mínimo.',
  sku: () => 'Usa 3 a 40 caracteres: letras, números, punto, guion o guion bajo.',
  nonZero: () => 'No puede ser 0.',
  pattern: () => 'Contiene caracteres no permitidos.',
  insufficient: (e) => `Solo hay ${e.available} disponibles.`,
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
