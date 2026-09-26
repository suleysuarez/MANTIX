import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  inject,
} from '@angular/core';
import { FormsModule } from '@angular/forms';

import {
  Equipment,
  EquipmentPayload,
  EquipmentService,
  EquipmentType,
} from '../../core/equipment.service';

@Component({
  standalone: true,
  imports: [FormsModule],
  template: `
    <main class="equipment-page">
      <header>
        <p class="eyebrow">Inventory</p>
        <h1>Equipment catalog</h1>
        <p>Manage technology assets and their current lifecycle state.</p>
      </header>

      @if (error) {
        <p class="error" role="alert">{{ error }}</p>
      }

      <section class="create-card">
        <h2>Add equipment</h2>
        <form (ngSubmit)="createEquipment()">
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

      <section>
        <h2>Current catalog</h2>
        @if (loading) {
          <p>Loading equipment…</p>
        } @else if (equipment.length === 0) {
          <p class="empty">No equipment has been registered yet.</p>
        } @else {
          <div class="table-wrap">
            <table>
              <thead><tr><th>Asset tag</th><th>Type</th><th>Brand / model</th><th>Status</th><th>Serial</th></tr></thead>
              <tbody>
                @for (item of equipment; track item.id) {
                  <tr><td>{{ item.asset_tag }}</td><td>{{ item.equipment_type.name }}</td><td>{{ item.brand }} {{ item.model }}</td><td>{{ item.status }}</td><td>{{ item.serial_number || '—' }}</td></tr>
                }
              </tbody>
            </table>
          </div>
        }
      </section>
    </main>
  `,
  styles: [
    `.equipment-page { max-width: 1100px; margin: 3rem auto; padding: 0 1.5rem; }
     .eyebrow { color: #2563eb; font-weight: 700; text-transform: uppercase; letter-spacing: .08em; }
     .create-card, .empty, .table-wrap { margin: 1.5rem 0; padding: 1.5rem; background: white; border: 1px solid #e2e8f0; border-radius: 10px; }
     form { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1rem; }
     label { display: grid; gap: .35rem; font-weight: 600; } input, select, textarea { padding: .6rem; border: 1px solid #cbd5e1; border-radius: 5px; font: inherit; } textarea { min-height: 70px; }
     .wide { grid-column: 1 / -1; } button { width: fit-content; padding: .65rem 1rem; border: 0; border-radius: 6px; background: #0f172a; color: white; cursor: pointer; } button:disabled { opacity: .5; cursor: not-allowed; }
     .table-wrap { overflow-x: auto; } table { width: 100%; border-collapse: collapse; } th, td { padding: .75rem; text-align: left; border-bottom: 1px solid #e2e8f0; } .error { color: #b91c1c; } @media (max-width: 760px) { form { grid-template-columns: 1fr; } }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentListComponent implements OnInit {
  private readonly service = inject(EquipmentService);
  equipment: Equipment[] = [];
  types: EquipmentType[] = [];
  statuses = ['in_storage', 'assigned', 'in_repair', 'lost', 'retired', 'disposed'];
  loading = true;
  saving = false;
  error = '';
  draft: EquipmentPayload = {
    asset_tag: '', serial_number: null, equipment_type_id: 0,
    brand: '', model: '', description: null, status: 'in_storage',
  };

  async ngOnInit(): Promise<void> {
    try {
      [this.equipment, this.types] = await Promise.all([
        this.service.list(), this.service.listTypes(),
      ]);
    } catch {
      this.error = 'Equipment catalog could not be loaded.';
    } finally {
      this.loading = false;
    }
  }

  async createEquipment(): Promise<void> {
    this.saving = true;
    this.error = '';
    try {
      const created = await this.service.create(this.draft);
      this.equipment = [...this.equipment, created].sort((a, b) => a.asset_tag.localeCompare(b.asset_tag));
      this.draft = { asset_tag: '', serial_number: null, equipment_type_id: 0, brand: '', model: '', description: null, status: 'in_storage' };
    } catch {
      this.error = 'Equipment could not be created. Check unique asset and serial values.';
    } finally {
      this.saving = false;
    }
  }
}
