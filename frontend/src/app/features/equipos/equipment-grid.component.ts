import { ChangeDetectionStrategy, Component, EventEmitter, Input, Output } from '@angular/core';

import {
  categoryIcon,
  formatDate,
  statusBadgeClasses,
  statusDotClasses,
  statusInfo,
} from '../../core/equipment-status';
import { Equipment } from '../../core/equipment.service';

/** Dumb component: vista en cuadrícula del catálogo (mismo contrato que la tabla). */
@Component({
  selector: 'app-equipment-grid',
  standalone: true,
  template: `
    @if (loading && equipment.length === 0) {
      <div class="grid gap-4 p-6 sm:grid-cols-2 xl:grid-cols-3" aria-hidden="true">
        @for (card of skeleton; track card) {
          <div class="h-44 animate-pulse rounded-2xl bg-slate-100"></div>
        }
      </div>
    } @else if (equipment.length === 0) {
      <div class="px-6 py-14 text-center">
        <span class="material-symbols-outlined text-[40px] text-slate-300">inventory_2</span>
        <p class="mt-2 text-sm font-semibold text-slate-700">
          {{ filtered ? 'Ningún equipo coincide con los filtros.' : 'Aún no hay equipos registrados.' }}
        </p>
      </div>
    } @else {
      <ul class="m-0 list-none grid gap-4 p-6 sm:grid-cols-2 xl:grid-cols-3" [class.opacity-60]="loading">
        @for (item of equipment; track item.id) {
          <li class="flex flex-col rounded-2xl !border !border-slate-200 bg-white p-4 transition-shadow hover:shadow-md">
            <div class="flex items-start justify-between gap-3">
              <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-sky-50 text-sky-700">
                <span class="material-symbols-outlined text-[22px]">{{ icon(item) }}</span>
              </span>
              <span class="inline-flex items-center gap-1.5 rounded-full !border px-2.5 py-1 text-[11px] font-semibold" [class]="badge(item.status)">
                <span class="h-1.5 w-1.5 rounded-full" [class]="dot(item.status)"></span>{{ label(item.status) }}
              </span>
            </div>
            <button type="button" (click)="view.emit(item)"
              class="bg-transparent mt-3 truncate text-left !text-sm !font-bold !text-slate-900 hover:text-sky-700 focus-visible:underline">
              {{ item.brand }} {{ item.model }}
            </button>
            <span class="mt-1 w-fit rounded !border !border-slate-200 bg-slate-100 px-2 py-0.5 font-mono text-[11px] font-semibold text-slate-700">{{ item.asset_tag }}</span>
            <dl class="mt-3 space-y-1.5 text-xs text-slate-600">
              <div class="flex items-center gap-1.5">
                <dt class="sr-only">Ubicación</dt>
                <span class="material-symbols-outlined text-[16px] text-slate-300">location_on</span>
                <dd class="ml-0">{{ item.current_location?.name || 'Sin ubicación' }}</dd>
              </div>
              <div class="flex items-center gap-1.5">
                <dt class="sr-only">Custodio</dt>
                <span class="material-symbols-outlined text-[16px] text-slate-300">person</span>
                <dd class="ml-0">{{ item.current_custodian?.full_name || 'Sin custodio' }}</dd>
              </div>
              <div class="flex items-center gap-1.5">
                <dt class="sr-only">Último mantenimiento</dt>
                <span class="material-symbols-outlined text-[16px] text-slate-300">build</span>
                <dd class="ml-0">{{ item.last_maintenance ? date(item.last_maintenance.performed_at) : 'Sin registros' }}</dd>
              </div>
            </dl>
            <div class="mt-4 flex items-center justify-between !border-t !border-slate-100 pt-3">
              <span class="rounded-full !border !border-sky-100 bg-sky-50 px-2.5 py-1 text-[11px] font-medium text-sky-700">{{ item.equipment_type.name }}</span>
              <div class="flex items-center gap-1">
                <button type="button" (click)="view.emit(item)" title="Ver detalle" [attr.aria-label]="'Ver detalle de ' + item.asset_tag"
                  class="bg-transparent flex h-8 w-8 items-center justify-center rounded-lg !text-slate-400 hover:bg-sky-50 hover:text-sky-600">
                  <span class="material-symbols-outlined text-[18px]">visibility</span>
                </button>
                @if (canManage) {
                  <button type="button" (click)="edit.emit(item)" title="Editar" [attr.aria-label]="'Editar ' + item.asset_tag"
                    class="bg-transparent flex h-8 w-8 items-center justify-center rounded-lg !text-slate-400 hover:bg-slate-100 hover:text-slate-700">
                    <span class="material-symbols-outlined text-[18px]">edit</span>
                  </button>
                }
              </div>
            </div>
          </li>
        }
      </ul>
    }
  `,
  host: { class: 'block' },
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentGridComponent {
  @Input() equipment: readonly Equipment[] = [];
  @Input() loading = false;
  @Input() filtered = false;
  @Input() canManage = false;
  @Output() readonly view = new EventEmitter<Equipment>();
  @Output() readonly edit = new EventEmitter<Equipment>();

  readonly skeleton = [1, 2, 3, 4, 5, 6];

  icon(item: Equipment): string {
    return categoryIcon(item.equipment_type.code);
  }

  label(status: string): string {
    return statusInfo(status).label;
  }

  badge(status: string): string {
    return statusBadgeClasses(status);
  }

  dot(status: string): string {
    return statusDotClasses(status);
  }

  date(value: string): string {
    return formatDate(value);
  }
}
