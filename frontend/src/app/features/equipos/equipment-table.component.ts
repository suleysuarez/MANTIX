import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

import { Equipment } from '../../core/equipment.service';

/** Dumb component: renders the catalog it is given. */
@Component({
  selector: 'app-equipment-table',
  standalone: true,
  template: `
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
  `,
  styles: [
    `.empty, .table-wrap { margin: 1.5rem 0; padding: 1.5rem; background: white; border: 1px solid #e2e8f0; border-radius: 10px; }
     .table-wrap { overflow-x: auto; } table { width: 100%; border-collapse: collapse; } th, td { padding: .75rem; text-align: left; border-bottom: 1px solid #e2e8f0; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentTableComponent {
  @Input() equipment: readonly Equipment[] = [];
  @Input() loading = false;
}
