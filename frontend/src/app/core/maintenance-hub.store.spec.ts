import { HttpErrorResponse } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';
import { Subject, defer, of, throwError } from 'rxjs';

import { dayKey, visibleRange } from './calendar-utils';
import { EquipmentService } from './equipment.service';
import { MaintenanceHubState, MaintenanceHubStore } from './maintenance-hub.store';
import { CalendarEvent, MaintenanceOverview, MaintenanceOverviewService } from './maintenance-overview.service';
import { MaintenanceSchedule, SchedulesService } from './schedules.service';
import { TechniciansService } from './technicians.service';
import { ToastService } from './toast.service';

const plan = (id = 1): MaintenanceSchedule => ({
  id, equipment: { id: 1, asset_tag: 'LT-1', brand: 'Dell', model: 'X' }, technician: null, title: 'Limpieza',
  description: null, interval_days: 30, remind_days_before: 3, next_due_at: '2026-12-01T09:00:00Z',
  last_reminded_at: null, is_active: true, created_at: '2026-10-01T00:00:00Z',
});
const event = (kind: CalendarEvent['kind'], at = '2026-10-20T09:00:00Z'): CalendarEvent => ({
  kind, schedule_id: 1, title: 't', equipment_id: 1, asset_tag: 'LT-1', technician: null, at, completed_at: null, on_time: null,
});

