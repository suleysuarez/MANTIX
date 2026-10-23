import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, forkJoin, of } from 'rxjs';
import { catchError, map, tap } from 'rxjs/operators';

import { apiErrorMessage, apiFieldErrors } from './api-errors';
import { Period } from './dashboard-kpis.service';
import { Equipment, EquipmentService } from './equipment.service';
import {
  MaintenanceListItem,
  MaintenanceQuery,
  MaintenanceRequest,
  MaintenanceService,
} from './maintenance.service';
import { PriorityRef, QueueService, QueueSummary, RequestCategory } from './queue.service';
import { Technician, TechniciansService } from './technicians.service';
import { TicketTransitionService } from './ticket-transitions.service';
import { ToastService } from './toast.service';
import { TransitionData, WorkflowService, WorkflowState } from './workflow.service';
import { queueRangeError } from '../features/pending-requests/pending-ui';
import { dayBoundaryIso } from '../features/reports/report-filters';
import { statusMeta } from '../features/tickets/ticket-ui';

export type QueueOrder = 'newest' | 'priority';

export interface QueueFilters {
  search: string;
  priority: string;
  category: string;
  /** `true`: solo solicitudes sin técnico (las que aún no están en un estado que lo exige). */
  unassignedOnly: boolean;
  order: QueueOrder;
  /** Recibidas desde / hasta, como `yyyy-MM-dd` (vacío: sin límite). */
  dateFrom: string;
  dateTo: string;
}

export interface QueueColumn {
  items: MaintenanceListItem[];
  total: number;
  /** Última página cargada (base 1). */
  page: number;
  loading: boolean;
  failed: boolean;
}

export interface PendingRequestsState {
  filters: QueueFilters;
  /** Mensaje del rango de fechas inválido; con él no se consulta al servidor. */
  filterError: string;
  /** Estados que son columnas (los marca el State Pattern del servidor), en el orden del flujo. */
  statuses: string[];
  /** Todo el flujo: de aquí salen los pasos válidos y lo que pide cada uno. */
  workflow: WorkflowState[];
  columns: Record<string, QueueColumn>;
  period: Period;
  /** `null`: no disponible (falló o sin permiso); la pantalla lo dice en vez de mostrar ceros. */
  summary: QueueSummary | null;
  summaryLoading: boolean;
  categories: RequestCategory[];
  /** Tabla de prioridades del servidor: nombres y tono de las etiquetas salen de aquí. */
  priorities: PriorityRef[];
  technicians: Technician[];
  equipmentById: Map<number, Equipment>;
  loading: boolean;
  error: string;
  selectedId: number | null;
  detail: MaintenanceRequest | null;
  detailLoading: boolean;
  detailError: string;
  /** Hay una acción en curso: bloquea el doble envío. */
  busy: boolean;
}

export interface ActionResult {
  ok: boolean;
  /** Errores 422 por campo, en español, para mostrarlos bajo cada control. */
  fieldErrors: Record<string, string>;
}

/** Resultado de arrastrar una tarjeta; coincide con lo que espera el tablero compartido. */
export type MoveResult = { ok: true } | { ok: false; message: string };

export const PAGE_SIZE = 15;

const SORT: Record<QueueOrder, string> = {
  newest: '-created_at',
  priority: '-priority',
};

export const EMPTY_FILTERS: QueueFilters = {
  search: '',
  priority: '',
  category: '',
  unassignedOnly: false,
  order: 'newest',
  dateFrom: '',
  dateTo: '',
};

const emptyColumn = (): QueueColumn => ({ items: [], total: 0, page: 0, loading: false, failed: false });

const INITIAL: PendingRequestsState = {
  filters: EMPTY_FILTERS,
  filterError: '',
  statuses: [],
  workflow: [],
  columns: {},
  period: '30d',
  summary: null,
  summaryLoading: true,
  categories: [],
  priorities: [],
  technicians: [],
  equipmentById: new Map(),
  loading: true,
  error: '',
  selectedId: null,
  detail: null,
  detailLoading: false,
  detailError: '',
  busy: false,
};

/** Columnas que el filtro «solo sin técnico» deja vacías: las que exigen técnico ya lo tienen. */
export function isColumnHidden(status: string, filters: QueueFilters, workflow: readonly WorkflowState[]): boolean {
  return filters.unassignedOnly && !!workflow.find((state) => state.status === status)?.requires.includes('technician');
}

