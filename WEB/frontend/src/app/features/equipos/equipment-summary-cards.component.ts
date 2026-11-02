import { ChangeDetectionStrategy, Component, EventEmitter, Input, Output } from '@angular/core';

import { activeGroup, groupCount, groupFilter } from '../../core/equipment-status';
import { EquipmentSummary } from '../../core/equipment.service';

/**
 * Dumb component: cuatro tarjetas con los contadores del catálogo. Cada una es un
 * botón que emite el filtro de estado equivalente (cadena vacía = todo el catálogo).
 */
@Component({
  selector: 'app-equipment-summary-cards',
  standalone: true,
  template: `
    <section class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4" aria-label="Resumen del catálogo">
      <button type="button" (click)="filterChange.emit('')" [attr.aria-pressed]="active === 'all'"
        class="group rounded-2xl !border bg-white p-5 text-left shadow-[0_4px_20px_-2px_rgba(13,31,56,0.04)] transition-all hover:border-sky-300 hover:shadow-md"
        [class]="active === 'all' ? '!border-sky-400 ring-2 ring-sky-100' : '!border-slate-200/90'">
        <div class="mb-3 flex items-center justify-between">
          <span class="flex h-10 w-10 items-center justify-center rounded-xl bg-sky-50 text-brand-accentDeep transition-transform group-hover:scale-105">
            <span class="material-symbols-outlined text-[22px]">devices</span>
          </span>
          <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-600">Total</span>
        </div>
        <div class="text-3xl font-extrabold tracking-tight text-slate-900">{{ summary ? summary.total : '–' }}</div>
        <p class="mt-1 text-xs font-medium text-slate-500">Equipos registrados en inventario</p>
        <div class="mt-3 flex items-center justify-between !border-t !border-slate-100 pt-3 text-[11px] font-semibold text-sky-600">
          <span>Ver todo el catálogo</span>
          <span class="material-symbols-outlined text-[14px] transition-transform group-hover:translate-x-1">arrow_forward</span>
        </div>
      </button>

      <button type="button" (click)="filterChange.emit(operationalFilter)" [attr.aria-pressed]="active === 'operational'"
        class="group rounded-2xl !border bg-white p-5 text-left shadow-[0_4px_20px_-2px_rgba(13,31,56,0.04)] transition-all hover:border-emerald-300 hover:shadow-md"
        [class]="active === 'operational' ? '!border-emerald-400 ring-2 ring-emerald-100' : '!border-slate-200/90'">
        <div class="mb-3 flex items-center justify-between">
          <span class="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-50 text-emerald-600 transition-transform group-hover:scale-105">
            <span class="material-symbols-outlined text-[22px]">check_circle</span>
          </span>
          <span class="rounded-full !border !border-emerald-200 bg-emerald-50 px-2 py-0.5 text-xs font-semibold text-emerald-700">{{ rate }} tasa</span>
        </div>
        <div class="text-3xl font-extrabold tracking-tight text-slate-900">{{ summary ? operational : '–' }}</div>
        <p class="mt-1 text-xs font-medium text-slate-500">Operativos y en disponibilidad</p>
        <div class="mt-3 flex items-center justify-between !border-t !border-slate-100 pt-3 text-[11px] font-semibold text-emerald-600">
          <span>Filtrar operativos</span>
          <span class="material-symbols-outlined text-[14px]">filter_alt</span>
        </div>
      </button>

      <button type="button" (click)="filterChange.emit(maintenanceFilter)" [attr.aria-pressed]="active === 'maintenance'"
        class="group rounded-2xl !border bg-white p-5 text-left shadow-[0_4px_20px_-2px_rgba(13,31,56,0.04)] transition-all hover:border-brand-mustard hover:shadow-md"
        [class]="active === 'maintenance' ? '!border-brand-mustard ring-2 ring-amber-100' : '!border-slate-200/90'">
        <div class="mb-3 flex items-center justify-between">
          <span class="flex h-10 w-10 items-center justify-center rounded-xl bg-amber-50 text-brand-mustard transition-transform group-hover:scale-105">
            <span class="material-symbols-outlined text-[22px]">build</span>
          </span>
          <span class="rounded-full !border !border-amber-200 bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-700">En curso</span>
        </div>
        <div class="text-3xl font-extrabold tracking-tight text-slate-900">{{ summary ? maintenance : '–' }}</div>
        <p class="mt-1 text-xs font-medium text-slate-500">Bajo revisión o soporte técnico</p>
        <div class="mt-3 flex items-center justify-between !border-t !border-slate-100 pt-3 text-[11px] font-semibold text-amber-600">
          <span>Ver equipos en mantenimiento</span>
          <span class="material-symbols-outlined text-[14px] transition-transform group-hover:translate-x-1">arrow_forward</span>
        </div>
      </button>

      <button type="button" (click)="filterChange.emit(offlineFilter)" [attr.aria-pressed]="active === 'offline'"
        class="group rounded-2xl !border bg-white p-5 text-left shadow-[0_4px_20px_-2px_rgba(13,31,56,0.04)] transition-all hover:border-rose-300 hover:shadow-md"
        [class]="active === 'offline' ? '!border-rose-400 ring-2 ring-rose-100' : '!border-slate-200/90'">
        <div class="mb-3 flex items-center justify-between">
          <span class="flex h-10 w-10 items-center justify-center rounded-xl bg-rose-50 text-rose-600 transition-transform group-hover:scale-105">
            <span class="material-symbols-outlined text-[22px]">warning</span>
          </span>
          <span class="rounded-full !border !border-rose-200 bg-rose-50 px-2 py-0.5 text-xs font-semibold text-rose-700">Crítico</span>
        </div>
        <div class="text-3xl font-extrabold tracking-tight text-slate-900">{{ summary ? offline : '–' }}</div>
        <p class="mt-1 text-xs font-medium text-slate-500">Dados de baja, retirados o extraviados</p>
        <div class="mt-3 flex items-center justify-between !border-t !border-slate-100 pt-3 text-[11px] font-semibold text-rose-600">
          <span>Revisar estos equipos</span>
          <span class="material-symbols-outlined text-[14px] transition-transform group-hover:translate-x-1">arrow_forward</span>
        </div>
      </button>
    </section>
  `,
  host: { class: 'block' },
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentSummaryCardsComponent {
  @Input() summary: EquipmentSummary | null = null;
  /** Filtro de estado vigente, para resaltar la tarjeta correspondiente. */
  @Input() statusFilter = '';
  @Output() readonly filterChange = new EventEmitter<string>();

  readonly operationalFilter = groupFilter('operational');
  readonly maintenanceFilter = groupFilter('maintenance');
  readonly offlineFilter = groupFilter('offline');

  get active() {
    return activeGroup(this.statusFilter);
  }

  get operational(): number {
    return this.summary ? groupCount(this.summary.by_status, 'operational') : 0;
  }

  get maintenance(): number {
    return this.summary ? groupCount(this.summary.by_status, 'maintenance') : 0;
  }

  get offline(): number {
    return this.summary ? groupCount(this.summary.by_status, 'offline') : 0;
  }

  /** Porcentaje de equipos operativos sobre el total, con un decimal. */
  get rate(): string {
    const total = this.summary?.total ?? 0;
    return total === 0 ? '0%' : `${((this.operational / total) * 100).toFixed(1)}%`;
  }
}
