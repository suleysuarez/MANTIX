import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { EquipmentService } from './equipment.service';
import { MaintenanceDetailStore, MaintenanceDetailState } from './maintenance-detail.store';
import { MaintenanceListItem, MaintenanceRequest, MaintenanceService } from './maintenance.service';
import { MaintenanceListState, MaintenanceStore } from './maintenance.store';
import { TechniciansService } from './technicians.service';

const row = (id: number): MaintenanceListItem => ({
  id, ticket_number: `TCK-${id}`, equipment_id: 1, title: 't', priority: 'medium',
  status: 'submitted', created_at: '2026-01-01T00:00:00Z',
});

const ticket = (status: string, allowed: string[] = []): MaintenanceRequest =>
  ({ id: 7, status, allowed_next_statuses: allowed, status_history: [] }) as unknown as MaintenanceRequest;

describe('MaintenanceStore', () => {
  let api: jasmine.SpyObj<MaintenanceService>;
  let equipmentApi: jasmine.SpyObj<EquipmentService>;
  let store: MaintenanceStore;
  let latest: MaintenanceListState;

  beforeEach(() => {
    api = jasmine.createSpyObj('MaintenanceService', ['list', 'create']);
    equipmentApi = jasmine.createSpyObj('EquipmentService', ['list']);
    TestBed.configureTestingModule({
      providers: [
        MaintenanceStore,
        { provide: MaintenanceService, useValue: api },
        { provide: EquipmentService, useValue: equipmentApi },
      ],
    });
    store = TestBed.inject(MaintenanceStore);
    store.state$.subscribe((state) => (latest = state));
    equipmentApi.list.and.returnValue(of([]));
  });

  it('loads one extra row to detect a next page and trims it', () => {
    api.list.and.returnValue(of(Array.from({ length: 21 }, (_, i) => row(i + 1))));

    store.load();

    expect(api.list).toHaveBeenCalledWith({ status: '', priority: '', limit: 21, offset: 0 });
    expect(latest.items.length).toBe(20);
    expect(latest.hasNext).toBeTrue();
  });

  it('changing filters goes back to the first page', () => {
    api.list.and.returnValue(of([]));
    store.load();
    store.setPage(3);

    store.setFilters('assigned', 'high');

    expect(latest.page).toBe(0);
    expect(api.list.calls.mostRecent().args[0]).toEqual({ status: 'assigned', priority: 'high', limit: 21, offset: 0 });
  });

  it('creates a request, signals the form and reloads the list', () => {
    api.list.and.returnValue(of([row(1)]));
    api.create.and.returnValue(of({} as MaintenanceRequest));
    store.load();
    let created = 0;
    store.requestCreated$.subscribe(() => created++);

    store.create({ equipment_id: 1, title: 't', description: 'd', priority: 'medium' });

    expect(created).toBe(1);
    expect(latest.saving).toBeFalse();
    expect(api.list.calls.count()).toBe(2);
  });

  it('reports a creation failure without losing the list', () => {
    api.list.and.returnValue(of([row(1)]));
    api.create.and.returnValue(throwError(() => new Error('bad')));
    store.load();

    store.create({ equipment_id: 1, title: 't', description: 'd', priority: 'medium' });

    expect(latest.items.length).toBe(1);
    expect(latest.error).toContain('could not be created');
  });
});

describe('MaintenanceDetailStore', () => {
  let api: jasmine.SpyObj<MaintenanceService>;
  let techniciansApi: jasmine.SpyObj<TechniciansService>;
  let store: MaintenanceDetailStore;
  let latest: MaintenanceDetailState;

  beforeEach(() => {
    api = jasmine.createSpyObj('MaintenanceService', ['get', 'listRecords', 'transition', 'assign', 'unassign', 'addRecord']);
    techniciansApi = jasmine.createSpyObj('TechniciansService', ['list']);
    TestBed.configureTestingModule({
      providers: [
        MaintenanceDetailStore,
        { provide: MaintenanceService, useValue: api },
        { provide: TechniciansService, useValue: techniciansApi },
      ],
    });
    store = TestBed.inject(MaintenanceDetailStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('still shows the ticket when the user cannot list technicians', () => {
    api.get.and.returnValue(of(ticket('submitted', ['triaged'])));
    api.listRecords.and.returnValue(of([]));
    techniciansApi.list.and.returnValue(throwError(() => new Error('403')));

    store.load(7);

    expect(latest.request?.status).toBe('submitted');
    expect(latest.technicians).toEqual([]);
    expect(latest.loading).toBeFalse();
  });

  it('replaces the ticket with the server response after a transition', () => {
    api.get.and.returnValue(of(ticket('submitted', ['triaged'])));
    api.listRecords.and.returnValue(of([]));
    techniciansApi.list.and.returnValue(of([]));
    api.transition.and.returnValue(of(ticket('triaged', ['assigned'])));
    store.load(7);

    store.transition('triaged', null, null);

    expect(api.transition).toHaveBeenCalledWith(7, 'triaged', null, null);
    expect(latest.request?.status).toBe('triaged');
    expect(latest.busy).toBeFalse();
  });

  it('keeps the current ticket and reports an error when a transition fails', () => {
    api.get.and.returnValue(of(ticket('submitted', ['triaged'])));
    api.listRecords.and.returnValue(of([]));
    techniciansApi.list.and.returnValue(of([]));
    api.transition.and.returnValue(throwError(() => new Error('conflict')));
    store.load(7);

    store.transition('closed', null, null);

    expect(latest.request?.status).toBe('submitted');
    expect(latest.error).toContain('could not be changed');
  });
});
