import { FormControl, FormGroup, ValidatorFn } from '@angular/forms';

import { fromLocalInput, toLocalInput } from '../../core/calendar-utils';
import {
  fieldError, futureDateTime, integerRange, optionalHours, optionalText, parseHours, reminderFitsInterval,
  requiredText,
} from './plan-form';

const control = (value: unknown, validator?: ValidatorFn) => new FormControl(value, validator ?? null);

describe('plan-form validators', () => {
  describe('requiredText', () => {
    const v = requiredText(3, 10);
    it('rejects empty, spaces-only, short and long text', () => {
      expect(v(control(''))).toEqual({ required: true });
      expect(v(control('     '))).toEqual({ required: true });
      expect(v(control('  ab  '))).toEqual({ minlength: { requiredLength: 3 } });
      expect(v(control('x'.repeat(11)))).toEqual({ maxlength: { requiredLength: 10 } });
    });
    it('accepts trimmed text inside the bounds', () => {
      expect(v(control('  abc  '))).toBeNull();
      expect(v(control('x'.repeat(10)))).toBeNull();
    });
  });

  describe('optionalText', () => {
    const v = optionalText(5);
    it('allows empty but not blank or too long', () => {
      expect(v(control(''))).toBeNull();
      expect(v(control('   '))).toEqual({ blank: true });
      expect(v(control('abcdef'))).toEqual({ maxlength: { requiredLength: 5 } });
      expect(v(control(' abc '))).toBeNull();
    });
  });

  describe('integerRange (intervals and counts never go negative)', () => {
    const v = integerRange(1, 3650);
    it('rejects empty, decimals, zero, negatives and too large', () => {
      expect(v(control(''))).toEqual({ required: true });
      expect(v(control(null))).toEqual({ required: true });
      expect(v(control(1.5))).toEqual({ integer: true });
      expect(v(control(0))).toEqual({ min: { min: 1 } });
      expect(v(control(-30))).toEqual({ min: { min: 1 } });
      expect(v(control(3651))).toEqual({ max: { max: 3650 } });
    });
    it('accepts the boundaries', () => {
      expect(v(control(1))).toBeNull();
      expect(v(control('3650'))).toBeNull();
    });
    it('allows a reminder of 0 days', () => expect(integerRange(0, 365)(control(0))).toBeNull());
  });

  describe('optionalHours (2 decimals, positive, capped)', () => {
    const v = optionalHours(999);
    it('is optional', () => {
      expect(v(control(''))).toBeNull();
      expect(v(control(null))).toBeNull();
    });
    it('rejects zero, negatives, text, 3 decimals and too many hours', () => {
      expect(v(control('0'))).toEqual({ positive: true });
      expect(v(control('-2'))).toEqual({ number: true });
      expect(v(control('abc'))).toEqual({ number: true });
      expect(v(control('1.234'))).toEqual({ decimals: true });
      expect(v(control('1000'))).toEqual({ max: { max: 999 } });
    });
    it('accepts 2 decimals with a point or a comma', () => {
      expect(v(control('1.25'))).toBeNull();
      expect(v(control('1,5'))).toBeNull();
      expect(v(control('999'))).toBeNull();
      expect(parseHours('1,5')).toBe(1.5);
      expect(parseHours('')).toBeNull();
    });
  });

  describe('futureDateTime (no past, no impossible dates)', () => {
    const now = new Date(2026, 9, 14, 12, 0);
    const v = futureDateTime(() => now);
    it('rejects empty, impossible and past dates', () => {
      expect(v(control(''))).toEqual({ required: true });
      expect(v(control('2027-02-30T09:00'))).toEqual({ invalidDate: true });
      expect(v(control('2026-13-01T09:00'))).toEqual({ invalidDate: true });
      expect(v(control('no es una fecha'))).toEqual({ invalidDate: true });
      expect(v(control('2026-10-14T11:59'))).toEqual({ past: true });
    });
    it('accepts now and later', () => {
      expect(v(control('2026-10-14T12:00'))).toBeNull();
      expect(v(control('2026-12-01T09:00'))).toBeNull();
    });
    it('round-trips a local value to ISO and back', () => {
      expect(fromLocalInput('2026-12-01T09:00')).toBe(new Date(2026, 11, 1, 9, 0).toISOString());
      expect(fromLocalInput('2027-02-29T09:00')).toBeNull(); // 2027 no es bisiesto
      expect(toLocalInput(new Date(2026, 11, 1, 9, 5))).toBe('2026-12-01T09:05');
    });
  });

  it('flags a reminder longer than the interval', () => {
    const group = (interval: number, remind: number) =>
      new FormGroup({ intervalDays: new FormControl(interval), remindDaysBefore: new FormControl(remind) });
    expect(reminderFitsInterval(group(30, 31))).toEqual({ reminderTooEarly: true });
    expect(reminderFitsInterval(group(30, 30))).toBeNull();
  });

  describe('fieldError', () => {
    it('shows Spanish messages only once the field is touched', () => {
      const c = control('', requiredText(3, 10));
      expect(fieldError(c)).toBe('');
      c.markAsTouched();
      expect(fieldError(c)).toBe('Este campo es obligatorio.');
      c.setValue('ab');
      expect(fieldError(c)).toBe('Debe tener al menos 3 caracteres.');
    });
    it('shows the server message set on the control', () => {
      const c = control('x');
      c.setErrors({ server: 'Ya existe un plan con ese título.' });
      c.markAsTouched();
      expect(fieldError(c)).toBe('Ya existe un plan con ese título.');
    });
  });
});
