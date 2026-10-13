import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, Subject, forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';

import { Equipment, EquipmentService } from './equipment.service';
import { httpErrorMessage } from './http-error';
import {
  MaintenanceListItem,
  MaintenanceQuery,
  MaintenanceRequestPayload,
  MaintenanceService,
} from './maintenance.service';

export type TicketOrder = 'newest' | 'oldest' | 'priority';

export interface TicketFilters {
  search: string;
  status: string;
  priority: string;
  /** Fechas `YYYY-MM-DD` (día local); vacío = sin límite. */
  dateFrom: string;
  dateTo: string;
  order: TicketOrder;
}

export interface TicketsState {
  /** Página actual, con los filtros aplicados. */
  items: MaintenanceListItem[];
  /** Hasta 500 tickets sin filtrar: alimentan los contadores y el aviso de prioridad. */
  all: MaintenanceListItem[];
  equipment: Equipment[];
  filters: TicketFilters;
  loading: boolean;
  saving: boolean;
  error: string;
  /** Error de validación de los filtros (p. ej. un rango de fechas imposible). */
  filterError: string;
  page: number;
  pageSize: number;
  hasNext: boolean;
}

export const EMPTY_FILTERS: TicketFilters = {
  search: '',
  status: '',
  priority: '',
  dateFrom: '',
  dateTo: '',
  order: 'newest',
};

const INITIAL_STATE: TicketsState = {
  items: [],
  all: [],
  equipment: [],
  filters: EMPTY_FILTERS,
  loading: true,
  saving: false,
  error: '',
  filterError: '',
  page: 0,
  pageSize: 20,
  hasNext: false,
};

const SORT: Record<TicketOrder, string> = {
  newest: '-created_at',
  oldest: 'created_at',
  priority: '-priority',
};


/** Inicio o fin del día local (`YYYY-MM-DD`) como ISO, para filtrar por `created_at`. */
export function dayBoundaryIso(date: string, end: boolean): string {
  const [year, month, day] = date.split('-').map(Number);
  const boundary = end
    ? new Date(year, month - 1, day, 23, 59, 59, 999)
    : new Date(year, month - 1, day, 0, 0, 0, 0);
  return boundary.toISOString();
}

/** Fecha local de hoy como `YYYY-MM-DD`. */
export function todayLocal(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/** Mensaje de error si los filtros son imposibles (rango invertido o fechas futuras); si no, `''`. */
export function validateFilters(filters: TicketFilters): string {
  const { dateFrom, dateTo } = filters;
  const today = todayLocal();
  if ((dateFrom && dateFrom > today) || (dateTo && dateTo > today)) {
    return 'Las fechas del rango no pueden ser futuras: los tickets ya existen.';
  }
  if (dateFrom && dateTo && dateFrom > dateTo) {
    return 'La fecha "desde" no puede ser posterior a la fecha "hasta".';
  }
  return '';
}

const LOAD_ERROR = 'No se pudieron cargar los tickets.';

/** Observer pattern store de la pantalla de tickets: filtros, paginación, métricas y alta. */
@Injectable({ providedIn: 'root' })
export class TicketsStore {
  private readonly api = inject(MaintenanceService);
  private readonly equipmentApi = inject(EquipmentService);
  private readonly subject = new BehaviorSubject<TicketsState>(INITIAL_STATE);
  private readonly createdSource = new Subject<number>();

  readonly state$: Observable<TicketsState> = this.subject.asObservable();
  /** Emite el id del ticket recién creado para que la pantalla lo abra. */
  readonly ticketCreated$ = this.createdSource.asObservable();

  load(): void {
    this.patch({ loading: true, error: '' });
    forkJoin({
      rows: this.fetchPage(),
      all: this.fetchAll(),
      equipment: this.equipmentApi.listAll().pipe(catchError(() => of([] as Equipment[]))),
    }).subscribe({
      next: ({ rows, all, equipment }) => this.applyPage(rows, { all, equipment }),
      error: (error) => this.patch({ loading: false, error: httpErrorMessage(error, LOAD_ERROR) }),
    });
  }

  /** Recarga la lista y los contadores (tras crear o cambiar un ticket). */
  refresh(): void {
    forkJoin({ rows: this.fetchPage(), all: this.fetchAll() }).subscribe({
      next: ({ rows, all }) => this.applyPage(rows, { all }),
      error: (error) => this.patch({ loading: false, error: httpErrorMessage(error, LOAD_ERROR) }),
    });
  }

  setFilters(changes: Partial<TicketFilters>): void {
    const filters = { ...this.subject.value.filters, ...changes };
    const filterError = validateFilters(filters);
    this.patch({ filters, filterError, page: 0 });
    if (!filterError) {
      this.reloadList();
    }
  }

  clearFilters(): void {
    this.patch({ filters: EMPTY_FILTERS, filterError: '', page: 0 });
    this.reloadList();
  }

  setPage(page: number): void {
    if (page < 0) {
      return;
    }
    this.patch({ page });
    this.reloadList();
  }

  create(payload: MaintenanceRequestPayload): void {
    this.patch({ saving: true, error: '' });
    this.api.create(payload).subscribe({
      next: (ticket) => {
        this.patch({ saving: false });
        this.createdSource.next(ticket.id);
        this.refresh();
      },
      error: (error) =>
        this.patch({
          saving: false,
          error: httpErrorMessage(error, 'No se pudo crear el ticket. Revisa los datos e inténtalo de nuevo.'),
        }),
    });
  }

  private reloadList(): void {
    this.patch({ loading: true, error: '' });
    this.fetchPage().subscribe({
      next: (rows) => this.applyPage(rows),
      error: (error) => this.patch({ loading: false, error: httpErrorMessage(error, LOAD_ERROR) }),
    });
  }

  private fetchPage(): Observable<MaintenanceListItem[]> {
    const { filters, page, pageSize } = this.subject.value;
    const query: MaintenanceQuery = {
      status: filters.status,
      priority: filters.priority,
      search: filters.search.trim(),
      sort: SORT[filters.order],
      limit: pageSize + 1,
      offset: page * pageSize,
    };
    if (filters.dateFrom) {
      query.dateFrom = dayBoundaryIso(filters.dateFrom, false);
    }
    if (filters.dateTo) {
      query.dateTo = dayBoundaryIso(filters.dateTo, true);
    }
    return this.api.list(query);
  }

  /** Un fallo aquí no debe ocultar la lista: solo quedan sin datos los contadores. */
  private fetchAll(): Observable<MaintenanceListItem[]> {
    return this.api.list({ limit: 500 }).pipe(catchError(() => of([] as MaintenanceListItem[])));
  }

  private applyPage(rows: MaintenanceListItem[], extra: Partial<TicketsState> = {}): void {
    const { pageSize } = this.subject.value;
    this.patch({ ...extra, items: rows.slice(0, pageSize), hasNext: rows.length > pageSize, loading: false });
  }

  private patch(partial: Partial<TicketsState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
