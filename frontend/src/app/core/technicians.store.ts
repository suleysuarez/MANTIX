import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, Subject, forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';

import { httpErrorMessage } from './http-error';
import {
  Technician,
  TechnicianPayload,
  TechniciansService,
  TechnicianUpdatePayload,
  TechnicianWorkload,
} from './technicians.service';

export interface TechniciansState {
  technicians: Technician[];
  /** Carga por id de técnico; vacío si el usuario no puede ver las métricas. */
  workload: Record<number, TechnicianWorkload | undefined>;
  /** `false` cuando las métricas de carga no pudieron cargarse. */
  hasWorkload: boolean;
  windowDays: number;
  loading: boolean;
  saving: boolean;
  error: string;
  notice: string;
}

const INITIAL_STATE: TechniciansState = {
  technicians: [],
  workload: {},
  hasWorkload: false,
  windowDays: 30,
  loading: true,
  saving: false,
  error: '',
  notice: '',
};

const WINDOW_DAYS = 30;

/** Observer pattern store para los perfiles de técnicos, su disponibilidad y su carga. */
@Injectable({ providedIn: 'root' })
export class TechniciansStore {
  private readonly api = inject(TechniciansService);
  private readonly subject = new BehaviorSubject<TechniciansState>(INITIAL_STATE);
  private readonly savedSource = new Subject<Technician>();

  readonly state$: Observable<TechniciansState> = this.subject.asObservable();
  /** Emite el perfil recién creado o editado para que la pantalla cierre su formulario. */
  readonly saved$ = this.savedSource.asObservable();

  load(): void {
    this.patch({ loading: true, error: '' });
    forkJoin({
      technicians: this.api.list(),
      // Sin permiso para ver métricas (o si fallan) la lista sigue siendo útil.
      workload: this.api.workload(WINDOW_DAYS).pipe(catchError(() => of(null))),
    }).subscribe({
      next: ({ technicians, workload }) =>
        this.patch({
          technicians,
          workload: Object.fromEntries((workload?.technicians ?? []).map((item) => [item.technician_id, item])),
          hasWorkload: workload !== null,
          windowDays: workload?.window_days ?? WINDOW_DAYS,
          loading: false,
        }),
      error: (error) =>
        this.patch({ loading: false, error: httpErrorMessage(error, 'No se pudieron cargar los técnicos.') }),
    });
  }

  create(payload: TechnicianPayload): void {
    this.patch({ saving: true, error: '', notice: '' });
    this.api.create(payload).subscribe({
      next: (created) => {
        this.patch({
          technicians: [...this.subject.value.technicians, created],
          saving: false,
          notice: `Técnico «${created.full_name}» registrado.`,
        });
        this.savedSource.next(created);
      },
      error: (error) =>
        this.patch({
          saving: false,
          error: httpErrorMessage(
            error,
            'No se pudo registrar el técnico. El usuario no existe, está inactivo o ya tiene un perfil.',
          ),
        }),
    });
  }

  update(id: number, payload: TechnicianUpdatePayload, notice: string): void {
    this.patch({ saving: true, error: '', notice: '' });
    this.api.update(id, payload).subscribe({
      next: (updated) => {
        this.patch({
          technicians: this.subject.value.technicians.map((item) => (item.id === id ? updated : item)),
          saving: false,
          notice,
        });
        this.savedSource.next(updated);
      },
      error: (error) =>
        this.patch({ saving: false, error: httpErrorMessage(error, 'No se pudo actualizar el técnico.') }),
    });
  }

  setAvailability(technician: Technician, isAvailable: boolean): void {
    this.update(
      technician.id,
      { is_available: isAvailable },
      `${technician.full_name} ahora está ${isAvailable ? 'disponible' : 'no disponible'}.`,
    );
  }

  clearMessages(): void {
    this.patch({ error: '', notice: '' });
  }

  private patch(partial: Partial<TechniciansState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
