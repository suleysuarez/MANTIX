import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';

import { httpErrorMessage } from './http-error';
import {
  MaintenanceRecord,
  MaintenanceRecordPayload,
  MaintenanceRequest,
  MaintenanceService,
} from './maintenance.service';
import { PermissionsService } from './permissions.service';
import { Technician, TechniciansService } from './technicians.service';

export interface MaintenanceDetailState {
  request: MaintenanceRequest | null;
  records: MaintenanceRecord[];
  technicians: Technician[];
  loading: boolean;
  busy: boolean;
  error: string;
}

const INITIAL_STATE: MaintenanceDetailState = {
  request: null,
  records: [],
  technicians: [],
  loading: true,
  busy: false,
  error: '',
};

/** Observer pattern store for one maintenance ticket and the actions available on it. */
@Injectable({ providedIn: 'root' })
export class MaintenanceDetailStore {
  private readonly api = inject(MaintenanceService);
  private readonly techniciansApi = inject(TechniciansService);
  private readonly permissions = inject(PermissionsService);
  private readonly subject = new BehaviorSubject<MaintenanceDetailState>(INITIAL_STATE);

  readonly state$: Observable<MaintenanceDetailState> = this.subject.asObservable();

  load(id: number): void {
    this.subject.next(INITIAL_STATE);
    forkJoin({
      request: this.api.get(id),
      records: this.api.listRecords(id),
      // Un usuario sin permiso para ver técnicos igual puede ver el ticket.
      // Quien no puede ver a los técnicos no los pide (el servidor respondería 403).
      technicians: this.permissions.has('tecnicos:ver') ? this.techniciansApi.list().pipe(catchError(() => of([] as Technician[]))) : of([] as Technician[]),
    }).subscribe({
      next: ({ request, records, technicians }) =>
        this.patch({ request, records, technicians, loading: false }),
      error: (error) =>
        this.patch({ loading: false, error: httpErrorMessage(error, 'The request could not be loaded.') }),
    });
  }

  transition(status: string, notes: string | null, resolutionSummary: string | null): void {
    this.run('The status could not be changed.', (id) =>
      this.api.transition(id, status, notes, resolutionSummary),
    );
  }

  assign(technicianId: number, notes: string | null): void {
    this.run('The technician could not be assigned.', (id) => this.api.assign(id, technicianId, notes));
  }

  unassign(): void {
    this.run('The technician could not be unassigned.', (id) => this.api.unassign(id));
  }

  addRecord(payload: MaintenanceRecordPayload): void {
    const id = this.subject.value.request?.id;
    if (id === undefined) {
      return;
    }
    this.patch({ busy: true, error: '' });
    this.api.addRecord(id, payload).subscribe({
      next: (record) =>
        this.patch({ records: [...this.subject.value.records, record], busy: false }),
      error: (error) =>
        this.patch({ busy: false, error: httpErrorMessage(error, 'The record could not be saved.') }),
    });
  }

  private run(failure: string, action: (id: number) => Observable<MaintenanceRequest>): void {
    const id = this.subject.value.request?.id;
    if (id === undefined) {
      return;
    }
    this.patch({ busy: true, error: '' });
    action(id).subscribe({
      next: (request) => this.patch({ request, busy: false }),
      error: (error) => this.patch({ busy: false, error: httpErrorMessage(error, failure) }),
    });
  }

  private patch(partial: Partial<MaintenanceDetailState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
