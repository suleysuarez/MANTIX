import {
  ChangeDetectionStrategy,
  Component,
  EventEmitter,
  Input,
  OnDestroy,
  OnInit,
  Output,
  signal,
} from '@angular/core';
import { Subject, Subscription, debounceTime } from 'rxjs';

import { EQUIPMENT_STATUSES, statusInfo } from '../../core/equipment-status';
import { EquipmentType } from '../../core/equipment.service';
import { EquipmentFilters, EquipmentView } from '../../core/equipment.store';

export const SORT_OPTIONS: readonly { value: string; label: string }[] = [
  { value: 'asset_tag', label: 'Código (A-Z)' },
  { value: '-created_at', label: 'Más recientes' },
  { value: 'brand', label: 'Marca (A-Z)' },
  { value: 'status', label: 'Estado' },
];

/** Búsqueda compacta y filtros desplegables para el catálogo de equipos. */
@Component({
  selector: 'app-equipment-toolbar',
  standalone: true,
  template: `
    <section aria-label="Herramientas del catálogo" class="relative flex w-full items-center gap-2 rounded-2xl !border !border-slate-200/80 bg-white p-3 shadow-sm">
      <div class="relative min-w-0 flex-1">
        <span class="material-symbols-outlined pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[19px] text-slate-400">search</span>
        <input type="search" [value]="filters.search" (input)="onSearch($any($event.target).value)" placeholder="Buscar equipo..." aria-label="Buscar equipos"
          class="w-full rounded-xl !border !border-slate-200 bg-slate-50/70 py-2.5 pl-10 pr-3 text-sm text-slate-700 transition-all placeholder:text-slate-400 focus:border-brand-accentDeep focus:bg-white focus:outline-none focus:ring-2 focus:ring-brand-accentDeep/20" />
      </div>
      <button type="button" (click)="filtersOpen.set(!filtersOpen())" [attr.aria-expanded]="filtersOpen()" aria-controls="equipment-filter-panel" aria-label="Filtros" title="Filtros"
        class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-brand-accentDeep/20 bg-brand-accentDeep px-0 text-white shadow-sm transition-colors hover:bg-brand-accentDeepDeep focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeepDeep">
        <span class="material-symbols-outlined text-[22px]" aria-hidden="true">filter_alt</span>
      </button>
      <div class="flex shrink-0 items-center rounded-xl !border !border-slate-200 bg-slate-100 p-1" role="group" aria-label="Tipo de vista">
        <button type="button" (click)="viewChange.emit('table')" [attr.aria-pressed]="view === 'table'" aria-label="Vista de tabla" title="Tabla"
          class="flex h-8 w-8 items-center justify-center rounded-lg transition-colors"
          [class]="view === 'table' ? 'bg-white !text-brand-accentDeepDeep shadow-sm' : 'bg-transparent !text-slate-500 hover:text-slate-800'">
          <span class="material-symbols-outlined text-[18px]">table_rows</span>
        </button>
        <button type="button" (click)="viewChange.emit('grid')" [attr.aria-pressed]="view === 'grid'" aria-label="Vista de cuadrícula" title="Cuadrícula"
          class="flex h-8 w-8 items-center justify-center rounded-lg transition-colors"
          [class]="view === 'grid' ? 'bg-white !text-brand-accentDeepDeep shadow-sm' : 'bg-transparent !text-slate-500 hover:text-slate-800'">
          <span class="material-symbols-outlined text-[18px]">grid_view</span>
        </button>
      </div>
      @if (filtersOpen()) {
        <div id="equipment-filter-panel" class="absolute right-3 top-full z-30 mt-2 grid w-[min(22rem,calc(100vw-2rem))] gap-3 rounded-xl border border-slate-200 bg-white p-4 shadow-xl" aria-label="Opciones de filtrado">
          <label class="grid gap-1.5 text-xs font-semibold text-slate-600">Categoría
            <select aria-label="Categoría" [value]="filters.typeId ?? ''" (change)="filtersChange.emit({ typeId: toNumber($any($event.target).value) })"
              class="w-full rounded-lg border border-slate-200 bg-slate-50 px-3 py-2.5 text-sm font-medium text-slate-700 focus:border-brand-accentDeep focus:outline-none focus:ring-2 focus:ring-brand-accentDeep/20">
              <option value="">Todas las categorías</option>
              @for (type of types; track type.id) { <option [value]="type.id">{{ type.name }}</option> }
            </select>
          </label>
          <label class="grid gap-1.5 text-xs font-semibold text-slate-600">Estado
            <select aria-label="Estado" [value]="filters.status" (change)="filtersChange.emit({ status: $any($event.target).value })"
              class="w-full rounded-lg border border-slate-200 bg-slate-50 px-3 py-2.5 text-sm font-medium text-slate-700 focus:border-brand-accentDeep focus:outline-none focus:ring-2 focus:ring-brand-accentDeep/20">
              <option value="">Todos los estados</option>
              @if (filters.status.includes(',')) { <option [value]="filters.status">Varios estados</option> }
              @for (status of statuses; track status) { <option [value]="status">{{ label(status) }}</option> }
            </select>
          </label>
          <label class="grid gap-1.5 text-xs font-semibold text-slate-600">Ordenar por
            <select aria-label="Ordenar por" [value]="sort" (change)="sortChange.emit($any($event.target).value)"
              class="w-full rounded-lg border border-slate-200 bg-slate-50 px-3 py-2.5 text-sm font-medium text-slate-700 focus:border-brand-accentDeep focus:outline-none focus:ring-2 focus:ring-brand-accentDeep/20">
              @for (option of sortOptions; track option.value) { <option [value]="option.value">{{ option.label }}</option> }
            </select>
          </label>
          <button type="button" (click)="filtersReset.emit(); filtersOpen.set(false)"
            class="flex items-center justify-center gap-2 rounded-lg border border-slate-200 px-3 py-2 text-xs font-semibold text-slate-600 transition-colors hover:bg-slate-50">
            <span class="material-symbols-outlined text-[17px]">restart_alt</span>Restablecer filtros
          </button>
        </div>
      }
    </section>
  `,
  host: { class: 'block w-full' },
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentToolbarComponent implements OnInit, OnDestroy {
  @Input() filters!: EquipmentFilters;
  @Input() sort = 'asset_tag';
  @Input() view: EquipmentView = 'table';
  @Input() types: readonly EquipmentType[] = [];

  @Output() readonly filtersChange = new EventEmitter<Partial<EquipmentFilters>>();
  @Output() readonly sortChange = new EventEmitter<string>();
  @Output() readonly viewChange = new EventEmitter<EquipmentView>();
  @Output() readonly filtersReset = new EventEmitter<void>();

  readonly statuses = EQUIPMENT_STATUSES;
  readonly sortOptions = SORT_OPTIONS;
  readonly filtersOpen = signal(false);

  private readonly typed = new Subject<string>();
  private subscription?: Subscription;

  ngOnInit(): void {
    this.subscription = this.typed
      .pipe(debounceTime(300))
      .subscribe((search) => this.filtersChange.emit({ search }));
  }

  ngOnDestroy(): void {
    this.subscription?.unsubscribe();
  }

  onSearch(value: string): void {
    this.typed.next(value);
  }

  label(status: string): string {
    return statusInfo(status).label;
  }

  toNumber(value: string): number | null {
    return value ? Number(value) : null;
  }

}
