import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, of } from 'rxjs';
import { catchError, map, tap } from 'rxjs/operators';

import { apiErrorMessage, apiFieldErrors } from './api-errors';
import { Period } from './dashboard-kpis.service';
import {
  ImportResult,
  InventoryItem,
  InventoryOption,
  InventoryOverview,
  InventoryService,
  ItemCategory,
  OptionKind,
  ItemPayload,
  ItemQuery,
  ItemStatusFilter,
  ItemUpdatePayload,
  Movement,
  MovementPayload,
} from './inventory.service';
import { ActionResult } from './pending-requests.store';
import { ToastService } from './toast.service';
import { dayBoundaryIso } from '../features/reports/report-filters';
import { RangeErrors, hasRangeErrors, rangeErrors } from '../features/inventory/inventory-ui';

export type InventoryView = 'grid' | 'table';

export interface InventoryFilters {
  search: string;
  category: ItemCategory | '';
  status: ItemStatusFilter;
  /** `name`, `-stock`, `stock_value`, `-updated_at`… (prefijo `-` descendente). */
  sort: string;
  /** Rangos de stock y de precio (números) y de fechas de ingreso / último movimiento (`yyyy-MM-dd`); vacío = sin límite. */
  stockMin: string;
  stockMax: string;
  costMin: string;
  costMax: string;
  createdFrom: string;
  createdTo: string;
  movedFrom: string;
  movedTo: string;
}

export const PAGE_SIZE = 12;
export const EMPTY_FILTERS: InventoryFilters = {
  search: '', category: '', status: '', sort: 'name',
  stockMin: '', stockMax: '', costMin: '', costMax: '', createdFrom: '', createdTo: '', movedFrom: '', movedTo: '',
};
const NO_ERRORS: RangeErrors = { stock: '', cost: '', created: '', moved: '' };

export interface InventoryState {
  view: InventoryView;
  filters: InventoryFilters;
  /** Problemas de los filtros por rango; con alguno no se consulta al servidor. */
  filterErrors: RangeErrors;
  /** Valores de los desplegables del ítem (categorías, unidades, ubicaciones y proveedores). */
  options: InventoryOption[];
  items: InventoryItem[];
  total: number;
  page: number;
  loading: boolean;
  error: string;
  period: Period;
  overview: InventoryOverview | null;
  overviewLoading: boolean;
  selectedId: number | null;
  item: InventoryItem | null;
  movements: Movement[];
  movementsTotal: number;
  detailLoading: boolean;
  detailError: string;
  busy: boolean;
}

const INITIAL: InventoryState = {
  view: 'grid',
  filters: EMPTY_FILTERS,
  filterErrors: NO_ERRORS,
  options: [],
  items: [],
  total: 0,
  page: 1,
  loading: true,
  error: '',
  period: '30d',
  overview: null,
  overviewLoading: true,
  selectedId: null,
  item: null,
  movements: [],
  movementsTotal: 0,
  detailLoading: false,
  detailError: '',
  busy: false,
};

/** Observer pattern store del inventario: listado del servidor, métricas, detalle y movimientos. */
@Injectable({ providedIn: 'root' })
export class InventoryStore {
  private readonly api = inject(InventoryService);
  private readonly toasts = inject(ToastService);
  private readonly subject = new BehaviorSubject<InventoryState>(INITIAL);

  readonly state$: Observable<InventoryState> = this.subject.asObservable();

  private get value(): InventoryState {
    return this.subject.value;
  }

  private patch(changes: Partial<InventoryState>): void {
    this.subject.next({ ...this.value, ...changes });
  }

  load(): void {
    this.loadList(1);
    this.loadOverview();
    this.loadOptions();
  }

  /** Guarda un valor nuevo en un desplegable y lo deja disponible al instante, sin recargar. */
  createOption(kind: OptionKind, name: string): Observable<InventoryOption> {
    return this.api.createOption(kind, name).pipe(
      tap((option) => {
        const known = this.value.options.some((o) => o.kind === option.kind && o.value === option.value);
        this.patch({ options: known ? this.value.options : [...this.value.options, option] });
      }),
    );
  }

  setView(view: InventoryView): void {
    this.patch({ view });
  }

  setFilters(changes: Partial<InventoryFilters>): void {
    const filters = { ...this.value.filters, ...changes };
    const filterErrors = rangeErrors(filters);
    this.patch({ filters, filterErrors });
    if (!hasRangeErrors(filterErrors)) {
      this.loadList(1);
    }
  }

  clearFilters(): void {
    this.setFilters(EMPTY_FILTERS);
  }

  setPage(page: number): void {
    if (page >= 1 && !this.value.loading) {
      this.loadList(page);
    }
  }

  setPeriod(period: Period): void {
    this.patch({ period });
    this.loadOverview();
  }

  select(id: number | null): void {
    this.patch({ selectedId: id, item: null, movements: [], movementsTotal: 0, detailError: '', detailLoading: id !== null });
    if (id !== null) {
      this.loadDetail(id);
    }
  }

