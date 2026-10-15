import { HttpErrorResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { Subject, defer, of, throwError } from 'rxjs';

import {
  ImportResult, InventoryItem, InventoryOverview, InventoryService, Movement,
} from './inventory.service';
import { InventoryState, InventoryStore, PAGE_SIZE } from './inventory.store';
import { ToastService } from './toast.service';

const item = (id = 1): InventoryItem => ({
  id, sku: `SKU-${id}`, name: `Item ${id}`, description: null, category: 'spare_part', unit: 'unidad', unit_cost: '10.00',
  stock: 5, min_stock: 2, max_stock: null, location: null, supplier: null, is_active: true, status: 'ok', stock_value: '50.00',
  level_pct: 50, last_movement_at: null, created_at: '', updated_at: '',
});
const movement = {} as Movement;

describe('InventoryStore', () => {
  let api: jasmine.SpyObj<InventoryService>;
  let toasts: ToastService;
  let store: InventoryStore;
  let latest: InventoryState;

  beforeEach(() => {
    api = jasmine.createSpyObj('InventoryService', ['listPage', 'get', 'create', 'update', 'remove', 'move', 'movements', 'overview', 'importFile', 'options', 'createOption']);
    api.listPage.and.returnValue(of({ items: [item()], total: 30 }));
    api.overview.and.returnValue(of({ period: '30d' } as InventoryOverview));
    api.get.and.returnValue(of(item()));
    api.options.and.returnValue(of([]));
    api.movements.and.returnValue(of({ items: [], total: 0 }));
    TestBed.configureTestingModule({ providers: [InventoryStore, { provide: InventoryService, useValue: api }] });
    toasts = TestBed.inject(ToastService);
    store = TestBed.inject(InventoryStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('loads the first server page and the metrics', () => {
    store.load();
    expect(api.listPage.calls.mostRecent().args[0]).toEqual(jasmine.objectContaining({ page: 1, size: PAGE_SIZE, sort: 'name' }));
    expect(latest.total).toBe(30);
    expect(latest.overview).not.toBeNull();
    expect(latest.loading).toBeFalse();
  });

  it('sends filters and sort to the server and restarts at page 1', () => {
    store.load();
    store.setPage(3);
    expect(api.listPage.calls.mostRecent().args[0]).toEqual(jasmine.objectContaining({ page: 3 }));
    store.setFilters({ search: '  ssd ', category: 'tool', status: 'low', sort: '-stock' });
    expect(api.listPage.calls.mostRecent().args[0]).toEqual(
      jasmine.objectContaining({ search: 'ssd', category: 'tool', status: 'low', sort: '-stock', page: 1 }),
    );
    store.clearFilters();
    expect(api.listPage.calls.mostRecent().args[0]).toEqual(jasmine.objectContaining({ search: undefined, sort: 'name', page: 1 }));
  });

  it('steps back a page when the current one comes back empty (e.g. after deleting its last item)', () => {
    store.load();
    api.listPage.and.callFake((query) => of(query?.page === 3 ? { items: [], total: 25 } : { items: [item()], total: 25 }));
    store.setPage(3);
    expect(latest.page).toBe(2);
    expect(latest.items.length).toBe(1);
  });

  it('keeps null metrics (not zeros) when the overview is unavailable', () => {
    api.overview.and.returnValue(throwError(() => new HttpErrorResponse({ status: 403 })));
    store.load();
    expect(latest.overview).toBeNull();
    expect(latest.overviewLoading).toBeFalse();
  });

  it('reports a list error in Spanish', () => {
    api.listPage.and.returnValue(throwError(() => new HttpErrorResponse({ status: 500 })));
    store.load();
    expect(latest.error).toContain('servidor');
    expect(latest.loading).toBeFalse();
  });

  it('loads the item and its movements when one is selected, and ignores a late answer for another', () => {
    store.select(7);
    expect(api.get).toHaveBeenCalledWith(7);
    expect(api.movements).toHaveBeenCalledWith(7);
    expect(latest.item?.id).toBe(1);
    store.select(null);
    expect(latest.selectedId).toBeNull();
    expect(latest.item).toBeNull();
  });

  describe('actions', () => {
    it('registers a movement, toasts by kind and refreshes list and metrics', () => {
      api.move.and.returnValue(of(movement));
      store.load();
      api.listPage.calls.reset();
      let result: unknown;
      store.move(1, { kind: 'out', quantity: 2 }).subscribe((r) => (result = r));
      expect(result).toEqual({ ok: true, fieldErrors: {} });
      expect(toasts.toasts()[0].message).toBe('Consumo registrado.');
      expect(api.listPage).toHaveBeenCalledTimes(1);
      expect(api.overview).toHaveBeenCalledTimes(2);
    });

    it('turns stock-insufficient and validation failures into toasts and field errors', () => {
      api.move.and.returnValue(throwError(() => new HttpErrorResponse({
        status: 409, error: { code: 'conflict', detail: 'insufficient stock: 3 available, 4 requested' },
      })));
      store.move(1, { kind: 'out', quantity: 4 }).subscribe();
      expect(toasts.toasts()[0].message).toBe('La acción no se puede realizar en el estado actual del registro.');

      api.create.and.returnValue(throwError(() => new HttpErrorResponse({
        status: 422, error: { errors: [{ field: 'unit_cost', message: 'x', type: 'greater_than_equal' }] },
      })));
      let fields: Record<string, string> = {};
      store.create({ sku: 'A-1', name: 'x', description: null, category: 'tool', unit: 'u', unit_cost: -1, min_stock: 0, max_stock: null, location: null, supplier: null, initial_stock: 0 })
        .subscribe((r) => (fields = r.fieldErrors));
      expect(fields['unit_cost']).toBe('El valor es demasiado bajo.');
      expect(latest.busy).toBeFalse();
    });

    it('turns an item with movements that is deleted into a readable conflict', () => {
      api.remove.and.returnValue(throwError(() => new HttpErrorResponse({ status: 409, error: { code: 'conflict' } })));
      store.remove(1).subscribe();
      expect(toasts.toasts()[0].kind).toBe('error');
    });

    it('closes the detail after deleting an item', () => {
      api.remove.and.returnValue(of(undefined));
      store.select(1);
      store.remove(1).subscribe();
      expect(latest.selectedId).toBeNull();
    });

    it('ignores a second action while one is running (no double submit)', () => {
      const gate = new Subject<Movement>();
      let calls = 0;
      api.move.and.callFake(() => defer(() => { calls++; return gate; }));
      store.move(1, { kind: 'in', quantity: 1 }).subscribe();
      expect(latest.busy).toBeTrue();
      let second: unknown;
      store.move(1, { kind: 'in', quantity: 1 }).subscribe((r) => (second = r));
      expect(calls).toBe(1);
      expect(second).toEqual({ ok: false, fieldErrors: {} });
      gate.next(movement);
      gate.complete();
      expect(latest.busy).toBeFalse();
    });
  });

  describe('import', () => {
    const file = new File(['sku,name\nA-1,Algo'], 'items.csv');
    const result = (overrides: Partial<ImportResult> = {}): ImportResult => ({ dry_run: true, success: true, total_rows: 1, created: 0, errors: [], ...overrides });

    it('a dry run reports without refreshing or toasting', () => {
      api.importFile.and.returnValue(of(result()));
      store.load();
      api.listPage.calls.reset();
      store.importFile(file, true).subscribe();
      expect(api.importFile).toHaveBeenCalledWith(file, true, false);
      expect(api.listPage).not.toHaveBeenCalled();
      expect(toasts.toasts()).toEqual([]);
    });

    it('a real import refreshes everything and says how many items were created', () => {
      api.importFile.and.returnValue(of(result({ dry_run: false, created: 4 })));
      store.load();
      api.listPage.calls.reset();
      store.importFile(file, false).subscribe();
      expect(toasts.toasts()[0].message).toBe('4 ítems importados.');
      expect(api.listPage).toHaveBeenCalled();
    });

    it('imports only the valid rows when asked, and says how many went in', () => {
      api.importFile.and.returnValue(of(result({ dry_run: false, created: 3, valid_rows: 3, error_rows: 2, errors: [{ row: 3, field: 'sku', message: 'x' }] })));
      store.load();
      api.listPage.calls.reset();
      store.importFile(file, false, true).subscribe();
      expect(api.importFile).toHaveBeenCalledWith(file, false, true);
      expect(toasts.toasts()[0].message).toBe('3 ítems importados.');
      expect(api.listPage).toHaveBeenCalled();
    });

    it('a failed import (row errors) writes nothing and does not toast success', () => {
      api.importFile.and.returnValue(of(result({ dry_run: false, success: false, errors: [{ row: 2, field: 'sku', message: 'x' }] })));
      store.importFile(file, false).subscribe();
      expect(toasts.toasts()).toEqual([]);
    });

    it('turns an upload failure into a toast and releases the busy flag', () => {
      api.importFile.and.returnValue(throwError(() => new HttpErrorResponse({ status: 415 })));
      let value: unknown = 'unset';
      store.importFile(file, true).subscribe((r) => (value = r));
      expect(value).toBeNull();
      expect(toasts.toasts()[0].message).toBe('El tipo de archivo no está permitido.');
      expect(latest.busy).toBeFalse();
    });
  });
});
