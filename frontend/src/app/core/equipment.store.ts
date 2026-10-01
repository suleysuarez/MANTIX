import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, Subject, forkJoin } from 'rxjs';

import {
  Equipment,
  EquipmentPayload,
  EquipmentService,
  EquipmentType,
} from './equipment.service';
import { httpErrorMessage } from './http-error';

export interface EquipmentState {
  equipment: Equipment[];
  types: EquipmentType[];
  loading: boolean;
  saving: boolean;
  error: string;
  search: string;
  status: string;
  /** Página actual, base 0. */
  page: number;
  pageSize: number;
  hasNext: boolean;
}

const INITIAL_STATE: EquipmentState = {
  equipment: [],
  types: [],
  loading: true,
  saving: false,
  error: '',
  search: '',
  status: '',
  page: 0,
  pageSize: 20,
  hasNext: false,
};

const LOAD_ERROR = 'Equipment catalog could not be loaded.';

/**
 * Observer pattern: the single source of truth for the equipment catalog.
 * Consumers subscribe to `state$` (BehaviorSubject-backed, so late
 * subscribers get the current value immediately) and never mutate it.
 *
 * Search, status filter and pagination run on the server. The API returns no
 * total, so each request asks for one extra row to learn whether a next page
 * exists.
 */
@Injectable({ providedIn: 'root' })
export class EquipmentStore {
  private readonly api = inject(EquipmentService);
  private readonly subject = new BehaviorSubject<EquipmentState>(INITIAL_STATE);

  private readonly equipmentCreatedSource = new Subject<void>();

  readonly state$: Observable<EquipmentState> = this.subject.asObservable();
  /** Emits once per successful creation (e.g. so a form can reset itself). */
  readonly equipmentCreated$ = this.equipmentCreatedSource.asObservable();

  load(): void {
    this.patch({ loading: true, error: '' });
    forkJoin({ equipment: this.fetchPage(), types: this.api.listTypes() }).subscribe({
      next: ({ equipment, types }) => this.applyPage(equipment, { types }),
      error: (error) => this.patch({ loading: false, error: httpErrorMessage(error, LOAD_ERROR) }),
    });
  }

  setFilters(search: string, status: string): void {
    this.patch({ search: search.trim(), status, page: 0 });
    this.reloadList();
  }

  setPage(page: number): void {
    if (page < 0) {
      return;
    }
    this.patch({ page });
    this.reloadList();
  }

  create(payload: EquipmentPayload): void {
    this.patch({ saving: true, error: '' });
    this.api.create(payload).subscribe({
      next: () => {
        this.patch({ saving: false });
        this.equipmentCreatedSource.next();
        this.reloadList();
      },
      error: (error) =>
        this.patch({
          saving: false,
          error: httpErrorMessage(
            error,
            'Equipment could not be created. Check unique asset and serial values.',
          ),
        }),
    });
  }

  private reloadList(): void {
    this.patch({ loading: true, error: '' });
    this.fetchPage().subscribe({
      next: (equipment) => this.applyPage(equipment),
      error: (error) => this.patch({ loading: false, error: httpErrorMessage(error, LOAD_ERROR) }),
    });
  }

  private fetchPage(): Observable<Equipment[]> {
    const { search, status, page, pageSize } = this.subject.value;
    return this.api.list({ search, status, limit: pageSize + 1, offset: page * pageSize });
  }

  private applyPage(rows: Equipment[], extra: Partial<EquipmentState> = {}): void {
    const { pageSize } = this.subject.value;
    this.patch({
      ...extra,
      equipment: rows.slice(0, pageSize),
      hasNext: rows.length > pageSize,
      loading: false,
    });
  }

  private patch(partial: Partial<EquipmentState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
