import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  EventEmitter,
  Input,
  OnInit,
  Output,
  ViewChild,
  inject,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormsModule, NgForm } from '@angular/forms';
import { Observable } from 'rxjs';

import { EquipmentPayload, EquipmentType } from '../../core/equipment.service';

const emptyDraft = (): EquipmentPayload => ({
  asset_tag: '', serial_number: null, equipment_type_id: 0,
  brand: '', model: '', description: null, status: 'in_storage',
});

/** Dumb component: renders the form and emits the payload; knows no service. */
@Component({
  selector: 'app-equipment-form',
  standalone: true,
  imports: [FormsModule],
  template: `
    <section class="create-card">
      <h2>Add equipment</h2>
      <form #form="ngForm" (ngSubmit)="submitted.emit(draft)">
        <label>Asset tag <input name="assetTag" [(ngModel)]="draft.asset_tag" required /></label>
        <label>Serial number <input name="serialNumber" [(ngModel)]="draft.serial_number" /></label>
        <label>Type
          <select name="type" [(ngModel)]="draft.equipment_type_id" required>
            <option [ngValue]="0">Select a type</option>
            @for (type of types; track type.id) {
              <option [ngValue]="type.id">{{ type.name }}</option>
            }
          </select>
        </label>
        <label>Brand <input name="brand" [(ngModel)]="draft.brand" required /></label>
        <label>Model <input name="model" [(ngModel)]="draft.model" required /></label>
        <label>Status
          <select name="status" [(ngModel)]="draft.status">
            @for (status of statuses; track status) {
              <option [value]="status">{{ status }}</option>
            }
          </select>
        </label>
        <label class="wide">Description <textarea name="description" [(ngModel)]="draft.description"></textarea></label>
        <button type="submit" [disabled]="saving || draft.equipment_type_id === 0">
          {{ saving ? 'Saving…' : 'Add equipment' }}
        </button>
      </form>
    </section>
  `,
  styles: [
    `.create-card { margin: 1.5rem 0; padding: 1.5rem; background: white; border: 1px solid #e2e8f0; border-radius: 10px; }
     form { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1rem; }
     label { display: grid; gap: .35rem; font-weight: 600; } input, select, textarea { padding: .6rem; border: 1px solid #cbd5e1; border-radius: 5px; font: inherit; } textarea { min-height: 70px; }
     .wide { grid-column: 1 / -1; } button { width: fit-content; padding: .65rem 1rem; border: 0; border-radius: 6px; background: #0f172a; color: white; cursor: pointer; } button:disabled { opacity: .5; cursor: not-allowed; }
     @media (max-width: 760px) { form { grid-template-columns: 1fr; } }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentFormComponent implements OnInit {
  @Input() types: EquipmentType[] = [];
  @Input() statuses: readonly string[] = [];
  @Input() saving = false;
  /** Fires when the parent has successfully saved; the form then resets. */
  @Input() created$?: Observable<void>;
  @Output() readonly submitted = new EventEmitter<EquipmentPayload>();

  @ViewChild('form', { static: true }) private form!: NgForm;
  private readonly destroyRef = inject(DestroyRef);

  draft: EquipmentPayload = emptyDraft();

  ngOnInit(): void {
    this.created$
      ?.pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(() => {
        this.draft = emptyDraft();
        this.form.resetForm(this.draft);
      });
  }
}
