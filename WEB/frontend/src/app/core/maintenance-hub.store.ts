import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, forkJoin, of } from 'rxjs';
import { catchError, map, tap } from 'rxjs/operators';

import { CalendarMode, addDays, startOfDay, shift, visibleRange } from './calendar-utils';
import { apiErrorMessage, apiFieldErrors } from './api-errors';
import { Period } from './dashboard-kpis.service';
import { Equipment, EquipmentService } from './equipment.service';
import {
  CalendarEvent,
  MaintenanceOverview,
  MaintenanceOverviewService,
} from './maintenance-overview.service';
import { ActionResult } from './pending-requests.store';
import { dateRangeError } from '../shared/date-range';
import { dayBoundaryIso, parseDay } from '../features/reports/report-filters';
import {
  MaintenanceSchedule,
  ScheduleHistory,
  SchedulePayload,
  ScheduleQuery,
  ScheduleStatusFilter,
  ScheduleUpdatePayload,
  SchedulesService,
} from './schedules.service';
import { PermissionsService } from './permissions.service';
import { Technician, TechniciansService } from './technicians.service';
import { ToastService } from './toast.service';

export type HubView = 'calendar' | 'list';

export interface ListFilters {
  search: string;
  technicianId: number | null;
  status: ScheduleStatusFilter;
  /** `next_due_at` o `-next_due_at`, `title`, `-created_at`… */
  sort: string;
}

/** Rango de fechas de los servicios (`yyyy-MM-dd`, vacío = sin límite). */
export interface DateRangeValue {
  from: string;
  to: string;
}

export const NO_RANGE: DateRangeValue = { from: '', to: '' };

export const LIST_PAGE_SIZE = 15;
export const TIMELINE_DAYS = 30;

export interface MaintenanceHubState {
  view: HubView;
  mode: CalendarMode;
  /** Día ancla del calendario (cualquier día del mes o de la semana visibles). */
  anchor: Date;
  selectedDay: string | null;
  period: Period;
  /** Rango que filtra el calendario (marcadores y conteos) y la lista; puede ser futuro. */
  range: DateRangeValue;
  /** Mensaje del rango inválido; con él no se consulta al servidor. */
  rangeError: string;
  overview: MaintenanceOverview | null;
  overviewLoading: boolean;
  events: CalendarEvent[];
  truncated: boolean;
  calendarLoading: boolean;
  calendarError: string;
  /** Próximos 30 días (planeados y vencidos), para la línea de tiempo. */
  timeline: CalendarEvent[] | null;
  list: MaintenanceSchedule[];
  listTotal: number;
  listPage: number;
  listLoading: boolean;
  listError: string;
  filters: ListFilters;
  technicians: Technician[];
  equipment: Equipment[];
  selectedId: number | null;
  plan: MaintenanceSchedule | null;
  history: ScheduleHistory | null;
  detailLoading: boolean;
  detailError: string;
  busy: boolean;
}

export const EMPTY_LIST_FILTERS: ListFilters = { search: '', technicianId: null, status: '', sort: 'next_due_at' };

const INITIAL: MaintenanceHubState = {
  view: 'calendar',
  mode: 'month',
  anchor: new Date(),
  selectedDay: null,
  period: '30d',
  range: NO_RANGE,
  rangeError: '',
  overview: null,
  overviewLoading: true,
  events: [],
  truncated: false,
  calendarLoading: true,
  calendarError: '',
  timeline: null,
  list: [],
  listTotal: 0,
  listPage: 1,
  listLoading: false,
  listError: '',
  filters: EMPTY_LIST_FILTERS,
  technicians: [],
  equipment: [],
  selectedId: null,
  plan: null,
  history: null,
  detailLoading: false,
  detailError: '',
  busy: false,
};

/** Observer pattern store del módulo de Mantenimiento: calendario, línea de tiempo, lista y planes. */
@Injectable({ providedIn: 'root' })
export class MaintenanceHubStore {
  private readonly overviewApi = inject(MaintenanceOverviewService);
  private readonly schedules = inject(SchedulesService);
  private readonly techniciansApi = inject(TechniciansService);
  private readonly permissions = inject(PermissionsService);
  private readonly equipmentApi = inject(EquipmentService);
  private readonly toasts = inject(ToastService);
  private readonly subject = new BehaviorSubject<MaintenanceHubState>({ ...INITIAL, anchor: startOfDay(new Date()) });

