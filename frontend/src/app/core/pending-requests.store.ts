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
import { QueueService, QueueSummary, RequestCategory } from './queue.service';
import { Technician, TechniciansService } from './technicians.service';
import { ToastService } from './toast.service';

/** Columnas de la bandeja: lo que aún espera trabajo, en el orden del flujo. */
export const QUEUE_STATUSES = ['submitted', 'triaged', 'assigned'] as const;
export type QueueStatus = (typeof QUEUE_STATUSES)[number];

export type QueueOrder = 'oldest' | 'newest' | 'priority';

export interface QueueFilters {
  search: string;
  priority: string;
  category: string;
  /** `true`: solo solicitudes sin técnico (enviadas y clasificadas). */
  unassignedOnly: boolean;
  order: QueueOrder;
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
  columns: Record<QueueStatus, QueueColumn>;
  period: Period;
  /** `null`: no disponible (falló o sin permiso); la pantalla lo dice en vez de mostrar ceros. */
  summary: QueueSummary | null;
  summaryLoading: boolean;
  categories: RequestCategory[];
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

export const PAGE_SIZE = 15;

const SORT: Record<QueueOrder, string> = {
  oldest: 'created_at',
  newest: '-created_at',
  priority: '-priority',
};

export const EMPTY_FILTERS: QueueFilters = {
  search: '',
  priority: '',
  category: '',
  unassignedOnly: false,
  order: 'oldest',
};

const emptyColumn = (): QueueColumn => ({ items: [], total: 0, page: 0, loading: false, failed: false });

const INITIAL: PendingRequestsState = {
  filters: EMPTY_FILTERS,
  columns: { submitted: emptyColumn(), triaged: emptyColumn(), assigned: emptyColumn() },
  period: '30d',
  summary: null,
  summaryLoading: true,
  categories: [],
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

/** Columnas que el filtro «solo sin asignar» deja vacías: las asignadas ya tienen técnico. */
export function isColumnHidden(status: QueueStatus, filters: QueueFilters): boolean {
  return filters.unassignedOnly && status === 'assigned';
}

/** Observer pattern store de la bandeja de solicitudes pendientes. */
@Injectable({ providedIn: 'root' })
export class PendingRequestsStore {
  private readonly maintenance = inject(MaintenanceService);
  private readonly queue = inject(QueueService);
  private readonly technicians = inject(TechniciansService);
  private readonly equipment = inject(EquipmentService);
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
      categories: this.queue.categories().pipe(catchError(() => of([] as RequestCategory[]))),
      technicians: this.technicians.list().pipe(catchError(() => of([] as Technician[]))),
      equipment: this.equipment.listAll().pipe(catchError(() => of([] as Equipment[]))),
    }).subscribe(({ categories, technicians, equipment }) => {
      this.patch({
        categories,
        technicians,
        equipmentById: new Map(equipment.map((item) => [item.id, item])),
      });
      this.reloadColumns();
      this.loadSummary();
    });
  }

  setFilters(changes: Partial<QueueFilters>): void {
    this.patch({ filters: { ...this.value.filters, ...changes } });
    this.reloadColumns();
  }

  clearFilters(): void {
    this.setFilters(EMPTY_FILTERS);
  }

  setPeriod(period: Period): void {
    this.patch({ period });
    this.loadSummary();
  }

  loadMore(status: QueueStatus): void {
    const column = this.value.columns[status];
    if (column.loading || column.items.length >= column.total) {
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

  /** Clasifica la solicitud (enviada → clasificada). */
  triage(id: number): Observable<ActionResult> {
    return this.run(this.maintenance.transition(id, 'triaged', null, null), id, 'Solicitud clasificada.');
  }

  assign(id: number, technicianId: number): Observable<ActionResult> {
    return this.run(this.maintenance.assign(id, technicianId, null), id, 'Técnico asignado.');
  }

  reject(id: number, reason: string): Observable<ActionResult> {
    return this.run(this.maintenance.reject(id, reason), id, 'Solicitud rechazada.');
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

  private query(status: QueueStatus, page: number): MaintenanceQuery {
    const { search, priority, category, order } = this.value.filters;
    return {
      status,
      search: search.trim() || undefined,
      priority: priority || undefined,
      category: category || undefined,
      sort: SORT[order],
      page,
      size: PAGE_SIZE,
    };
  }

  private reloadColumns(): void {
    this.patch({ loading: true, error: '' });
    for (const status of QUEUE_STATUSES) {
      if (isColumnHidden(status, this.value.filters)) {
        this.setColumn(status, emptyColumn());
      } else {
        this.fetchColumn(status, 1, false);
      }
    }
  }

  private fetchColumn(status: QueueStatus, page: number, append: boolean): void {
    const previous = this.value.columns[status];
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

  private setColumn(status: QueueStatus, column: QueueColumn): void {
    this.patch({ columns: { ...this.value.columns, [status]: column } });
  }

  private settle(): void {
    if (QUEUE_STATUSES.every((status) => !this.value.columns[status].loading)) {
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
