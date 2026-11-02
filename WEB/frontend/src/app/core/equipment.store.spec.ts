import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { Attachment, Equipment, EquipmentPayload, EquipmentService } from './equipment.service';
import { EquipmentState, EquipmentStore, SaveRequest } from './equipment.store';

const item = (id: number, tag: string): Equipment =>
  ({ id, asset_tag: tag, equipment_type: { id: 1, code: 'LAPTOP', name: 'Laptop' } }) as Equipment;

const payload: EquipmentPayload = {
  asset_tag: 'B', serial_number: null, equipment_type_id: 1, brand: 'Acme', model: 'Pro',
  description: null, status: 'in_storage', purchase_date: null, purchase_cost: null,
  warranty_start_date: null, warranty_end_date: null,
};

const request = (overrides: Partial<SaveRequest> = {}): SaveRequest => ({
  id: null, payload, locationId: null, custodianId: null, files: [], ...overrides,
});

describe('EquipmentStore', () => {
  let api: jasmine.SpyObj<EquipmentService>;
  let store: EquipmentStore;
  let latest: EquipmentState;

  beforeEach(() => {
    api = jasmine.createSpyObj('EquipmentService', [
      'list', 'listTypes', 'listLocations', 'summary', 'create', 'update',
      'assignLocation', 'assignCustody', 'uploadAttachment', 'exportReport',
    ]);
    api.list.and.returnValue(of({ items: [item(1, 'A')], total: 1 }));
    api.listTypes.and.returnValue(of([{ id: 1, code: 'LAPTOP', name: 'Laptop' }]));
    api.listLocations.and.returnValue(of([]));
    api.summary.and.returnValue(of({ total: 1, by_status: { assigned: 1 } }));
    TestBed.configureTestingModule({
      providers: [EquipmentStore, { provide: EquipmentService, useValue: api }],
    });
    store = TestBed.inject(EquipmentStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('emits the initial loading state to subscribers immediately', () => {
    expect(latest.loading).toBeTrue();
    expect(latest.items).toEqual([]);
    expect(latest.view).toBe('table');
  });

  it('publishes page, total, types and summary once loaded', () => {
    store.load();

    expect(latest.loading).toBeFalse();
    expect(latest.items.map((e) => e.asset_tag)).toEqual(['A']);
    expect(latest.total).toBe(1);
    expect(latest.types.length).toBe(1);
    expect(latest.summary?.total).toBe(1);
  });

  it('still loads the list when locations or the summary are unavailable', () => {
    api.listLocations.and.returnValue(throwError(() => new Error('403')));
    api.summary.and.returnValue(throwError(() => new Error('500')));

    store.load();

    expect(latest.items.length).toBe(1);
    expect(latest.locations).toEqual([]);
    expect(latest.summary).toBeNull();
    expect(latest.error).toBe('');
  });

  it('publishes an error when the list cannot be loaded', () => {
    api.list.and.returnValue(throwError(() => new Error('boom')));

    store.load();

    expect(latest.loading).toBeFalse();
    expect(latest.error).toContain('No se pudo cargar');
  });

  it('queries the server with the first page and the default sort', () => {
    store.load();

    expect(api.list).toHaveBeenCalledWith({
      search: '', status: '', equipmentTypeId: null, locationId: null, sort: 'asset_tag', page: 1, size: 10,
    });
  });

  it('changing a filter returns to page 1 and queries again', () => {
    api.list.and.returnValue(of({ items: [], total: 95 }));
    store.load();
    store.setPage(4);

    store.setFilters({ search: 'lap', status: 'assigned,in_storage', typeId: 2 });

    expect(latest.page).toBe(1);
    expect(latest.filters).toEqual({ search: 'lap', status: 'assigned,in_storage', typeId: 2, locationId: null });
    expect(api.list.calls.mostRecent().args[0]).toEqual(
      jasmine.objectContaining({ search: 'lap', status: 'assigned,in_storage', equipmentTypeId: 2, page: 1 }),
    );
  });

  it('resets every filter at once', () => {
    store.load();
    store.setFilters({ search: 'x', locationId: 3 });

    store.resetFilters();

    expect(latest.filters).toEqual({ search: '', status: '', typeId: null, locationId: null });
  });

  it('sorting goes back to page 1', () => {
    api.list.and.returnValue(of({ items: [], total: 95 }));
    store.load();
    store.setPage(3);

    store.setSort('-created_at');

    expect(latest.sort).toBe('-created_at');
    expect(latest.page).toBe(1);
  });

  it('pages within range only', () => {
    api.list.and.returnValue(of({ items: [], total: 25 })); // 3 pages of 10
    store.load();

    store.setPage(3);
    expect(latest.page).toBe(3);
    const calls = api.list.calls.count();
    store.setPage(4);
    store.setPage(0);
    expect(latest.page).toBe(3);
    expect(api.list.calls.count()).toBe(calls);
  });

  it('keeps the list when only the view changes', () => {
    store.load();
    const calls = api.list.calls.count();

    store.setView('grid');

    expect(latest.view).toBe('grid');
    expect(api.list.calls.count()).toBe(calls);
  });

  describe('save', () => {
    it('creates, then assigns location, custody and uploads files in order, then emits saved$', () => {
      const order: string[] = [];
      api.create.and.callFake(() => { order.push('create'); return of(item(2, 'B')); });
      api.assignLocation.and.callFake(() => { order.push('location'); return of(item(2, 'B')); });
      api.assignCustody.and.callFake(() => { order.push('custody'); return of(item(2, 'B')); });
      api.uploadAttachment.and.callFake((_id, file) => { order.push(`file:${file.name}`); return of({} as Attachment); });
      const saved: Equipment[] = [];
      store.saved$.subscribe((value) => saved.push(value));
      store.load();
      const loads = api.list.calls.count();

      store.save(request({
        locationId: 5, custodianId: 9,
        files: [new File(['a'], 'a.pdf'), new File(['b'], 'b.png')],
      }));

      expect(order).toEqual(['create', 'location', 'custody', 'file:a.pdf', 'file:b.png']);
      expect(saved.map((e) => e.id)).toEqual([2]);
      expect(latest.saving).toBeFalse();
      expect(latest.notice).toBe('');
      expect(api.list.calls.count()).toBe(loads + 1);
    });

    it('does not undo the registration when a follow-up step fails, and says so', () => {
      api.create.and.returnValue(of(item(2, 'B')));
      api.assignLocation.and.returnValue(throwError(() => new Error('403')));
      api.uploadAttachment.and.returnValue(throwError(() => new Error('415')));
      const saved: Equipment[] = [];
      store.saved$.subscribe((value) => saved.push(value));
      store.load();

      store.save(request({ locationId: 5, files: [new File(['a'], 'ficha.pdf')] }));

      expect(saved.length).toBe(1);
      expect(latest.notice).toContain('ubicación');
      expect(latest.notice).toContain('ficha.pdf');
      expect(latest.saveError).toBe('');
    });

    it('updates without sending the asset tag', () => {
      api.update.and.returnValue(of(item(7, 'B')));
      store.load();

      store.save(request({ id: 7 }));

      expect(api.create).not.toHaveBeenCalled();
      const [id, changes] = api.update.calls.mostRecent().args;
      expect(id).toBe(7);
      expect(changes).not.toEqual(jasmine.objectContaining({ asset_tag: jasmine.anything() }));
      expect('asset_tag' in changes).toBeFalse();
      expect(changes.brand).toBe('Acme');
    });

    it('ignores location, custody and files when editing', () => {
      api.update.and.returnValue(of(item(7, 'B')));
      store.load();

      store.save(request({ id: 7, locationId: 5, custodianId: 9, files: [new File(['a'], 'a.pdf')] }));

      expect(api.assignLocation).not.toHaveBeenCalled();
      expect(api.assignCustody).not.toHaveBeenCalled();
      expect(api.uploadAttachment).not.toHaveBeenCalled();
    });

    it('reports an error, keeps the list and does not emit saved$ when saving fails', () => {
      api.create.and.returnValue(throwError(() => new Error('conflict')));
      let emissions = 0;
      store.saved$.subscribe(() => emissions++);
      store.load();

      store.save(request());

      expect(latest.items.length).toBe(1);
      expect(latest.saving).toBeFalse();
      expect(latest.saveError).toContain('No se pudo guardar');
      expect(emissions).toBe(0);
    });

    it('clears notices and save errors on demand', () => {
      api.create.and.returnValue(throwError(() => new Error('x')));
      store.save(request());
      expect(latest.saveError).not.toBe('');

      store.clearNotice();

      expect(latest.saveError).toBe('');
      expect(latest.notice).toBe('');
    });
  });

  describe('export', () => {
    it('asks for the report with the current status and category filters', () => {
      api.exportReport.and.returnValue(throwError(() => new Error('403')));
      store.load();
      store.setFilters({ status: 'in_repair', typeId: 3 });

      store.export('xlsx');

      expect(api.exportReport).toHaveBeenCalledWith('xlsx', { status: 'in_repair', equipmentTypeId: 3 });
    });

    it('reports a failure and stops the spinner', () => {
      api.exportReport.and.returnValue(throwError(() => new Error('403')));

      store.export('pdf');

      expect(latest.exporting).toBeFalse();
      expect(latest.error).toContain('No se pudo generar');
    });
  });
});
