import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, Subject, forkJoin } from 'rxjs';

import { Equipment, EquipmentService } from './equipment.service';
import { httpErrorMessage } from './http-error';
import {
  MaintenanceListItem,
  MaintenanceRequestPayload,
  MaintenanceService,
} from './maintenance.service';

export interface MaintenanceListState {
  items: MaintenanceListItem[];
  equipment: Equipment[];
  loading: boolean;
  saving: boolean;
  error: string;
  status: string;
  priority: string;
  page: number;
  pageSize: number;
  hasNext: boolean;
}

const INITIAL_STATE: MaintenanceListState = {
  items: [],
  equipment: [],
  loading: true,
  saving: false,
  error: '',
  status: '',
  priority: '',
  page: 0,
  pageSize: 20,
  hasNext: false,
};

const LOAD_ERROR = 'Maintenance requests could not be loaded.';

/** Observer pattern store for the maintenance ticket list (filters + paging + creation). */
@Injectable({ providedIn: 'root' })
export class MaintenanceStore {
  private readonly api = inject(MaintenanceService);
  private readonly equipmentApi = inject(EquipmentService);
  private readonly subject = new BehaviorSubject<MaintenanceListState>(INITIAL_STATE);
  private readonly createdSource = new Subject<void>();

  readonly state$: Observable<MaintenanceListState> = this.subject.asObservable();
  /** Emits once per successful creation so the form can reset itself. */
  readonly requestCreated$ = this.createdSource.asObservable();

  load(): void {
    this.patch({ loading: true, error: '' });
    forkJoin({
      rows: this.fetchPage(),
      equipment: this.equipmentApi.list({ limit: 500 }),
    }).subscribe({
      next: ({ rows, equipment }) => this.applyPage(rows, { equipment }),
      error: (error) => this.patch({ loading: false, error: httpErrorMessage(error, LOAD_ERROR) }),
    });
  }

  setFilters(status: string, priority: string): void {
    this.patch({ status, priority, page: 0 });
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
      next: () => {
        this.patch({ saving: false });
        this.createdSource.next();
        this.reloadList();
      },
      error: (error) =>
        this.patch({
          saving: false,
          error: httpErrorMessage(error, 'The request could not be created. Review the data and try again.'),
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
    const { status, priority, page, pageSize } = this.subject.value;
    return this.api.list({ status, priority, limit: pageSize + 1, offset: page * pageSize });
  }

  private applyPage(rows: MaintenanceListItem[], extra: Partial<MaintenanceListState> = {}): void {
    const { pageSize } = this.subject.value;
    this.patch({ ...extra, items: rows.slice(0, pageSize), hasNext: rows.length > pageSize, loading: false });
  }

  private patch(partial: Partial<MaintenanceListState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
