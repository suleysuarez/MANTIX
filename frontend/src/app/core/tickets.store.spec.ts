import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { EquipmentService } from './equipment.service';
import { MaintenanceListItem, MaintenanceRequest, MaintenanceService } from './maintenance.service';
import { TicketsState, TicketsStore, dayBoundaryIso } from './tickets.store';

const row = (id: number, status = 'submitted', priority = 'medium'): MaintenanceListItem => ({
  id, ticket_number: `TCK-${id}`, equipment_id: 1, title: 't', priority, status,
  created_at: '2026-01-01T00:00:00Z',
});

describe('TicketsStore', () => {
  let api: jasmine.SpyObj<MaintenanceService>;
  let equipmentApi: jasmine.SpyObj<EquipmentService>;
  let store: TicketsStore;
  let latest: TicketsState;

  beforeEach(() => {
    api = jasmine.createSpyObj('MaintenanceService', ['list', 'create']);
    equipmentApi = jasmine.createSpyObj('EquipmentService', ['listAll']);
    equipmentApi.listAll.and.returnValue(of([]));
    TestBed.configureTestingModule({
      providers: [
        TicketsStore,
        { provide: MaintenanceService, useValue: api },
        { provide: EquipmentService, useValue: equipmentApi },
      ],
    });
    store = TestBed.inject(TicketsStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('loads one extra row to detect a next page and trims it', () => {
    api.list.and.returnValue(of(Array.from({ length: 21 }, (_, i) => row(i + 1))));

    store.load();

    expect(latest.items.length).toBe(20);
    expect(latest.hasNext).toBeTrue();
    expect(latest.all.length).toBe(21);
  });

  it('sends every filter to the API and goes back to the first page', () => {
    api.list.and.returnValue(of([]));
    store.load();
    store.setPage(3);

    store.setFilters({
      search: ' bios ', status: 'assigned', priority: 'high', order: 'priority',
      dateFrom: '2026-03-01', dateTo: '2026-03-31',
    });

    const query = api.list.calls.mostRecent().args[0]!;
    expect(latest.page).toBe(0);
    expect(query).toEqual({
      status: 'assigned', priority: 'high', search: 'bios', sort: '-priority',
      dateFrom: dayBoundaryIso('2026-03-01', false), dateTo: dayBoundaryIso('2026-03-31', true),
      limit: 21, offset: 0,
    });
  });

  it('omits empty filters and sorts newest first by default', () => {
    api.list.and.returnValue(of([]));

    store.load();

    expect(api.list.calls.first().args[0]).toEqual({
      status: '', priority: '', search: '', sort: '-created_at', limit: 21, offset: 0,
    });
  });

  it('rejects an inverted date range without calling the API', () => {
    api.list.and.returnValue(of([]));
    store.load();
    const calls = api.list.calls.count();

    store.setFilters({ dateFrom: '2026-03-10', dateTo: '2026-03-01' });

    expect(latest.filterError).toContain('"desde"');
    expect(api.list.calls.count()).toBe(calls);
  });

  it('rejects future dates and recovers once the range is valid', () => {
    api.list.and.returnValue(of([]));
    store.load();

    store.setFilters({ dateTo: '2999-01-01' });
    expect(latest.filterError).toContain('futuras');

    store.setFilters({ dateTo: '2026-03-01' });
    expect(latest.filterError).toBe('');
  });

  it('clears the filters', () => {
    api.list.and.returnValue(of([]));
    store.load();
    store.setFilters({ status: 'closed' });

    store.clearFilters();

    expect(latest.filters.status).toBe('');
    expect(latest.filters.order).toBe('newest');
  });

  it('still shows the list when the unfiltered counters fail', () => {
    api.list.and.callFake((query) =>
      query?.limit === 500 ? throwError(() => new Error('boom')) : of([row(1)]),
    );

    store.load();

    expect(latest.items.length).toBe(1);
    expect(latest.all).toEqual([]);
    expect(latest.error).toBe('');
  });

  it('announces the created ticket and refreshes the list', () => {
    api.list.and.returnValue(of([row(1)]));
    api.create.and.returnValue(of({ id: 42 } as MaintenanceRequest));
    store.load();
    const created: number[] = [];
    store.ticketCreated$.subscribe((id) => created.push(id));
    const calls = api.list.calls.count();

    store.create({ equipment_id: 1, title: 't', description: 'd', priority: 'medium' });

    expect(created).toEqual([42]);
    expect(latest.saving).toBeFalse();
    expect(api.list.calls.count()).toBeGreaterThan(calls);
  });

  it('reports a creation failure without losing the list', () => {
    api.list.and.returnValue(of([row(1)]));
    api.create.and.returnValue(throwError(() => new Error('bad')));
    store.load();

    store.create({ equipment_id: 1, title: 't', description: 'd', priority: 'medium' });

    expect(latest.items.length).toBe(1);
    expect(latest.saving).toBeFalse();
    expect(latest.error).toContain('No se pudo crear');
  });
});
