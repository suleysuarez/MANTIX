import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, Subject, forkJoin, tap } from 'rxjs';

import {
  Equipment,
  EquipmentPayload,
  EquipmentService,
  EquipmentType,
} from './equipment.service';

export interface EquipmentState {
  equipment: Equipment[];
  types: EquipmentType[];
  loading: boolean;
  saving: boolean;
  error: string;
}

const INITIAL_STATE: EquipmentState = {
  equipment: [],
  types: [],
  loading: true,
  saving: false,
  error: '',
};

/**
 * Observer pattern: the single source of truth for the equipment catalog.
 * Consumers subscribe to `state$` (BehaviorSubject-backed, so late
 * subscribers get the current value immediately) and never mutate it.
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
    forkJoin({ equipment: this.api.list(), types: this.api.listTypes() }).subscribe({
      next: ({ equipment, types }) => this.patch({ equipment, types, loading: false }),
      error: () =>
        this.patch({ loading: false, error: 'Equipment catalog could not be loaded.' }),
    });
  }

  create(payload: EquipmentPayload): void {
    this.patch({ saving: true, error: '' });
    this.api
      .create(payload)
      .pipe(
        tap((created) =>
          this.patch({
            equipment: [...this.subject.value.equipment, created].sort((a, b) =>
              a.asset_tag.localeCompare(b.asset_tag),
            ),
          }),
        ),
      )
      .subscribe({
        next: () => {
          this.patch({ saving: false });
          this.equipmentCreatedSource.next();
        },
        error: () =>
          this.patch({
            saving: false,
            error: 'Equipment could not be created. Check unique asset and serial values.',
          }),
      });
  }

  private patch(partial: Partial<EquipmentState>): void {
    this.subject.next({ ...this.subject.value, ...partial });
  }
}