describe('MaintenanceHubStore', () => {
  let overview: jasmine.SpyObj<MaintenanceOverviewService>;
  let schedules: jasmine.SpyObj<SchedulesService>;
  let toasts: ToastService;
  let store: MaintenanceHubStore;
  let latest: MaintenanceHubState;

  beforeEach(() => {
    overview = jasmine.createSpyObj('MaintenanceOverviewService', ['overview', 'calendar']);
    schedules = jasmine.createSpyObj('SchedulesService', ['listPage', 'get', 'history', 'create', 'update', 'complete']);
    const technicians = jasmine.createSpyObj('TechniciansService', ['list']);
    const equipment = jasmine.createSpyObj('EquipmentService', ['listAll']);
    overview.overview.and.returnValue(of({ period: '30d' } as MaintenanceOverview));
    overview.calendar.and.returnValue(of({ generated_at: '', start: '', end: '', truncated: false, events: [event('planned'), event('overdue'), event('done')] }));
    schedules.listPage.and.returnValue(of({ items: [plan()], total: 31 }));
    schedules.get.and.returnValue(of(plan()));
    schedules.history.and.returnValue(of({ runs: [], reschedules: [] }));
    technicians.list.and.returnValue(of([]));
    equipment.listAll.and.returnValue(of([]));
    TestBed.configureTestingModule({
      providers: [
        MaintenanceHubStore,
        { provide: MaintenanceOverviewService, useValue: overview },
        { provide: SchedulesService, useValue: schedules },
        { provide: TechniciansService, useValue: technicians },
        { provide: EquipmentService, useValue: equipment },
      ],
    });
    toasts = TestBed.inject(ToastService);
    store = TestBed.inject(MaintenanceHubStore);
    store.state$.subscribe((state) => (latest = state));
  });

  it('loads metrics, the visible month and the next-30-days timeline without done services', () => {
    store.load();
    expect(overview.overview).toHaveBeenCalledWith('30d');
    expect(overview.calendar).toHaveBeenCalledTimes(2); // mes visible + línea de tiempo
    expect(latest.events.length).toBe(3);
    expect(latest.timeline?.map((e) => e.kind)).toEqual(['planned', 'overdue']);
    expect(latest.calendarLoading).toBeFalse();
  });

  it('asks the server for exactly the visible range and moves it month by month', () => {
    store.load();
    const [start, end] = overview.calendar.calls.first().args;
    const expected = visibleRange(latest.anchor, 'month');
    expect(dayKey(start)).toBe(dayKey(expected.start));
    expect(dayKey(end)).toBe(dayKey(expected.end));
    const month = latest.anchor.getMonth();
    store.navigate(1);
    expect(latest.anchor.getMonth()).toBe((month + 1) % 12);
    store.setMode('week');
    const [weekStart, weekEnd] = overview.calendar.calls.mostRecent().args;
    expect((weekEnd.getTime() - weekStart.getTime()) / 86_400_000).toBe(7);
  });

  it('shows an error without losing the previous events when the calendar fails', () => {
    store.load();
    overview.calendar.and.returnValue(throwError(() => new HttpErrorResponse({ status: 422 })));
    store.navigate(1);
    expect(latest.calendarError).not.toBe('');
    expect(latest.events.length).toBe(3);
    expect(latest.calendarLoading).toBeFalse();
  });

  it('toggles the selected day', () => {
    store.selectDay('2026-10-20');
    expect(latest.selectedDay).toBe('2026-10-20');
    store.selectDay('2026-10-20');
    expect(latest.selectedDay).toBeNull();
  });

  it('keeps null metrics (not zeros) when the overview is unavailable', () => {
    overview.overview.and.returnValue(throwError(() => new HttpErrorResponse({ status: 403 })));
    store.load();
    expect(latest.overview).toBeNull();
    expect(latest.overviewLoading).toBeFalse();
  });

  describe('list view', () => {
    it('loads the first server page only when the view is opened', () => {
      store.load();
      expect(schedules.listPage).not.toHaveBeenCalled();
      store.setView('list');
      expect(schedules.listPage).toHaveBeenCalledTimes(1);
      expect(latest.listTotal).toBe(31);
    });

    it('sends filters and sort to the server and restarts from page 1', () => {
      store.load();
      store.setView('list');
      store.setListPage(2);
      expect(schedules.listPage.calls.mostRecent().args[0]).toEqual(jasmine.objectContaining({ page: 2, size: 15 }));
      store.setFilters({ search: '  limpieza ', technicianId: 4, status: 'overdue', sort: '-next_due_at' });
      expect(schedules.listPage.calls.mostRecent().args[0]).toEqual(
        jasmine.objectContaining({ search: 'limpieza', technicianId: 4, status: 'overdue', sort: '-next_due_at', page: 1 }),
      );
    });

    it('reports a list error', () => {
      store.load();
      schedules.listPage.and.returnValue(throwError(() => new HttpErrorResponse({ status: 500 })));
      store.setView('list');
      expect(latest.listError).toContain('servidor');
    });
  });

  describe('actions', () => {
    it('creates a plan, shows a toast and refreshes calendar and metrics', () => {
      schedules.create.and.returnValue(of(plan(9)));
      store.load();
      overview.calendar.calls.reset();
      let result: unknown;
      store.create({ equipment_id: 1, title: 'x', description: null, interval_days: 30, remind_days_before: 3, first_due_at: '2026-12-01T09:00:00Z' })
        .subscribe((r) => (result = r));
      expect(result).toEqual({ ok: true, fieldErrors: {} });
      expect(toasts.toasts()[0].message).toBe('Mantenimiento programado.');
      expect(overview.calendar).toHaveBeenCalledTimes(2);
      expect(latest.busy).toBeFalse();
    });

    it('turns backend errors into Spanish toasts and field errors', () => {
      schedules.create.and.returnValue(throwError(() => new HttpErrorResponse({
        status: 422, error: { code: 'unprocessable', detail: 'a service cannot be scheduled in the past' },
      })));
      store.create({ equipment_id: 1, title: 'x', description: null, interval_days: 30, remind_days_before: 3, first_due_at: '2020-01-01T00:00:00Z' }).subscribe();
      expect(toasts.toasts()[0].message).toBe('Revisa los campos marcados.');

      schedules.update.and.returnValue(throwError(() => new HttpErrorResponse({
        status: 422, error: { errors: [{ field: 'estimated_hours', message: 'x', type: 'greater_than_equal' }] },
      })));
      let fields: Record<string, string> = {};
      store.update(1, { estimated_hours: -1 }).subscribe((r) => (fields = r.fieldErrors));
      expect(fields['estimated_hours']).toBe('El valor es demasiado bajo.');
    });

    it('ignores a second action while one is running', () => {
      const gate = new Subject<MaintenanceSchedule>();
      let calls = 0;
      schedules.complete.and.callFake(() => defer(() => { calls++; return gate; }));
      store.complete(1, 1.5).subscribe();
      expect(latest.busy).toBeTrue();
      let second: unknown;
      store.complete(1, 1.5).subscribe((r) => (second = r));
      expect(calls).toBe(1);
      expect(second).toEqual({ ok: false, fieldErrors: {} });
      gate.next(plan());
      gate.complete();
      expect(latest.busy).toBeFalse();
    });

    it('reloads the open plan after completing it', () => {
      schedules.complete.and.returnValue(of(plan()));
      store.selectPlan(1);
      schedules.get.calls.reset();
      store.complete(1, null).subscribe();
      expect(schedules.get).toHaveBeenCalledWith(1);
    });
  });

  it('exports every plan that matches the current filters, not just the page', () => {
    store.setFilters({ status: 'overdue' });
    schedules.listPage.calls.reset();
    store.exportAll().subscribe();
    expect(schedules.listPage.calls.mostRecent().args[0]).toEqual(jasmine.objectContaining({ status: 'overdue', size: 500, page: 1 }));
  });
});
