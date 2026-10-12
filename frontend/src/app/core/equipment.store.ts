import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, Subject, catchError, concat, forkJoin, map, of, switchMap, toArray } from 'rxjs';

import { reportFilename, saveBlob } from './download';
import {
  Equipment,
  EquipmentPayload,
  EquipmentService,
  EquipmentSummary,
  EquipmentType,
  EquipmentUpdatePayload,
  LocationItem,
  ReportFormat,
} from './equipment.service';
import { httpErrorMessage } from './http-error';

export interface EquipmentFilters {
  search: string;
  /** Un estado o varios separados por comas (las tarjetas agrupan estados). */
  status: string;
  typeId: number | null;
  locationId: number | null;
}

export type EquipmentView = 'table' | 'grid';

export interface EquipmentState {
  items: Equipment[];
  total: number;
  types: EquipmentType[];
  locations: LocationItem[];
  summary: EquipmentSummary | null;
  loading: boolean;
  saving: boolean;
  exporting: boolean;
  error: string;
  saveError: string;
  /** Avisos no bloqueantes de un guardado (p. ej. un adjunto que no se pudo subir). */
  notice: string;
  filters: EquipmentFilters;
  /** Base 1. */
  page: number;
  pageSize: number;
  sort: string;
  view: EquipmentView;
}

export const EMPTY_FILTERS: EquipmentFilters = { search: '', status: '', typeId: null, locationId: null };

const INITIAL_STATE: EquipmentState = {
  items: [],
  total: 0,
  types: [],
  locations: [],
  summary: null,
  loading: true,
  saving: false,
  exporting: false,
  error: '',
  saveError: '',
  notice: '',
  filters: EMPTY_FILTERS,
  page: 1,
  pageSize: 10,
  sort: 'asset_tag',
  view: 'table',
};

export interface SaveRequest {
  /** `null` para crear. */
  id: number | null;
  payload: EquipmentPayload;
  /** Solo al crear: ubicación y custodio iniciales (después se cambian desde el detalle). */
  locationId: number | null;
  custodianId: number | null;
  files: File[];
}

/** El código de activo no se puede cambiar una vez registrado: la API lo rechaza en edición. */
function withoutAssetTag(payload: EquipmentPayload): EquipmentUpdatePayload {
  const changes: Partial<EquipmentPayload> = { ...payload };
  delete changes.asset_tag;
  return changes as EquipmentUpdatePayload;
}

const LOAD_ERROR = 'No se pudo cargar el catálogo de equipos.';

/**
 * Observer pattern: fuente única de verdad del catálogo de equipos. Los componentes
 * se suscriben a `state$` (BehaviorSubject: los suscriptores tardíos reciben el valor
 * actual) y nunca lo mutan. Búsqueda, filtros, orden y paginación se resuelven en el
 * servidor; el total sale de la cabecera `X-Total-Count`.
 */
@Injectable({ providedIn: 'root' })
export class EquipmentStore {
  private readonly api = inject(EquipmentService);
  private readonly subject = new BehaviorSubject<EquipmentState>(INITIAL_STATE);
  private readonly savedSource = new Subject<Equipment>();

  readonly state$: Observable<EquipmentState> = this.subject.asObservable();
  /** Emite una vez por guardado correcto (el formulario se cierra al recibirlo). */
  readonly saved$ = this.savedSource.asObservable();

  load(): void {
    this.patch({ loading: true, error: '' });
    forkJoin({
      page: this.api.list(this.query()),
      types: this.api.listTypes(),
      locations: this.api.listLocations().pipe(catchError(() => of([] as LocationItem[]))),
      summary: this.api.summary().pipe(catchError(() => of(null))),
    }).subscribe({
      next: ({ page, types, locations, summary }) =>
        this.patch({ items: page.items, total: page.total, types, locations, summary, loading: false }),
      error: (error) => this.patch({ loading: false, error: httpErrorMessage(error, LOAD_ERROR) }),
    });
  }

  setFilters(partial: Partial<EquipmentFilters>): void {
    this.patch({ filters: { ...this.subject.value.filters, ...partial }, page: 1 });
    this.reloadList();
  }

