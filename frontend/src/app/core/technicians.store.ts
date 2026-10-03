import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable } from 'rxjs';

import { httpErrorMessage } from './http-error';
import { Technician, TechnicianPayload, TechniciansService } from './technicians.service';

export interface TechniciansState {
  technicians: Technician[];
  loading: boolean;
  saving: boolean;
  error: string;
}

const INITIAL_STATE: TechniciansState = { technicians: [], loading: true, saving: false, error: '' };

/** Observer pattern store for technician profiles. */
@Injectable({ providedIn: 'root' })
export class TechniciansStore {
  private readonly api = inject(TechniciansService);
  private readonly subject = new BehaviorSubject<TechniciansState>(INITIAL_STATE);

  readonly state$: Observable<TechniciansState> = this.subject.asObservable();

  load(): void {
    this.patch({ loading: true, error: '' });
    this.api.list().subscribe({
      next: (technicians) => this.patch({ technicians, loading: false }),
      error: (error) =>
        this.patch({ loading: false, error: httpErrorMessage(error, 'Technicians could not be loaded.') }),
    });
  }

  create(payload: TechnicianPayload): void {
    this.patch({ saving: true, error: '' });
    this.api.create(payload).subscribe({
      next: (created) =>
        this.patch({ technicians: [...this.subject.value.technicians, created], saving: false }),
      error: (error) =>
        this.patch({
          saving: false,
          error: httpErrorMessage(error, 'The technician could not be created. The user may not exist or already has a profile.'),
        }),
    });
  }

  setAvailability(id: number, isAvailable: boolean): void {
    this.patch({ error: '' });
    this.api.setAvailability(id, isAvailable).subscribe({
      next: (updated) =>
        this.patch({
          technicians: this.subject.value.technicians.map((item) => (item.id === id ? updated : item)),
        }),
      error: (error) => this.patch({ error: httpErrorMessage(error, 'The technician could not be updated.') }),
    });
  }

  private patch(partial: Partial<TechniciansState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
