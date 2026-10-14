import { FormControl } from '@angular/forms';

import {
  AGING_HOURS, STALE_HOURS, categoryLabel, formatWait, reasonError, reasonValidator, share, waitHours, waitTone,
} from './pending-ui';

describe('pending-ui', () => {
  const NOW = new Date('2026-10-14T12:00:00Z');

  it('measures the wait in hours and never goes negative', () => {
    expect(waitHours('2026-10-14T09:00:00Z', NOW)).toBe(3);
    expect(waitHours('2026-10-14T13:00:00Z', NOW)).toBe(0);
  });

  it('grades the wait at one and three days', () => {
    expect(waitTone(AGING_HOURS - 0.1)).toBe('fresh');
    expect(waitTone(AGING_HOURS)).toBe('aging');
    expect(waitTone(STALE_HOURS - 0.1)).toBe('aging');
    expect(waitTone(STALE_HOURS)).toBe('stale');
    expect(formatWait(30)).toBe('30 h');
    expect(formatWait(0.25)).toBe('15 min');
  });

  describe('reasonValidator', () => {
    const errorOf = (value: string) => reasonError(Object.assign(new FormControl(value, reasonValidator), {}));

    it('requires a real reason: empty, spaces only and too short are all invalid', () => {
      for (const value of ['', '     ', 'abcd', '  ab  ']) {
        expect(reasonValidator(new FormControl(value))).not.toBeNull();
      }
      expect(errorOf('')).toBe('Escribe el motivo del rechazo.');
      expect(errorOf('   ')).toBe('Escribe el motivo del rechazo.');
      expect(errorOf('abc')).toBe('El motivo debe tener al menos 5 caracteres.');
    });

    it('accepts a trimmed reason of 5 to 500 characters', () => {
      expect(reasonValidator(new FormControl('  Duplicado  '))).toBeNull();
      expect(reasonValidator(new FormControl('x'.repeat(500)))).toBeNull();
      expect(reasonValidator(new FormControl('x'.repeat(501)))).not.toBeNull();
      expect(errorOf('x'.repeat(501))).toBe('El motivo admite como máximo 500 caracteres.');
    });

    it('shows the server message when the backend rejected the value', () => {
      const control = new FormControl('Duplicado', reasonValidator);
      control.setErrors({ server: 'Debe tener al menos 5 caracteres.' });
      expect(reasonError(control)).toBe('Debe tener al menos 5 caracteres.');
    });
  });

  it('labels categories from the catalog and falls back gracefully', () => {
    const names = new Map([['network', 'Red y conectividad']]);
    expect(categoryLabel('network', names)).toBe('Red y conectividad');
    expect(categoryLabel('other', names)).toBe('other');
    expect(categoryLabel(null, names)).toBe('Sin categoría');
    expect(categoryLabel('uncategorized', names)).toBe('Sin categoría');
  });

  it('gives non-zero shares a visible minimum', () => {
    expect(share(0, 10)).toBe(0);
    expect(share(1, 1000)).toBe(4);
    expect(share(5, 10)).toBe(50);
    expect(share(3, 0)).toBe(0);
  });
});