  resetFilters(): void {
    this.patch({ filters: EMPTY_FILTERS, page: 1 });
    this.reloadList();
  }

  setSort(sort: string): void {
    this.patch({ sort, page: 1 });
    this.reloadList();
  }

  setPage(page: number): void {
    const { pageSize, total } = this.subject.value;
    const lastPage = Math.max(1, Math.ceil(total / pageSize));
    if (page < 1 || page > lastPage) {
      return;
    }
    this.patch({ page });
    this.reloadList();
  }

  setView(view: EquipmentView): void {
    this.patch({ view });
  }

  clearNotice(): void {
    this.patch({ notice: '', saveError: '' });
  }

  /** Recarga la página actual y los contadores (tras guardar o cambiar ubicación/custodio). */
  refresh(): void {
    this.reloadList();
  }

  save(request: SaveRequest): void {
    this.patch({ saving: true, saveError: '', notice: '' });
    const saved$ =
      request.id === null
        ? this.api.create(request.payload)
        : this.api.update(request.id, withoutAssetTag(request.payload));
    saved$.pipe(switchMap((saved) => this.finishSave(saved, request))).subscribe({
      next: ({ saved, warnings }) => {
        this.patch({ saving: false, notice: warnings.join(' ') });
        this.savedSource.next(saved);
        this.reloadList();
      },
      error: (error) =>
        this.patch({
          saving: false,
          saveError: httpErrorMessage(
            error,
            'No se pudo guardar el equipo. Verifica que el código y el número de serie no estén repetidos.',
          ),
        }),
    });
  }

  export(format: ReportFormat): void {
    const { filters } = this.subject.value;
    this.patch({ exporting: true, error: '' });
    this.api.exportReport(format, { status: filters.status, equipmentTypeId: filters.typeId }).subscribe({
      next: (blob) => {
        this.patch({ exporting: false });
        saveBlob(blob, reportFilename('equipos', format));
      },
      error: (error) =>
        this.patch({ exporting: false, error: httpErrorMessage(error, 'No se pudo generar el reporte.') }),
    });
  }

  /** Pasos posteriores a crear (ubicación, custodio, adjuntos) en orden; un fallo no deshace el alta. */
  private finishSave(
    saved: Equipment,
    request: SaveRequest,
  ): Observable<{ saved: Equipment; warnings: string[] }> {
    const steps: Observable<string | null>[] = [];
    const attempt = (call: Observable<unknown>, warning: string) =>
      call.pipe(
        map(() => null),
        catchError(() => of(warning)),
      );
    if (request.id === null) {
      if (request.locationId) {
        steps.push(attempt(this.api.assignLocation(saved.id, request.locationId), 'No se pudo asignar la ubicación.'));
      }
      if (request.custodianId) {
        steps.push(attempt(this.api.assignCustody(saved.id, request.custodianId), 'No se pudo asignar el custodio.'));
      }
      for (const file of request.files) {
        steps.push(attempt(this.api.uploadAttachment(saved.id, file), `No se pudo adjuntar «${file.name}».`));
      }
    }
    if (steps.length === 0) {
      return of({ saved, warnings: [] });
    }
    return concat(...steps).pipe(
      toArray(),
      map((results) => ({ saved, warnings: results.filter((item): item is string => item !== null) })),
    );
  }

  private reloadList(): void {
    this.patch({ loading: true, error: '' });
    forkJoin({
      page: this.api.list(this.query()),
      summary: this.api.summary().pipe(catchError(() => of(null))),
    }).subscribe({
      next: ({ page, summary }) =>
        this.patch({
          items: page.items,
          total: page.total,
          summary: summary ?? this.subject.value.summary,
          loading: false,
        }),
      error: (error) => this.patch({ loading: false, error: httpErrorMessage(error, LOAD_ERROR) }),
    });
  }

  private query() {
    const { filters, page, pageSize, sort } = this.subject.value;
    return {
      search: filters.search,
      status: filters.status,
      equipmentTypeId: filters.typeId,
      locationId: filters.locationId,
      sort,
      page,
      size: pageSize,
    };
  }

  private patch(partial: Partial<EquipmentState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
