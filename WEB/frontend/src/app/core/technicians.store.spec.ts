import { TestBed } from '@angular/core/testing';
import { of, throwError } from 'rxjs';

import { Technician, TechniciansService, WorkloadResponse } from './technicians.service';
import { TechniciansState, TechniciansStore } from './technicians.store';

const technician = (id: number, overrides: Partial<Technician> = {}): Technician => ({
  id, user_id: id + 10, full_name: `Tec ${id}`, email: `tec${id}@mantix.io`, employee_code: null,
  specialization: null, is_available: true, hourly_rate: null, created_at: '2026-01-01T00:00:00Z', ...overrides,
});

const workload: WorkloadResponse = {
  window_days: 30,
  scope: 'all',
  technicians: [{ technician_id: 1, full_name: 'Tec 1', is_available: true, open_tickets: 2, resolved_in_window: 9 }],
};

describe('TechniciansStore', () => {
  let api: jasmine.SpyObj<TechniciansService>;
  let store: TechniciansStore;
  let latest: TechniciansState;

  beforeEach(() => {
    api = jasmine.createSpyObj('TechniciansService', ['list', 'workload', 'create', 'update']);
    TestBed.configureTestingModule({
      providers: [TechniciansStore, { provide: TechniciansService, useValue: api }],
    });
    store = TestBed.inject(TechniciansStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('loads the technicians together with their workload', () => {
    api.list.and.returnValue(of([technician(1), technician(2)]));
    api.workload.and.returnValue(of(workload));

    store.load();

    expect(latest.technicians.length).toBe(2);
    expect(latest.workload[1]?.open_tickets).toBe(2);
    expect(latest.workload[2]).toBeUndefined();
    expect(latest.hasWorkload).toBeTrue();
    expect(latest.loading).toBeFalse();
  });

  it('still lists the technicians when the workload cannot be read', () => {
    api.list.and.returnValue(of([technician(1)]));
    api.workload.and.returnValue(throwError(() => new Error('403')));

    store.load();

    expect(latest.technicians.length).toBe(1);
    expect(latest.hasWorkload).toBeFalse();
    expect(latest.error).toBe('');
  });

  it('reports a failure to load the list', () => {
    api.list.and.returnValue(throwError(() => new Error('boom')));
    api.workload.and.returnValue(of(workload));

    store.load();

    expect(latest.loading).toBeFalse();
    expect(latest.error).toContain('No se pudieron cargar');
  });

  it('adds a created technician, announces it and says so to the user', () => {
    api.list.and.returnValue(of([technician(1)]));
    api.workload.and.returnValue(of(workload));
    api.create.and.returnValue(of(technician(2)));
    store.load();
    const saved: number[] = [];
    store.saved$.subscribe((item) => saved.push(item.id));

    store.create({ user_id: 12, specialization: null, hourly_rate: null });

    expect(latest.technicians.map((item) => item.id)).toEqual([1, 2]);
    expect(saved).toEqual([2]);
    expect(latest.notice).toContain('Tec 2');
    expect(latest.saving).toBeFalse();
  });

  it('keeps the list and explains a creation failure', () => {
    api.list.and.returnValue(of([technician(1)]));
    api.workload.and.returnValue(of(workload));
    api.create.and.returnValue(throwError(() => new Error('409')));
    store.load();

    store.create({ user_id: 11, specialization: null, hourly_rate: null });

    expect(latest.technicians.length).toBe(1);
    expect(latest.error).toContain('ya tiene un perfil');
    expect(latest.saving).toBeFalse();
  });

  it('replaces the technician with the server response after an update', () => {
    api.list.and.returnValue(of([technician(1), technician(2)]));
    api.workload.and.returnValue(of(workload));
    api.update.and.returnValue(of(technician(1, { is_available: false })));
    store.load();

    store.setAvailability(latest.technicians[0], false);

    expect(api.update).toHaveBeenCalledWith(1, { is_available: false });
    expect(latest.technicians[0].is_available).toBeFalse();
    expect(latest.notice).toBe('Tec 1 ahora está no disponible.');
  });

  it('clears messages on demand', () => {
    api.list.and.returnValue(of([technician(1)]));
    api.workload.and.returnValue(of(workload));
    api.update.and.returnValue(of(technician(1)));
    store.load();
    store.update(1, { specialization: 'Redes' }, 'Perfil actualizado.');

    store.clearMessages();

    expect(latest.notice).toBe('');
  });
});
