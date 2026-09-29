import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject } from '@angular/core';

import { EquipmentPayload } from '../../core/equipment.service';
import { EquipmentStore } from '../../core/equipment.store';
import { EquipmentFormComponent } from './equipment-form.component';
import { EquipmentTableComponent } from './equipment-table.component';

/** Smart (container) component: talks to the store, delegates rendering. */
@Component({
  standalone: true,
  imports: [AsyncPipe, EquipmentFormComponent, EquipmentTableComponent],
  template: `
    @if (state$ | async; as state) {
      <main class="equipment-page">
        <header>
          <p class="eyebrow">Inventory</p>
          <h1>Equipment catalog</h1>
          <p>Manage technology assets and their current lifecycle state.</p>
        </header>

        @if (state.error) {
          <p class="error" role="alert">{{ state.error }}</p>
        }

        <app-equipment-form
          [types]="state.types"
          [statuses]="statuses"
          [saving]="state.saving"
          [created$]="created$"
          (submitted)="create($event)"
        />

        <section>
          <h2>Current catalog</h2>
          <app-equipment-table [equipment]="state.equipment" [loading]="state.loading" />
        </section>
      </main>
    }
  `,
  styles: [
    `.equipment-page { max-width: 1100px; margin: 3rem auto; padding: 0 1.5rem; }
     .eyebrow { color: #2563eb; font-weight: 700; text-transform: uppercase; letter-spacing: .08em; }
     .error { color: #b91c1c; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentListComponent implements OnInit {
  private readonly store = inject(EquipmentStore);

  readonly state$ = this.store.state$;
  readonly created$ = this.store.equipmentCreated$;
  readonly statuses = ['in_storage', 'assigned', 'in_repair', 'lost', 'retired', 'disposed'] as const;

  ngOnInit(): void {
    this.store.load();
  }

  create(payload: EquipmentPayload): void {
    this.store.create(payload);
  }
}
