import { AbstractControl, ValidationErrors, ValidatorFn } from '@angular/forms';

import { fromLocalInput } from '../../core/calendar-utils';

export {
  fieldError, groupError, integerRange, optionalHours, optionalText, parseHours, requiredText,
} from '../../core/form-validation';

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
