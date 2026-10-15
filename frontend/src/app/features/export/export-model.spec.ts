import { EMPTY_EXPORT_FILTERS, countMessage, toExportFilters } from './export-model';

describe('export-model', () => {
  describe('toExportFilters', () => {
    it('sends only what was chosen', () => {
      expect(toExportFilters(EMPTY_EXPORT_FILTERS)).toEqual({});
      const filters = toExportFilters({
        statuses: ['resolved'], priorities: ['high', 'low'], categories: ['hardware'], technicianIds: [4],
        dateFrom: '2026-10-01', dateTo: '2026-10-14',
      });
      expect(filters.statuses).toEqual(['resolved']);
      expect(filters.priorities).toEqual(['high', 'low']);
      expect(filters.categories).toEqual(['hardware']);
      expect(filters.technician_ids).toEqual([4]);
      expect(new Date(filters.date_from!).getHours()).toBe(0);
      expect(new Date(filters.date_to!).getHours()).toBe(23);
    });

    it('drops an impossible date instead of sending it', () => {
      const filters = toExportFilters({ ...EMPTY_EXPORT_FILTERS, dateFrom: '2026-02-30', dateTo: 'basura' });
      expect(filters.date_from).toBeUndefined();
      expect(filters.date_to).toBeUndefined();
    });
  });

  describe('toExportFilters (technician roster)', () => {
    it('sends nothing for empty roster values', () => {
      expect(toExportFilters({ ...EMPTY_EXPORT_FILTERS, search: '  ', specialty: '', active: '', availability: '', load: '' })).toEqual({});
    });

    it('translates the roster filters to the server names, trimming the text', () => {
      expect(toExportFilters({ ...EMPTY_EXPORT_FILTERS, search: ' ana ', specialty: 'Redes', active: 'inactive', availability: 'available', load: 'high' }))
        .toEqual({ search: 'ana', specialty: 'Redes', is_active: false, is_available: true, load: 'high' });
    });
  });

  describe('toExportFilters (users)', () => {
    it('sends the role code and the account state, and nothing for empty values', () => {
      expect(toExportFilters({ ...EMPTY_EXPORT_FILTERS, role: '  ', active: '' })).toEqual({});
      expect(toExportFilters({ ...EMPTY_EXPORT_FILTERS, role: ' ADMIN ', active: 'active' })).toEqual({ role: 'ADMIN', is_active: true });
    });
  });

  describe('countMessage', () => {
    it('explains each situation', () => {
      expect(countMessage(1, 10_000, 2_000)).toEqual({ text: 'Se exportará 1 registro.', tone: 'ok' });
    });

    it('says nothing matched, too many, large and normal', () => {
      expect(countMessage(0, 10_000, 2_000).tone).toBe('error');
      expect(countMessage(0, 10_000, 2_000).text).toContain('Ningún registro coincide');
      expect(countMessage(12_500, 10_000, 2_000)).toEqual({
        text: 'Son 12.500 registros y el máximo es 10.000. Acota los filtros para exportar.',
        tone: 'error',
      });
      expect(countMessage(2_500, 10_000, 2_000).tone).toBe('warn');
      expect(countMessage(2_500, 10_000, 2_000).text).toContain('puede tardar');
      expect(countMessage(40, 10_000, 2_000)).toEqual({ text: 'Se exportarán 40 registros.', tone: 'ok' });
    });
  });
});
