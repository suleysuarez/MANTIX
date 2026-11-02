import { dateRangeError, dayString, shortcutOf, shortcutRange } from './date-range';

describe('date-range', () => {
  const today = new Date(2026, 9, 14, 12); // 14/10/2026

  describe('shortcuts', () => {
    it('resolves each shortcut to local days', () => {
      expect(shortcutRange('all', today)).toEqual({ from: '', to: '' });
      expect(shortcutRange('today', today)).toEqual({ from: '2026-10-14', to: '2026-10-14' });
      expect(shortcutRange('7d', today)).toEqual({ from: '2026-10-08', to: '2026-10-14' });
      expect(shortcutRange('30d', today)).toEqual({ from: '2026-09-15', to: '2026-10-14' });
      expect(shortcutRange('month', today)).toEqual({ from: '2026-10-01', to: '2026-10-14' });
      expect(shortcutRange('custom', today)).toBeNull();
    });

    it('looks forward for scheduled ranges', () => {
      expect(shortcutRange('7d', today, true)).toEqual({ from: '2026-10-14', to: '2026-10-20' });
      expect(shortcutRange('30d', today, true)).toEqual({ from: '2026-10-14', to: '2026-11-12' });
      expect(shortcutRange('month', today, true)).toEqual({ from: '2026-10-01', to: '2026-10-31' });
      expect(shortcutOf('2026-10-14', '2026-10-20', today, true)).toBe('7d');
      expect(shortcutOf('2026-10-08', '2026-10-14', today, true)).toBe('custom');
    });

    it('crosses month and year boundaries', () => {
      expect(shortcutRange('7d', new Date(2027, 0, 3))).toEqual({ from: '2026-12-28', to: '2027-01-03' });
      expect(dayString(new Date(2026, 1, 9))).toBe('2026-02-09');
    });

    it('recognises the shortcut of a range already chosen', () => {
      expect(shortcutOf('', '', today)).toBe('all');
      expect(shortcutOf('2026-10-14', '2026-10-14', today)).toBe('today');
      expect(shortcutOf('2026-10-08', '2026-10-14', today)).toBe('7d');
      expect(shortcutOf('2026-10-01', '2026-10-14', today)).toBe('month');
      expect(shortcutOf('2026-09-01', '2026-09-30', today)).toBe('custom');
      expect(shortcutOf('2026-09-01', '', today)).toBe('custom');
    });
  });

  describe('dateRangeError', () => {
    it('accepts empty, one-sided, same-day and past ranges', () => {
      for (const [from, to] of [['', ''], ['2026-10-01', ''], ['', '2026-10-14'], ['2026-10-05', '2026-10-05'], ['2026-10-14', '2026-10-14']]) {
        expect(dateRangeError(from, to, today)).withContext(`${from}..${to}`).toBe('');
      }
    });

    it('requires start <= end', () => {
      expect(dateRangeError('2026-10-10', '2026-10-01', today)).toBe('La fecha final no puede ser anterior a la inicial.');
    });

    it('rejects dates that do not exist', () => {
      expect(dateRangeError('2026-02-30', '', today)).toBe('La fecha no existe en el calendario.');
      expect(dateRangeError('', '2026-13-01', today)).toBe('La fecha no existe en el calendario.');
    });

    it('rejects a start in the future but allows an end in the future', () => {
      expect(dateRangeError('2026-10-15', '', today)).toBe('La fecha inicial no puede ser futura.');
      expect(dateRangeError('2026-10-01', '2026-12-31', today)).toBe('');
    });

    it('accepts a future start only for scheduled (upcoming) ranges', () => {
      expect(dateRangeError('2026-10-20', '2026-10-31', today)).toBe('La fecha inicial no puede ser futura.');
      expect(dateRangeError('2026-10-20', '2026-10-31', today, true)).toBe('');
      expect(dateRangeError('2026-10-31', '2026-10-20', today, true)).toBe('La fecha final no puede ser anterior a la inicial.');
      expect(dateRangeError('2026-02-30', '', today, true)).toBe('La fecha no existe en el calendario.');
    });

    it('allows 366 days and rejects 367', () => {
      expect(dateRangeError('2025-01-01', '2026-01-01', today)).toBe('');
      expect(dateRangeError('2025-01-01', '2026-01-02', today)).toBe('El rango no puede superar 366 días.');
    });
  });
});