  create(payload: ItemPayload): Observable<ActionResult> {
    return this.run(this.api.create(payload), 'Ítem creado.');
  }

  update(id: number, payload: ItemUpdatePayload, success = 'Ítem actualizado.'): Observable<ActionResult> {
    return this.run(this.api.update(id, payload), success);
  }

  remove(id: number): Observable<ActionResult> {
    return this.run(this.api.remove(id), 'Ítem eliminado.', () => this.select(null));
  }

  move(id: number, payload: MovementPayload): Observable<ActionResult> {
    const label = payload.kind === 'out' ? 'Consumo registrado.' : payload.kind === 'in' ? 'Entrada registrada.' : 'Ajuste registrado.';
    return this.run(this.api.move(id, payload), label);
  }

  /**
   * Importa el archivo; con `dryRun` solo valida y resume. Con `skipInvalid` importa las filas válidas.
   * Una importación real que crea ítems refresca todo (y los desplegables, por si trajo valores nuevos).
   */
  importFile(file: File, dryRun: boolean, skipInvalid = false): Observable<ImportResult | null> {
    if (this.value.busy) {
      return of(null);
    }
    this.patch({ busy: true });
    return this.api.importFile(file, dryRun, skipInvalid).pipe(
      tap((result) => {
        if (!dryRun && result.created > 0) {
          this.toasts.success(`${result.created} ítems importados.`);
          this.refresh();
          this.loadOptions();
        }
      }),
      tap(() => this.patch({ busy: false })),
      catchError((error) => {
        this.patch({ busy: false });
        this.toasts.error(apiErrorMessage(error, 'No se pudo leer el archivo.'));
        return of(null);
      }),
    );
  }

  private run<T>(call: Observable<T>, success: string, after?: () => void): Observable<ActionResult> {
    if (this.value.busy) {
      return of({ ok: false, fieldErrors: {} });
    }
    this.patch({ busy: true });
    return call.pipe(
      tap(() => this.toasts.success(success)),
      map(() => {
        this.patch({ busy: false });
        after?.();
        this.refresh();
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
    this.loadList(this.value.page);
    this.loadOverview();
    if (this.value.selectedId !== null) {
      this.loadDetail(this.value.selectedId);
    }
  }

  private query(page: number): ItemQuery {
    const f = this.value.filters;
    const number = (value: string): number | undefined => (value.trim() === '' ? undefined : Number(value));
    return {
      search: f.search.trim() || undefined,
      category: f.category,
      status: f.status,
      sort: f.sort,
      stockMin: number(f.stockMin),
      stockMax: number(f.stockMax),
      costMin: number(f.costMin),
      costMax: number(f.costMax),
      createdFrom: dayBoundaryIso(f.createdFrom, false) ?? undefined,
      createdTo: dayBoundaryIso(f.createdTo, true) ?? undefined,
      movedFrom: dayBoundaryIso(f.movedFrom, false) ?? undefined,
      movedTo: dayBoundaryIso(f.movedTo, true) ?? undefined,
      page,
      size: PAGE_SIZE,
    };
  }

  private loadList(page: number): void {
    this.patch({ loading: true, error: '' });
    this.api.listPage(this.query(page)).subscribe({
      next: ({ items, total }) => {
        // Si la última página quedó vacía (p. ej. tras eliminar), retrocede una.
        if (items.length === 0 && page > 1) {
          this.loadList(page - 1);
          return;
        }
        this.patch({ items, total, page, loading: false });
      },
      error: (error) => this.patch({ loading: false, error: apiErrorMessage(error, 'No se pudo cargar el inventario.') }),
    });
  }

  private loadOptions(): void {
    this.api.options().subscribe({
      next: (options) => this.patch({ options }),
      error: () => undefined, // sin listas, los desplegables solo ofrecen lo que ya traen los ítems
    });
  }

  private loadOverview(): void {
    this.patch({ overviewLoading: true });
    const period = this.value.period;
    this.api.overview(period).subscribe({
      next: (overview) => {
        if (this.value.period === period) {
          this.patch({ overview, overviewLoading: false });
        }
      },
      error: () => this.patch({ overview: null, overviewLoading: false }),
    });
  }

  private loadDetail(id: number): void {
    this.api.get(id).subscribe({
      next: (item) => {
        if (this.value.selectedId === id) {
          this.patch({ item, detailLoading: false });
        }
      },
      error: (error) => {
        if (this.value.selectedId === id) {
          this.patch({ detailLoading: false, detailError: apiErrorMessage(error, 'No se pudo cargar el ítem.') });
        }
      },
    });
    this.api.movements(id).subscribe({
      next: ({ items, total }) => {
        if (this.value.selectedId === id) {
          this.patch({ movements: items, movementsTotal: total });
        }
      },
      error: () => undefined,
    });
  }
}