  readonly state$: Observable<MaintenanceHubState> = this.subject.asObservable();

  private get value(): MaintenanceHubState {
    return this.subject.value;
  }

  private patch(changes: Partial<MaintenanceHubState>): void {
    this.subject.next({ ...this.value, ...changes });
  }

  load(): void {
    forkJoin({
      // Quien no puede ver a los técnicos no los pide (el servidor respondería 403).
      technicians: this.permissions.has('tecnicos:ver') ? this.techniciansApi.list().pipe(catchError(() => of([] as Technician[]))) : of([] as Technician[]),
      equipment: this.equipmentApi.listAll().pipe(catchError(() => of([] as Equipment[]))),
    }).subscribe((lookups) => this.patch(lookups));
    this.refresh();
  }

  setView(view: HubView): void {
    this.patch({ view });
    if (view === 'list' && this.value.list.length === 0 && !this.value.listLoading) {
      this.loadList(1);
    }
  }

  setMode(mode: CalendarMode): void {
    this.patch({ mode, selectedDay: null });
    this.loadCalendar();
  }

  navigate(direction: -1 | 1): void {
    this.patch({ anchor: shift(this.value.anchor, this.value.mode, direction), selectedDay: null });
    this.loadCalendar();
  }

  goToday(): void {
    this.patch({ anchor: startOfDay(new Date()), selectedDay: null });
    this.loadCalendar();
  }

  selectDay(key: string | null): void {
    this.patch({ selectedDay: this.value.selectedDay === key ? null : key });
  }

  setPeriod(period: Period): void {
    this.patch({ period });
    this.loadOverview();
  }

  /**
   * Filtra por fechas. El calendario se mueve al rango (a la semana si cabe en una, si no al mes de la
   * fecha inicial) y la lista pide solo esos servicios. Un rango inválido solo muestra su error.
   */
  setRange(range: DateRangeValue): void {
    const rangeError = dateRangeError(range.from, range.to, new Date(), true);
    if (rangeError) {
      this.patch({ rangeError });
      return;
    }
    const start = parseDay(range.from) ?? parseDay(range.to);
    const end = parseDay(range.to);
    const days = start && end ? Math.round((end.getTime() - start.getTime()) / 86_400_000) + 1 : null;
    this.patch({
      range,
      rangeError: '',
      selectedDay: null,
      ...(start ? { anchor: startOfDay(start), mode: days !== null && days <= 7 ? ('week' as const) : ('month' as const) } : {}),
    });
    this.loadCalendar();
    if (this.value.view === 'list' || this.value.list.length > 0) {
      this.loadList(1);
    }
  }

  setFilters(changes: Partial<ListFilters>): void {
    this.patch({ filters: { ...this.value.filters, ...changes } });
    this.loadList(1);
  }

  clearFilters(): void {
    this.setRange(NO_RANGE);
    this.setFilters(EMPTY_LIST_FILTERS);
  }

  setListPage(page: number): void {
    if (page >= 1 && !this.value.listLoading) {
      this.loadList(page);
    }
  }

  selectPlan(id: number | null): void {
    this.patch({ selectedId: id, plan: null, history: null, detailError: '', detailLoading: id !== null });
    if (id !== null) {
      this.loadDetail(id);
    }
  }

  create(payload: SchedulePayload): Observable<ActionResult> {
    return this.run(this.schedules.create(payload), 'Mantenimiento programado.', (plan) => plan.id);
  }

  update(id: number, payload: ScheduleUpdatePayload, success = 'Plan actualizado.'): Observable<ActionResult> {
    return this.run(this.schedules.update(id, payload), success, () => id);
  }

  complete(id: number, actualHours: number | null): Observable<ActionResult> {
    return this.run(this.schedules.complete(id, actualHours), 'Servicio registrado como hecho.', () => id);
  }

