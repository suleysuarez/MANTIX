import { HttpErrorResponse, HttpHeaders, HttpResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { Subject, of, throwError } from 'rxjs';

import { EMPTY_VALUES } from '../features/reports/report-filters';
import {
  Catalog, ReportPreview, ReportsOverview, ReportsService, ReportDefinition, filenameFrom,
} from './reports.service';
import { ReportsState, ReportsStore, readableError } from './reports.store';
import { ToastService } from './toast.service';

const definition = (key: ReportDefinition['key'], compare: boolean, filters: ReportDefinition['filters']): ReportDefinition => ({
  key, title: key, description: '', icon: 'x', supports_compare: compare, filters,
});
const catalog: Catalog = {
  reports: [
    definition('tickets', true, [{ key: 'statuses', label: 'Estado', kind: 'multiselect', options: [] }, { key: 'dates', label: 'Fechas', kind: 'dates', options: [] }]),
    definition('equipment', false, [{ key: 'statuses', label: 'Estado', kind: 'multiselect', options: [] }]),
  ],
  max_rows: 10000, max_range_days: 366, formats: ['xlsx', 'pdf', 'csv'],
};
const preview = (total = 3): ReportPreview => ({ report: 'tickets', title: 'T', columns: [], rows: [], total_rows: total, truncated: false, comparison: null });

describe('ReportsStore', () => {
  let api: jasmine.SpyObj<ReportsService>;
  let toasts: ToastService;
  let store: ReportsStore;
  let latest: ReportsState;

  beforeEach(() => {
    api = jasmine.createSpyObj('ReportsService', ['catalog', 'preview', 'generate', 'overview', 'history']);
    api.catalog.and.returnValue(of(catalog));
    api.overview.and.returnValue(of({ generated: 3 } as ReportsOverview));
    api.history.and.returnValue(of({ items: [], total: 0 }));
    api.preview.and.returnValue(of(preview()));
    TestBed.configureTestingModule({ providers: [ReportsStore, { provide: ReportsService, useValue: api }] });
    toasts = TestBed.inject(ToastService);
    store = TestBed.inject(ReportsStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('loads the gallery, the activity and the history, selecting the first report', () => {
    store.load();
    expect(latest.catalog?.reports.length).toBe(2);
    expect(latest.selected).toBe('tickets');
    expect(latest.overview?.generated).toBe(3);
    expect(api.history).toHaveBeenCalledWith(1, 8);
  });

  it('keeps null activity (not zeros) when it is unavailable', () => {
    api.overview.and.returnValue(throwError(() => new HttpErrorResponse({ status: 403 })));
    store.load();
    expect(latest.overview).toBeNull();
  });

  it('reports a gallery error in Spanish', () => {
    api.catalog.and.returnValue(throwError(() => new HttpErrorResponse({ status: 500 })));
    store.load();
    expect(latest.catalogError).toContain('servidor');
    expect(latest.catalogLoading).toBeFalse();
  });

  describe('preview', () => {
    beforeEach(() => store.load());

    it('asks for the preview with the API filters of the selected report', () => {
      store.requestPreview({ ...EMPTY_VALUES, statuses: ['closed'], dateFrom: '2026-09-01', dateTo: '2026-09-30' }, true);
      const [report, filters, compare] = api.preview.calls.mostRecent().args;
      expect(report).toBe('tickets');
      expect(filters.statuses).toEqual(['closed']);
      expect(filters.date_from).toBeDefined();
      expect(compare).toBeTrue();
      expect(latest.preview?.total_rows).toBe(3);
    });

    it('never asks for a comparison on a report that cannot be compared', () => {
      store.select('equipment');
      store.requestPreview({ ...EMPTY_VALUES, statuses: ['assigned'], priorities: ['high'] }, true);
      const [, filters, compare] = api.preview.calls.mostRecent().args;
      expect(compare).toBeFalse();
      expect(Object.keys(filters)).toEqual(['statuses']);
    });

    it('drops the previous preview when another report is selected', () => {
      store.requestPreview(EMPTY_VALUES, false);
      store.select('equipment');
      expect(latest.preview).toBeNull();
      expect(latest.selected).toBe('equipment');
    });

    it('ignores a slow answer that is no longer the latest request', () => {
      const slow = new Subject<ReportPreview>();
      api.preview.and.returnValue(slow);
      store.requestPreview(EMPTY_VALUES, false);
      api.preview.and.returnValue(of(preview(9)));
      store.requestPreview({ ...EMPTY_VALUES, statuses: ['closed'] }, false);
      slow.next(preview(1));
      slow.complete();
      expect(latest.preview?.total_rows).toBe(9);
    });

    it('shows the API error in Spanish without leaking the server text', () => {
      api.preview.and.returnValue(throwError(() => new HttpErrorResponse({ status: 422, error: { code: 'unprocessable', detail: 'internal detail' } })));
      store.requestPreview(EMPTY_VALUES, false);
      expect(latest.previewError).toBe('Revisa los campos marcados.');
      expect(latest.previewLoading).toBeFalse();
    });
  });

  describe('export', () => {
    beforeEach(() => {
      store.load();
      spyOn(URL, 'createObjectURL').and.returnValue('blob:x');
      spyOn(URL, 'revokeObjectURL');
      spyOn(HTMLAnchorElement.prototype, 'click');
    });

    it('downloads the file, toasts, and refreshes activity and history', () => {
      api.generate.and.returnValue(of({ blob: new Blob(['x']), filename: 'tickets-1.xlsx' }));
      api.overview.calls.reset();
      api.history.calls.reset();
      store.export('xlsx', EMPTY_VALUES);
      expect(api.generate).toHaveBeenCalledWith('tickets', 'xlsx', {});
      expect(HTMLAnchorElement.prototype.click).toHaveBeenCalled();
      expect(toasts.toasts()[0].message).toBe('Reporte generado: tickets-1.xlsx');
      expect(api.overview).toHaveBeenCalled();
      expect(api.history).toHaveBeenCalledWith(1, 8);
      expect(latest.exporting).toBeNull();
    });

    it('ignores a second click while the file is being generated', () => {
      const gate = new Subject<{ blob: Blob; filename: string }>();
      api.generate.and.returnValue(gate);
      store.export('pdf', EMPTY_VALUES);
      expect(latest.exporting).toBe('pdf');
      store.export('csv', EMPTY_VALUES);
      expect(api.generate).toHaveBeenCalledTimes(1);
      gate.next({ blob: new Blob(['x']), filename: 'a.pdf' });
      gate.complete();
      expect(latest.exporting).toBeNull();
    });

    it('turns a failed download into a readable toast, reading the JSON inside the blob', async () => {
      const body = new Blob([JSON.stringify({ code: 'unprocessable', detail: 'the report has more than 10000 rows' })], { type: 'application/json' });
      api.generate.and.returnValue(throwError(() => new HttpErrorResponse({ status: 422, error: body })));
      store.export('xlsx', EMPTY_VALUES);
      await new Promise((resolve) => setTimeout(resolve, 20));
      expect(toasts.toasts()[0].kind).toBe('error');
      expect(toasts.toasts()[0].message).toBe('Revisa los campos marcados.');
      expect(latest.exporting).toBeNull();
    });
  });

  it('readableError leaves a non-blob error untouched', async () => {
    const error = new HttpErrorResponse({ status: 500, error: 'x' });
    expect(await readableError(error)).toBe(error);
  });

  it('reads the file name from Content-Disposition, with a fallback', () => {
    const response = (header: string | null) =>
      new HttpResponse<Blob>({ body: new Blob(), headers: new HttpHeaders(header ? { 'Content-Disposition': header } : {}) });
    expect(filenameFrom(response('attachment; filename="tickets-20261014-1200.xlsx"'), 'x')).toBe('tickets-20261014-1200.xlsx');
    expect(filenameFrom(response(null), 'tickets.xlsx')).toBe('tickets.xlsx');
  });
});
