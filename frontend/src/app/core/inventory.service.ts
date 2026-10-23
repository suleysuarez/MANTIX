import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { apiBaseUrl } from './api.config';
import { Period } from './dashboard-kpis.service';

/** Código de una categoría: las 5 de fábrica y las que se agreguen desde el formulario. */
export type ItemCategory = string;
export type OptionKind = 'category' | 'unit' | 'location' | 'supplier';

/** Valor de uno de los desplegables del ítem (`value` es lo que se guarda; `label`, lo que se lee). */
export interface InventoryOption {
  kind: OptionKind;
  value: string;
  label: string;
}
export type StockStatus = 'ok' | 'low' | 'out';
export type ItemStatusFilter = '' | 'ok' | 'low' | 'out' | 'stale' | 'active' | 'inactive';
export type MovementKind = 'in' | 'out' | 'adjust';

/** Límites que impone el backend (la fuente de verdad); el frontend los repite para avisar antes. */
export const INVENTORY_LIMITS = { maxQuantity: 1_000_000, maxCost: 1_000_000, skuMin: 3, skuMax: 40 } as const;

export interface InventoryItem {
  id: number;
  sku: string;
  name: string;
  description: string | null;
  category: ItemCategory;
  unit: string;
  /** Importes como texto: la API usa `Decimal`. */
  unit_cost: string;
  stock: number;
  min_stock: number;
  max_stock: number | null;
  location: string | null;
  supplier: string | null;
  is_active: boolean;
  status: StockStatus;
  stock_value: string;
  /** Stock contra el máximo (o el doble del mínimo si no hay máximo), 0–100. */
  level_pct: number;
  last_movement_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface ItemPayload {
  sku: string;
  name: string;
  description: string | null;
  category: ItemCategory;
  unit: string;
  unit_cost: number;
  min_stock: number;
  max_stock: number | null;
  location: string | null;
  supplier: string | null;
  initial_stock: number;
}

export type ItemUpdatePayload = Partial<Omit<ItemPayload, 'sku' | 'initial_stock'>> & { is_active?: boolean };

export interface MovementPayload {
  kind: MovementKind;
  quantity: number;
  unit_cost?: number | null;
  notes?: string | null;
  record_id?: number | null;
  request_id?: number | null;
}

export interface Movement {
  id: number;
  item_id: number;
  kind: MovementKind;
  /** Con signo: entradas > 0, consumo < 0. */
  quantity: number;
  stock_after: number;
  unit_cost: string | null;
  notes: string | null;
  record_id: number | null;
  request_id: number | null;
  created_by: string | null;
  created_at: string;
}

export interface ItemQuery {
  search?: string;
  category?: ItemCategory | '';
  status?: ItemStatusFilter;
  /** Rangos (inclusivos, pueden ser de un solo lado): stock, costo unitario y fechas ISO de ingreso / último movimiento. */
  stockMin?: number;
  stockMax?: number;
  costMin?: number;
  costMax?: number;
  createdFrom?: string;
  createdTo?: string;
  movedFrom?: string;
  movedTo?: string;
  sort?: string;
  /** Base 1. */
  page?: number;
  size?: number;
}

export interface StockValue {
  total: string;
  previous: string | null;
  change_pct: number | null;
  items: number;
}

export interface Consumption {
  units: number;
  value: string;
  previous_units: number;
  change_pct: number | null;
  movements: number;
  low_sample: boolean;
}

export interface Rotation {
  value: number | null;
  previous: number | null;
  change_pct: number | null;
}

export interface MonthlyConsumption {
  month: string;
  units: number;
}

export interface ReorderAlert {
  item_id: number;
  sku: string;
  name: string;
  stock: number;
  min_stock: number;
  suggested_order: number;
}

export interface StaleItem {
  item_id: number;
  sku: string;
  name: string;
  stock: number;
  last_movement_at: string | null;
}

export interface UsedItem {
  item_id: number;
  sku: string;
  name: string;
  units: number;
}

export interface InventoryOverview {
  generated_at: string;
  period: Period;
  window_start: string;
  window_end: string;
  stock_value: StockValue;
  low_stock: number;
  out_of_stock: number;
  consumption: Consumption;
  rotation: Rotation;
  monthly_consumption: MonthlyConsumption[];
  stale_count: number;
  stale_items: StaleItem[];
  most_used: UsedItem[];
  reorder: ReorderAlert[];
}

export interface ImportRowError {
  row: number;
  field: string | null;
  message: string;
}

export interface ImportResult {
  dry_run: boolean;
  success: boolean;
  total_rows: number;
  created: number;
  errors: ImportRowError[];
  /** Filas que pasaron la validación y filas con al menos un problema (el resumen previo). */
  valid_rows?: number | null;
  error_rows?: number | null;
}

/** Inventario de repuestos y consumibles (`/inventory`). */
@Injectable({ providedIn: 'root' })
export class InventoryService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/inventory`;

  /** Filtros, orden y paginación en el servidor; el total llega en `X-Total-Count`. */
  listPage(query: ItemQuery = {}): Observable<{ items: InventoryItem[]; total: number }> {
    let params = new HttpParams();
    if (query.search) {
      params = params.set('search', query.search);
    }
    if (query.category) {
      params = params.set('category', query.category);
    }
    if (query.status) {
      params = params.set('status', query.status);
    }
    const ranges: [string, string | number | undefined][] = [
      ['stock_min', query.stockMin], ['stock_max', query.stockMax], ['cost_min', query.costMin], ['cost_max', query.costMax],
      ['created_from', query.createdFrom], ['created_to', query.createdTo], ['moved_from', query.movedFrom], ['moved_to', query.movedTo],
    ];
    for (const [name, value] of ranges) {
      if (value !== undefined) {
        params = params.set(name, value);
      }
    }
    if (query.sort) {
      params = params.set('sort', query.sort);
    }
    if (query.page !== undefined) {
      params = params.set('page', query.page);
    }
    if (query.size !== undefined) {
      params = params.set('size', query.size);
    }
    return this.http.get<InventoryItem[]>(`${this.url}/items`, { params, observe: 'response' }).pipe(
      map((response) => {
        const items = response.body ?? [];
        const total = Number(response.headers.get('X-Total-Count'));
        return { items, total: Number.isFinite(total) && total >= items.length ? total : items.length };
      }),
    );
  }

  get(id: number): Observable<InventoryItem> {
    return this.http.get<InventoryItem>(`${this.url}/items/${id}`);
  }

  create(payload: ItemPayload): Observable<InventoryItem> {
    return this.http.post<InventoryItem>(`${this.url}/items`, payload);
  }

  update(id: number, payload: ItemUpdatePayload): Observable<InventoryItem> {
    return this.http.patch<InventoryItem>(`${this.url}/items/${id}`, payload);
  }

  remove(id: number): Observable<void> {
    return this.http.delete<void>(`${this.url}/items/${id}`);
  }

  move(id: number, payload: MovementPayload): Observable<Movement> {
    return this.http.post<Movement>(`${this.url}/items/${id}/movements`, payload);
  }

  movements(id: number, page = 1, size = 10): Observable<{ items: Movement[]; total: number }> {
    const params = new HttpParams().set('page', page).set('size', size);
    return this.http.get<Movement[]>(`${this.url}/items/${id}/movements`, { params, observe: 'response' }).pipe(
      map((response) => {
        const items = response.body ?? [];
        const total = Number(response.headers.get('X-Total-Count'));
        return { items, total: Number.isFinite(total) && total >= items.length ? total : items.length };
      }),
    );
  }

  overview(period: Period): Observable<InventoryOverview> {
    return this.http.get<InventoryOverview>(`${this.url}/overview`, { params: new HttpParams().set('period', period) });
  }

  /** Plantilla de importación en Excel (con el mismo estilo que los demás archivos de Mantix). */
  importTemplate(): Observable<Blob> {
    return this.http.get(`${this.url}/import/template`, { responseType: 'blob' });
  }

  /** Valores de los desplegables (categorías, unidades, ubicaciones y proveedores). */
  options(): Observable<InventoryOption[]> {
    return this.http.get<InventoryOption[]>(`${this.url}/options`);
  }

  /** Agrega un valor a un desplegable; el servidor lo normaliza y rechaza los repetidos (409). */
  createOption(kind: OptionKind, name: string): Observable<InventoryOption> {
    return this.http.post<InventoryOption>(`${this.url}/options`, { kind, name });
  }

  /**
   * Importación fila por fila. Con `dryRun` solo valida y resume. Por defecto es todo-o-nada; con
   * `skipInvalid` importa las filas válidas y reporta las demás.
   */
  importFile(file: File, dryRun: boolean, skipInvalid = false): Observable<ImportResult> {
    const body = new FormData();
    body.append('file', file, file.name);
    const params = new HttpParams().set('dry_run', dryRun).set('skip_invalid', skipInvalid);
    return this.http.post<ImportResult>(`${this.url}/import`, body, { params });
  }
}