  /** Hasta 500 planes con los filtros actuales (sin paginar), para exportar. */
  exportAll(): Observable<MaintenanceSchedule[]> {
    return this.schedules.listPage({ ...this.query(1), size: 500 }).pipe(map((result) => result.items));
  }

  private run(
    call: Observable<MaintenanceSchedule>,
    success: string,
    detailId: (plan: MaintenanceSchedule) => number,
  ): Observable<ActionResult> {
    if (this.value.busy) {
      return of({ ok: false, fieldErrors: {} });
    }
    this.patch({ busy: true });
    return call.pipe(
      tap(() => this.toasts.success(success)),
      map((plan) => {
        this.patch({ busy: false });
        this.refresh();
        if (this.value.selectedId !== null && this.value.selectedId === detailId(plan)) {
          this.loadDetail(this.value.selectedId);
        }
        return { ok: true, fieldErrors: {} } as ActionResult;
      }),
      catchError((error) => {
        this.patch({ busy: false });
        this.toasts.error(apiErrorMessage(error, 'No se pudo completar la acción.'));
        return of({ ok: false, fieldErrors: apiFieldErrors(error) });
      }),
    );
  }

  private refresh(): void {
    this.loadOverview();
    this.loadCalendar();
    this.loadTimeline();
    if (this.value.view === 'list' || this.value.list.length > 0) {
      this.loadList(this.value.listPage);
    }
  }

  private loadOverview(): void {
    this.patch({ overviewLoading: true });
    const period = this.value.period;
    this.overviewApi.overview(period).subscribe({
      next: (overview) => {
        if (this.value.period === period) {
          this.patch({ overview, overviewLoading: false });
        }
      },
      error: () => this.patch({ overview: null, overviewLoading: false }),
    });
  }

  private loadCalendar(): void {
    this.patch({ calendarLoading: true, calendarError: '' });
    const { anchor, mode } = this.value;
    const { start, end } = visibleRange(anchor, mode);
    this.overviewApi.calendar(start, end).subscribe({
      next: ({ events, truncated }) => {
        if (this.value.anchor === anchor && this.value.mode === mode) {
          this.patch({ events, truncated, calendarLoading: false });
        }
      },
      error: (error) =>
        this.patch({ calendarLoading: false, calendarError: apiErrorMessage(error, 'No se pudo cargar el calendario.') }),
    });
  }

  private loadTimeline(): void {
    const today = startOfDay(new Date());
    this.overviewApi.calendar(addDays(today, -30), addDays(today, TIMELINE_DAYS)).subscribe({
      next: ({ events }) =>
        this.patch({ timeline: events.filter((event) => event.kind !== 'done') }),
      error: () => this.patch({ timeline: null }),
    });
  }

  private query(page: number): ScheduleQuery {
    const { search, technicianId, status, sort } = this.value.filters;
    const { from, to } = this.value.range;
    return {
      search: search.trim() || undefined,
      technicianId,
      status,
      dueFrom: dayBoundaryIso(from, false) ?? undefined,
      dueTo: dayBoundaryIso(to, true) ?? undefined,
      sort,
      page,
      size: LIST_PAGE_SIZE,
    };
  }

  private loadList(page: number): void {
    this.patch({ listLoading: true, listError: '' });
    this.schedules.listPage(this.query(page)).subscribe({
      next: ({ items, total }) => this.patch({ list: items, listTotal: total, listPage: page, listLoading: false }),
      error: (error) =>
        this.patch({ listLoading: false, listError: apiErrorMessage(error, 'No se pudo cargar la lista de planes.') }),
    });
  }

  private loadDetail(id: number): void {
    forkJoin({ plan: this.schedules.get(id), history: this.schedules.history(id) }).subscribe({
      next: ({ plan, history }) => {
        if (this.value.selectedId === id) {
          this.patch({ plan, history, detailLoading: false });
        }
      },
      error: (error) => {
        if (this.value.selectedId === id) {
          this.patch({ detailLoading: false, detailError: apiErrorMessage(error, 'No se pudo cargar el plan.') });
        }
      },
    });
  }
}