/** Estados de la bandeja a partir del flujo del servidor. */
export const queueStatuses = (workflow: readonly WorkflowState[]): string[] =>
  workflow.filter((state) => state.in_queue).sort((a, b) => a.order - b.order).map((state) => state.status);

/** Observer pattern store de la bandeja de solicitudes pendientes. */
@Injectable({ providedIn: 'root' })
export class PendingRequestsStore {
  private readonly maintenance = inject(MaintenanceService);
  private readonly queue = inject(QueueService);
  private readonly technicians = inject(TechniciansService);
  private readonly equipment = inject(EquipmentService);
  private readonly workflowApi = inject(WorkflowService);
  private readonly transitions = inject(TicketTransitionService);
  private readonly toasts = inject(ToastService);
  private readonly subject = new BehaviorSubject<PendingRequestsState>(INITIAL);

  readonly state$: Observable<PendingRequestsState> = this.subject.asObservable();

  private get value(): PendingRequestsState {
    return this.subject.value;
  }

  private patch(changes: Partial<PendingRequestsState>): void {
    this.subject.next({ ...this.value, ...changes });
  }

  load(): void {
    this.patch({ loading: true, error: '' });
    forkJoin({
      workflow: this.workflowApi.states().pipe(catchError(() => of(null))),
      categories: this.queue.categories().pipe(catchError(() => of([] as RequestCategory[]))),
      priorities: this.queue.priorities().pipe(catchError(() => of([] as PriorityRef[]))),
      technicians: this.technicians.list().pipe(catchError(() => of([] as Technician[]))),
      equipment: this.equipment.listAll().pipe(catchError(() => of([] as Equipment[]))),
    }).subscribe(({ workflow, categories, priorities, technicians, equipment }) => {
      if (workflow === null) {
        this.workflowApi.reset();
      }
      const states = workflow ?? [];
      const statuses = queueStatuses(states);
      this.patch({
        workflow: states,
        statuses,
        columns: Object.fromEntries(statuses.map((status) => [status, emptyColumn()])),
        categories,
        priorities,
        technicians,
        equipmentById: new Map(equipment.map((item) => [item.id, item])),
        error: workflow === null ? 'No se pudo cargar el flujo de estados de las solicitudes.' : '',
        loading: workflow !== null,
      });
      this.reloadColumns();
      this.loadSummary();
    });
  }

  setFilters(changes: Partial<QueueFilters>): void {
    const filters = { ...this.value.filters, ...changes };
    const filterError = queueRangeError(filters.dateFrom, filters.dateTo);
    this.patch({ filters, filterError });
    if (!filterError) {
      this.reloadColumns();
    }
  }

  clearFilters(): void {
    this.setFilters(EMPTY_FILTERS);
  }

  setPeriod(period: Period): void {
    this.patch({ period });
    this.loadSummary();
  }

  loadMore(status: string): void {
    const column = this.value.columns[status];
    if (!column || column.loading || column.items.length >= column.total) {
      return;
    }
    this.fetchColumn(status, column.page + 1, true);
  }

  select(id: number | null): void {
    this.patch({ selectedId: id, detail: null, detailError: '', detailLoading: id !== null });
    if (id === null) {
      return;
    }
    this.maintenance.get(id).subscribe({
      next: (detail) => {
        if (this.value.selectedId === id) {
          this.patch({ detail, detailLoading: false });
        }
      },
      error: (error) => {
        if (this.value.selectedId === id) {
          this.patch({ detailLoading: false, detailError: apiErrorMessage(error, 'No se pudo cargar el detalle.') });
        }
      },
    });
  }

  /** Clasifica la solicitud: categoría y prioridad del catálogo, y pasa de enviada a clasificada. */
  classify(id: number, body: { category: string; priority: string; notes: string | null }): Observable<ActionResult> {
    return this.run(this.maintenance.classify(id, body), id, 'Solicitud clasificada.');
  }

  assign(id: number, technicianId: number): Observable<ActionResult> {
    return this.run(this.maintenance.assign(id, technicianId, null), id, 'Técnico asignado.');
  }

  reject(id: number, reason: string): Observable<ActionResult> {
    return this.run(this.maintenance.reject(id, reason), id, 'Solicitud rechazada.');
  }

