import { FormControl, FormGroup } from '@angular/forms';

import { ReportDefinition } from '../../core/reports.service';
import {
  EMPTY_VALUES, FilterValues, canCompare, dateRangeValidator, dayBoundaryIso, describeFilters, parseDay, rangeError, toApiFilters,
} from './report-filters';

const tickets: ReportDefinition = {
  key: 'tickets', title: 'Tickets', description: '', icon: 'x', supports_compare: true,
  filters: [
    { key: 'statuses', label: 'Estado', kind: 'multiselect', options: [{ value: 'closed', label: 'Cerrado' }, { value: 'resolved', label: 'Resuelto' }] },
    { key: 'priorities', label: 'Prioridad', kind: 'multiselect', options: [{ value: 'high', label: 'Alta' }] },
    { key: 'dates', label: 'Creados entre', kind: 'dates', options: [] },
  ],
};
const equipment: ReportDefinition = {
  key: 'equipment', title: 'Equipos', description: '', icon: 'x', supports_compare: false,
  filters: [
    { key: 'statuses', label: 'Estado', kind: 'multiselect', options: [] },
    { key: 'equipment_type_ids', label: 'Tipo', kind: 'multiselect', options: [] },
  ],
};
const summary: ReportDefinition = {
  key: 'summary', title: 'Resumen', description: '', icon: 'x', supports_compare: false,
  filters: [{ key: 'days', label: 'Periodo', kind: 'days', options: [{ value: '30', label: 'Últimos 30 días' }] }],
};
const values = (overrides: Partial<FilterValues> = {}): FilterValues => ({ ...EMPTY_VALUES, ...overrides });
const group = (from: string, to: string) => new FormGroup({ dateFrom: new FormControl(from), dateTo: new FormControl(to) });

describe('report filters', () => {
  describe('days', () => {
    it('only accepts real calendar days', () => {
      expect(parseDay('2026-09-30')).not.toBeNull();
      expect(parseDay('2026-02-30')).toBeNull();
      expect(parseDay('2027-02-29')).toBeNull();
      expect(parseDay('2028-02-29')).not.toBeNull(); // bisiesto
      expect(parseDay('2026-13-01')).toBeNull();
      expect(parseDay('30/09/2026')).toBeNull();
      expect(parseDay('')).toBeNull();
    });

    it('turns a day into the start or the end of that local day', () => {
      const start = new Date(dayBoundaryIso('2026-09-30', false)!);
      const end = new Date(dayBoundaryIso('2026-09-30', true)!);
      expect([start.getHours(), start.getMinutes(), start.getDate()]).toEqual([0, 0, 30]);
      expect([end.getHours(), end.getMinutes(), end.getSeconds()]).toEqual([23, 59, 59]);
      expect(dayBoundaryIso('2026-02-30', false)).toBeNull();
    });
  });

  describe('range validator', () => {
    it('accepts empty, one-sided and same-day ranges', () => {
      for (const [from, to] of [['', ''], ['2026-09-01', ''], ['', '2026-09-30'], ['2026-09-05', '2026-09-05']]) {
        expect(dateRangeValidator(group(from, to))).toBeNull();
      }
    });

    it('rejects an inverted range and impossible dates', () => {
      expect(dateRangeValidator(group('2026-09-10', '2026-09-01'))).toEqual({ rangeInverted: true });
      expect(dateRangeValidator(group('2026-02-30', '2026-03-05'))).toEqual({ invalidDate: true });
      expect(dateRangeValidator(group('2026-09-01', '2026-13-01'))).toEqual({ invalidDate: true });
    });

    it('allows 366 days inclusive and rejects 367', () => {
      expect(dateRangeValidator(group('2026-01-01', '2026-12-31'))).toBeNull(); // 365 días
      expect(dateRangeValidator(group('2028-01-01', '2028-12-31'))).toBeNull(); // 366 días (bisiesto)
      expect(dateRangeValidator(group('2026-01-01', '2027-01-02'))).toEqual({ rangeTooLong: { max: 366 } });
    });

    it('explains each error in Spanish', () => {
      expect(rangeError(null)).toBe('');
      expect(rangeError({ rangeInverted: true })).toBe('La fecha final no puede ser anterior a la inicial.');
      expect(rangeError({ invalidDate: true })).toBe('La fecha no existe en el calendario.');
      expect(rangeError({ rangeTooLong: { max: 366 } })).toBe('El rango no puede superar 366 días.');
    });
  });

  describe('toApiFilters', () => {
    it('sends lists and the day boundaries, and leaves out empty filters', () => {
      const api = toApiFilters(tickets, values({ statuses: ['closed', 'resolved'], dateFrom: '2026-09-01', dateTo: '2026-09-30' }));
      expect(api.statuses).toEqual(['closed', 'resolved']);
      expect(api.priorities).toBeUndefined();
      expect(new Date(api.date_from!).getDate()).toBe(1);
      expect(new Date(api.date_to!).getHours()).toBe(23);
    });

    it('never carries filters the chosen report does not take (the API would reject them)', () => {
      const stale = values({ statuses: ['x'], priorities: ['high'], dateFrom: '2026-09-01', kinds: ['in'], categories: ['tool'], days: '90' });
      expect(Object.keys(toApiFilters(equipment, stale))).toEqual(['statuses']);
      expect(toApiFilters(summary, stale)).toEqual({ days: 90 });
    });

    it('converts equipment types to numbers and ignores an unparseable date', () => {
      expect(toApiFilters(equipment, values({ equipment_type_ids: ['3', '7'] })).equipment_type_ids).toEqual([3, 7]);
      expect(toApiFilters(tickets, values({ dateFrom: '2026-02-30' })).date_from).toBeUndefined();
    });
  });

  it('describes the active filters in a readable line', () => {
    expect(describeFilters(tickets, values())).toBe('Sin filtros');
    expect(describeFilters(tickets, values({ statuses: ['closed'], dateFrom: '2026-09-01' })))
      .toBe('Estado: Cerrado · Creados entre: 2026-09-01 a …');
    expect(describeFilters(summary, values({ days: '30' }))).toBe('Últimos 30 días');
  });

  it('allows comparing only when the report supports it and both dates are set', () => {
    expect(canCompare(tickets, values({ dateFrom: '2026-09-01', dateTo: '2026-09-30' }))).toBeTrue();
    expect(canCompare(tickets, values({ dateFrom: '2026-09-01' }))).toBeFalse();
    expect(canCompare(tickets, values({ dateFrom: '2026-02-30', dateTo: '2026-03-30' }))).toBeFalse();
    expect(canCompare(equipment, values({ dateFrom: '2026-09-01', dateTo: '2026-09-30' }))).toBeFalse();
  });
});
