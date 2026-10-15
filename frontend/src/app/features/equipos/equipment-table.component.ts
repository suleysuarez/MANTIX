import { ChangeDetectionStrategy, Component, EventEmitter, Input, Output } from '@angular/core';

import {
  categoryIcon,
  formatDate,
  statusBadgeClasses,
  statusDotClasses,
  statusInfo,
} from '../../core/equipment-status';
import { Equipment } from '../../core/equipment.service';

/** Dumb component: tabla del catálogo. Emite qué equipo se quiere ver o editar. */
@Component({
  selector: 'app-equipment-table',
  standalone: true,
  template: `
    <div class="overflow-x-auto">
      <table class="w-full !border-collapse text-left text-xs">
        <caption class="sr-only">Catálogo de equipos</caption>
        <thead class="!border-b !border-slate-200 bg-slate-50/75 text-[11px] font-semibold uppercase tracking-wider text-slate-500">
          <tr>
            <th scope="col" class="py-4 pl-6 pr-4">Equipo y modelo</th>
            <th scope="col" class="px-3 py-4">Código</th>
            <th scope="col" class="px-3 py-4">Categoría</th>
            <th scope="col" class="px-4 py-4">Ubicación</th>
            <th scope="col" class="px-4 py-4">Estado</th>
            <th scope="col" class="px-4 py-4">Último mantenimiento</th>
            <th scope="col" class="py-4 pl-4 pr-6 text-right">Acciones</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100 text-slate-700">
          @if (loading && equipment.length === 0) {
            @for (row of skeleton; track row) {
              <tr aria-hidden="true">
                <td colspan="7" class="px-6 py-4"><div class="h-10 animate-pulse rounded-xl bg-slate-100"></div></td>
              </tr>
            }
          } @else if (equipment.length === 0) {
            <tr>
              <td colspan="7" class="px-6 py-14 text-center">
                <span class="material-symbols-outlined text-[40px] text-slate-300">inventory_2</span>
                <p class="mt-2 text-sm font-semibold text-slate-700">
                  {{ filtered ? 'Ningún equipo coincide con los filtros.' : 'Aún no hay equipos registrados.' }}
                </p>
                <p class="text-xs text-slate-400">
                  {{ filtered ? 'Prueba con otra búsqueda o restablece los filtros.' : 'Registra el primero con «Nuevo equipo».' }}
                </p>
              </td>
            </tr>
          } @else {
            @for (item of equipment; track item.id) {
              <tr class="group transition-colors hover:bg-slate-50/80" [class.opacity-60]="loading">
                <td class="py-4 pl-6 pr-4">
                  <div class="flex items-center gap-3">
                    <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-sky-50 text-sky-700">
                      <span class="material-symbols-outlined text-[20px]">{{ icon(item) }}</span>
                    </span>
                    <div class="min-w-0">
                      <button type="button" (click)="view.emit(item)"
                        class="bg-transparent block max-w-[260px] truncate text-left !font-bold !text-slate-900 transition-colors hover:text-sky-700 focus-visible:underline">
                        {{ item.brand }} {{ item.model }}
                      </button>
                      <span class="block max-w-[260px] truncate text-[11px] text-slate-400">
                        {{ item.description || ('Serie: ' + (item.serial_number || 'sin registrar')) }}
                      </span>
                    </div>
                  </div>
                </td>
                <td class="px-3 py-4">
                  <span class="rounded !border !border-slate-200 bg-slate-100 px-2 py-1 font-mono text-[11px] font-semibold text-slate-700">{{ item.asset_tag }}</span>
                </td>
                <td class="px-3 py-4">
                  <span class="rounded-full !border !border-sky-100 bg-sky-50 px-2.5 py-1 text-[11px] font-medium text-sky-700">{{ item.equipment_type.name }}</span>
                </td>
                <td class="px-4 py-4">
                  <div class="flex items-center gap-1.5 text-slate-600">
                    <span class="material-symbols-outlined text-[16px] text-slate-300">location_on</span>
                    <span>{{ item.current_location?.name || 'Sin ubicación' }}</span>
                  </div>
                </td>
                <td class="px-4 py-4">
                  <span class="inline-flex items-center gap-1.5 rounded-full !border px-2.5 py-1 text-[11px] font-semibold" [class]="badge(item.status)">
                    <span class="h-1.5 w-1.5 rounded-full" [class]="dot(item.status)"></span>{{ label(item.status) }}
                  </span>
                </td>
                <td class="px-4 py-4">
                  @if (item.last_maintenance; as last) {
                    <div class="font-medium text-slate-800">{{ date(last.performed_at) }}</div>
                    <div class="text-[10px] text-slate-400">Por {{ last.technician_name }}</div>
                  } @else {
                    <span class="text-slate-400">Sin registros</span>
                  }
                </td>
                <td class="whitespace-nowrap py-4 pl-4 pr-6 text-right">
                  <div class="inline-flex items-center gap-1">
                    <button type="button" (click)="view.emit(item)" title="Ver detalle" [attr.aria-label]="'Ver detalle de ' + item.asset_tag"
                      class="bg-transparent flex h-8 w-8 items-center justify-center rounded-lg !text-slate-400 transition-colors hover:bg-sky-50 hover:text-sky-600">
                      <span class="material-symbols-outlined text-[18px]">visibility</span>
                    </button>
                    @if (canManage) {
                      <button type="button" (click)="edit.emit(item)" title="Editar" [attr.aria-label]="'Editar ' + item.asset_tag"
                        class="bg-transparent flex h-8 w-8 items-center justify-center rounded-lg !text-slate-400 transition-colors hover:bg-slate-100 hover:text-slate-700">
                        <span class="material-symbols-outlined text-[18px]">edit</span>
                      </button>
                    }
                  </div>
                </td>
              </tr>
            }
          }
        </tbody>
      </table>
    </div>
  `,
  host: { class: 'block' },
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentTableComponent {
  @Input() equipment: readonly Equipment[] = [];
  @Input() loading = false;
  @Input() filtered = false;
  @Input() canManage = false;
  @Output() readonly view = new EventEmitter<Equipment>();
  @Output() readonly edit = new EventEmitter<Equipment>();

  readonly skeleton = [1, 2, 3, 4, 5];

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