  /**
   * Cambia el estado de una tarjeta arrastrada. El servidor valida el paso (State Pattern) y deja el
   * historial de estados y la auditoría; aquí, si lo acepta, la tarjeta se queda en su nueva columna
   * mientras se recarga, y si lo rechaza el tablero la devuelve a su sitio con el mensaje.
   */
  move(item: MaintenanceListItem, from: string, to: string, data: TransitionData): Observable<MoveResult> {
    return this.transitions.move(item.id, from, to, data).pipe(
      map((): MoveResult => {
        this.placeLocally(item, from, to);
        this.toasts.success(`${item.ticket_number} pasó a «${statusMeta(to).label}».`);
        if (this.value.selectedId === item.id) {
          this.select(item.id);
        }
        this.reloadColumns();
        this.loadSummary();
        return { ok: true };
      }),
      catchError((error) => of<MoveResult>({ ok: false, message: apiErrorMessage(error, 'No se pudo cambiar el estado de la solicitud.') })),
    );
  }

  private run(call: Observable<MaintenanceRequest>, id: number, success: string): Observable<ActionResult> {
    if (this.value.busy) {
      return of({ ok: false, fieldErrors: {} });
    }
    this.patch({ busy: true });
    return call.pipe(
      tap(() => this.toasts.success(success)),
      map((detail) => {
        // Rechazada o asignada: sale de la bandeja o cambia de columna; el panel muestra el nuevo estado.
        this.patch({ busy: false, detail: this.value.selectedId === id ? detail : this.value.detail });
        this.reloadColumns();
        this.loadSummary();
        return { ok: true, fieldErrors: {} } as ActionResult;
      }),
      catchError((error) => {
        this.patch({ busy: false });
        this.toasts.error(apiErrorMessage(error, 'No se pudo completar la acción.'));
        return of({ ok: false, fieldErrors: apiFieldErrors(error) });
      }),
    );
  }

  /** Pasa la tarjeta de columna en el estado local, para que no parpadee mientras se recargan las columnas. */
  private placeLocally(item: MaintenanceListItem, from: string, to: string): void {
    const { columns } = this.value;
    const source = columns[from];
    const target = columns[to];
    if (!source || !target) {
      return;
    }
    this.patch({
      columns: {
        ...columns,
        [from]: { ...source, items: source.items.filter((i) => i.id !== item.id), total: Math.max(source.total - 1, 0) },
        [to]: { ...target, items: [...target.items, { ...item, status: to }], total: target.total + 1 },
      },
    });
  }

  private query(status: string, page: number): MaintenanceQuery {
    const { search, priority, category, order, dateFrom, dateTo } = this.value.filters;
    return {
      status,
      dateFrom: dayBoundaryIso(dateFrom, false) ?? undefined,
      dateTo: dayBoundaryIso(dateTo, true) ?? undefined,
      search: search.trim() || undefined,
      priority: priority || undefined,
      category: category || undefined,
      sort: SORT[order],
      page,
      size: PAGE_SIZE,
    };
  }

  private reloadColumns(): void {
    const hasColumns = this.value.statuses.length > 0;
    this.patch({ loading: hasColumns, error: hasColumns ? '' : this.value.error });
    for (const status of this.value.statuses) {
      if (isColumnHidden(status, this.value.filters, this.value.workflow)) {
        this.setColumn(status, emptyColumn());
      } else {
        this.fetchColumn(status, 1, false);
      }
    }
    this.settle();
  }

  private fetchColumn(status: string, page: number, append: boolean): void {
    const previous = this.value.columns[status] ?? emptyColumn();
    this.setColumn(status, { ...previous, loading: true, failed: false });
    this.maintenance.listPage(this.query(status, page)).subscribe({
      next: ({ items, total }) => {
        this.setColumn(status, {
          items: append ? [...previous.items, ...items] : items,
          total,
          page,
          loading: false,
          failed: false,
        });
        this.settle();
      },
      error: (error) => {
        this.setColumn(status, { ...previous, loading: false, failed: true });
        this.patch({ error: apiErrorMessage(error, 'No se pudo cargar la bandeja.') });
        this.settle();
      },
    });
  }

  private setColumn(status: string, column: QueueColumn): void {
    this.patch({ columns: { ...this.value.columns, [status]: column } });
  }

  private settle(): void {
    if (this.value.statuses.every((status) => !this.value.columns[status]?.loading)) {
      this.patch({ loading: false });
    }
  }

  private loadSummary(): void {
    this.patch({ summaryLoading: true });
    const period = this.value.period;
    this.queue.summary(period).subscribe({
      next: (summary) => {
        if (this.value.period === period) {
          this.patch({ summary, summaryLoading: false });
        }
      },
      error: () => this.patch({ summary: null, summaryLoading: false }),
    });
  }
}
