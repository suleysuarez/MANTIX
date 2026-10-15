import { HttpErrorResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { Subject, defer, of, throwError } from 'rxjs';

import { EquipmentService } from './equipment.service';
import { MaintenanceListItem, MaintenanceRequest, MaintenanceService } from './maintenance.service';
import { PAGE_SIZE, PendingRequestsState, PendingRequestsStore } from './pending-requests.store';
import { QueueService, QueueSummary } from './queue.service';
import { TechniciansService } from './technicians.service';
import { ToastService } from './toast.service';

const item = (id: number, status = 'submitted'): MaintenanceListItem => ({
  id, ticket_number: `T-${id}`, equipment_id: 1, title: `t${id}`, priority: 'low', status, created_at: '2026-10-14T00:00:00Z',
});
const detail = { id: 7, status: 'triaged' } as MaintenanceRequest;

describe('PendingRequestsStore', () => {
  let maintenance: jasmine.SpyObj<MaintenanceService>;
  let queue: jasmine.SpyObj<QueueService>;
  let toasts: ToastService;
  let store: PendingRequestsStore;
  let latest: PendingRequestsState;

  beforeEach(() => {
    maintenance = jasmine.createSpyObj('MaintenanceService', ['listPage', 'get', 'transition', 'assign', 'reject', 'classify']);
    queue = jasmine.createSpyObj('QueueService', ['summary', 'categories']);
    const technicians = jasmine.createSpyObj('TechniciansService', ['list']);
    const equipment = jasmine.createSpyObj('EquipmentService', ['listAll']);
    maintenance.listPage.and.callFake((query = {}) =>
      of({ items: [item(1, query.status), item(2, query.status)], total: 40 }),
    );
    queue.summary.and.returnValue(of({ pending_total: 6 } as QueueSummary));
    queue.categories.and.returnValue(of([{ code: 'network', name: 'Red' }]));
    technicians.list.and.returnValue(of([]));
    equipment.listAll.and.returnValue(of([]));
    TestBed.configureTestingModule({
      providers: [
        PendingRequestsStore,
        { provide: MaintenanceService, useValue: maintenance },
        { provide: QueueService, useValue: queue },
        { provide: TechniciansService, useValue: technicians },
        { provide: EquipmentService, useValue: equipment },
      ],
    });
    toasts = TestBed.inject(ToastService);
    store = TestBed.inject(PendingRequestsStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('loads one server page per queue column, oldest first, plus metrics and catalog', () => {
    store.load();
    expect(maintenance.listPage).toHaveBeenCalledTimes(3);
    const queries = maintenance.listPage.calls.allArgs().map(([q]) => q!);
    expect(queries.map((q) => q.status)).toEqual(['submitted', 'triaged', 'assigned']);
    expect(queries.every((q) => q.sort === 'created_at' && q.page === 1 && q.size === PAGE_SIZE)).toBeTrue();
    expect(latest.columns.submitted.total).toBe(40);
    expect(latest.summary?.pending_total).toBe(6);
    expect(latest.categories[0].code).toBe('network');
    expect(latest.loading).toBeFalse();
  });

  it('sends the filters to the server and restarts from page 1', () => {
    store.load();
    maintenance.listPage.calls.reset();
    store.setFilters({ search: '  pantalla ', priority: 'high', category: 'network', order: 'priority' });
    const query = maintenance.listPage.calls.first().args[0]!;
    expect(query).toEqual(jasmine.objectContaining({ search: 'pantalla', priority: 'high', category: 'network', sort: '-priority', page: 1 }));
  });

  it('sends the received-between range as day boundaries and does not ask the server for an invalid one', () => {
    store.load();
    maintenance.listPage.calls.reset();
    store.setFilters({ dateFrom: '2026-10-01', dateTo: '2026-10-14' });
    const query = maintenance.listPage.calls.first().args[0]!;
    expect(new Date(query.dateFrom!).getHours()).toBe(0);
    expect(new Date(query.dateTo!).getHours()).toBe(23);
    expect(latest.filterError).toBe('');

    maintenance.listPage.calls.reset();
    store.setFilters({ dateFrom: '2026-10-14', dateTo: '2026-10-01' });
    expect(maintenance.listPage).not.toHaveBeenCalled();
    expect(latest.filterError).toBe('La fecha final no puede ser anterior a la inicial.');
    store.setFilters({ dateTo: '2026-10-20' });
    expect(maintenance.listPage).toHaveBeenCalled();
    expect(latest.filterError).toBe('');
  });

  it('skips the assigned column when only unassigned requests are wanted', () => {
    store.load();
    maintenance.listPage.calls.reset();
    store.setFilters({ unassignedOnly: true });
    expect(maintenance.listPage.calls.allArgs().map(([q]) => q!.status)).toEqual(['submitted', 'triaged']);
    expect(latest.columns.assigned.items).toEqual([]);
  });

  it('appends the next server page and stops when everything is loaded', () => {
    store.load();
    store.loadMore('submitted');
    expect(maintenance.listPage.calls.mostRecent().args[0]!.page).toBe(2);
    expect(latest.columns.submitted.items.length).toBe(4);
    maintenance.listPage.and.returnValue(of({ items: [], total: 4 }));
    maintenance.listPage.calls.reset();
    store.loadMore('submitted');
    store.loadMore('submitted');
    expect(maintenance.listPage.calls.count()).toBeLessThanOrEqual(1);
  });

  it('keeps the metrics null (not zero) when the summary is unavailable', () => {
    queue.summary.and.returnValue(throwError(() => new HttpErrorResponse({ status: 403 })));
    store.load();
    expect(latest.summary).toBeNull();
    expect(latest.summaryLoading).toBeFalse();
  });

  it('reports a failing column without losing the others', () => {
    maintenance.listPage.and.callFake((query = {}) =>
      query.status === 'triaged' ? throwError(() => new HttpErrorResponse({ status: 500 })) : of({ items: [item(1)], total: 1 }),
    );
    store.load();
    expect(latest.columns.triaged.failed).toBeTrue();
    expect(latest.columns.submitted.items.length).toBe(1);
    expect(latest.error).toContain('servidor');
    expect(latest.loading).toBeFalse();
  });

  describe('actions', () => {
    it('rejects with a success toast and refreshes the queue', () => {
      maintenance.reject.and.returnValue(of(detail));
      store.load();
      maintenance.listPage.calls.reset();
      let result: unknown;
      store.reject(7, 'Duplicado').subscribe((r) => (result = r));
      expect(maintenance.reject).toHaveBeenCalledWith(7, 'Duplicado');
      expect(result).toEqual({ ok: true, fieldErrors: {} });
      expect(toasts.toasts()[0].message).toBe('Solicitud rechazada.');
      expect(maintenance.listPage).toHaveBeenCalledTimes(3);
      expect(latest.busy).toBeFalse();
    });

    it('classifies with category, priority and note, then refreshes', () => {
      maintenance.classify.and.returnValue(of(detail));
      store.load();
      maintenance.listPage.calls.reset();
      store.classify(7, { category: 'network', priority: 'high', notes: null }).subscribe();
      expect(maintenance.classify).toHaveBeenCalledWith(7, { category: 'network', priority: 'high', notes: null });
      expect(toasts.toasts()[0].message).toBe('Solicitud clasificada.');
      expect(maintenance.listPage).toHaveBeenCalledTimes(3);
    });

    it('turns a 409 into a readable toast and a 422 into field errors', () => {
      maintenance.assign.and.returnValue(throwError(() => new HttpErrorResponse({
        status: 409, error: { detail: 'cannot assign a ticket to an inactive technician', code: 'conflict' },
      })));
      store.assign(7, 3).subscribe();
      expect(toasts.toasts()[0].message).toBe('No se puede asignar a un técnico inactivo.');

      maintenance.reject.and.returnValue(throwError(() => new HttpErrorResponse({
        status: 422, error: { errors: [{ field: 'reason', message: 'String should have at least 5 characters', type: 'string_too_short' }] },
      })));
      let fieldErrors: Record<string, string> = {};
      store.reject(7, 'abc').subscribe((r) => (fieldErrors = r.fieldErrors));
      expect(fieldErrors['reason']).toBe('Debe tener al menos 5 caracteres.');
      expect(latest.busy).toBeFalse();
    });

    it('ignores a second action while one is in flight (no double submit)', () => {
      const gate = new Subject<MaintenanceRequest>();
      let requests = 0;
      maintenance.reject.and.callFake(() => defer(() => { requests++; return gate; }));
      store.reject(7, 'Duplicado').subscribe();
      expect(latest.busy).toBeTrue();
      let second: unknown;
      store.reject(7, 'Duplicado').subscribe((r) => (second = r));
      expect(requests).toBe(1);
      expect(second).toEqual({ ok: false, fieldErrors: {} });
      gate.next(detail);
      gate.complete();
      expect(latest.busy).toBeFalse();
    });
  });
});
