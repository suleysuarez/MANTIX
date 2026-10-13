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
import { EquipmentType, LocationItem, ReportFormat } from '../../core/equipment.service';
import { EquipmentFilters, EquipmentView } from '../../core/equipment.store';

export const SORT_OPTIONS: readonly { value: string; label: string }[] = [
  { value: 'asset_tag', label: 'Código (A-Z)' },
  { value: '-created_at', label: 'Más recientes' },
  { value: 'brand', label: 'Marca (A-Z)' },
  { value: 'status', label: 'Estado' },
];

/** Dumb component: búsqueda con debounce, filtros, orden, cambio de vista y exportación. */
@Component({
  selector: 'app-equipment-toolbar',
  standalone: true,
  template: `
    <section aria-label="Filtros del catálogo"
      class="flex flex-col items-stretch justify-between gap-4 rounded-2xl !border !border-slate-200/80 bg-white p-4 shadow-sm lg:flex-row lg:items-center">
      <div class="flex flex-1 flex-wrap items-center gap-3">
        <div class="relative min-w-[240px] flex-1">
          <span class="material-symbols-outlined pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[18px] text-slate-400">search</span>
          <input type="search" [value]="filters.search" (input)="onSearch($any($event.target).value)"
            placeholder="Buscar por código, serie, marca o modelo…" aria-label="Buscar equipos"
            class="w-full rounded-xl !border !border-slate-200 bg-slate-50/70 py-2.5 pl-10 pr-4 text-xs transition-all focus:border-sky-500 focus:bg-white focus:outline-none focus:ring-2 focus:ring-sky-500/20" />
        </div>

        <select aria-label="Categoría" [value]="filters.typeId ?? ''"
          (change)="filtersChange.emit({ typeId: toNumber($any($event.target).value) })"
          class="rounded-xl !border !border-slate-200 bg-slate-50/70 px-3 py-2.5 text-xs font-medium text-slate-700 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-500/20">
          <option value="">Todas las categorías</option>
          @for (type of types; track type.id) {
            <option [value]="type.id" [selected]="type.id === filters.typeId">{{ type.name }}</option>
          }
        </select>

        <select aria-label="Estado" (change)="filtersChange.emit({ status: $any($event.target).value })"
          class="rounded-xl !border !border-slate-200 bg-slate-50/70 px-3 py-2.5 text-xs font-medium text-slate-700 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-500/20">
          <option value="" [selected]="!filters.status">Todos los estados</option>
          @if (filters.status.includes(',')) {
            <option [value]="filters.status" selected>Varios estados</option>
          }
          @for (status of statuses; track status) {
            <option [value]="status" [selected]="status === filters.status">{{ label(status) }}</option>
          }
        </select>

        <select aria-label="Ubicación" (change)="filtersChange.emit({ locationId: toNumber($any($event.target).value) })"
          class="hidden rounded-xl !border !border-slate-200 bg-slate-50/70 px-3 py-2.5 text-xs font-medium text-slate-700 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-500/20 xl:block">
          <option value="">Todas las ubicaciones</option>
          @for (location of locations; track location.id) {
            <option [value]="location.id" [selected]="location.id === filters.locationId">{{ location.name }}</option>
          }
        </select>

        <select aria-label="Ordenar por" (change)="sortChange.emit($any($event.target).value)"
          class="hidden rounded-xl !border !border-slate-200 bg-slate-50/70 px-3 py-2.5 text-xs font-medium text-slate-700 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-500/20 2xl:block">
          @for (option of sortOptions; track option.value) {
            <option [value]="option.value" [selected]="option.value === sort">{{ option.label }}</option>
          }
        </select>

        <button type="button" (click)="filtersReset.emit()" title="Restablecer filtros" aria-label="Restablecer filtros"
          class="bg-transparent rounded-xl p-2.5 !text-slate-500 transition-colors hover:bg-slate-100 hover:text-slate-800">
          <span class="material-symbols-outlined text-[18px]">restart_alt</span>
        </button>
      </div>

      <div class="flex items-center gap-2 self-end lg:self-auto">
        <div class="flex items-center rounded-xl !border !border-slate-200 bg-slate-100 p-1" role="group" aria-label="Tipo de vista">
          <button type="button" (click)="viewChange.emit('table')" [attr.aria-pressed]="view === 'table'"
            class="flex items-center gap-1.5 rounded-lg px-3 py-1.5 !text-xs transition-colors"
            [class]="view === 'table' ? 'bg-white !font-semibold !text-slate-800 shadow-sm' : 'bg-transparent !font-medium !text-slate-500 hover:text-slate-800'">
            <span class="material-symbols-outlined text-[16px]" [class]="view === 'table' ? 'text-sky-600' : ''">table_rows</span>
            <span class="hidden sm:inline">Tabla</span>
          </button>
          <button type="button" (click)="viewChange.emit('grid')" [attr.aria-pressed]="view === 'grid'"
            class="flex items-center gap-1.5 rounded-lg px-3 py-1.5 !text-xs transition-colors"
            [class]="view === 'grid' ? 'bg-white !font-semibold !text-slate-800 shadow-sm' : 'bg-transparent !font-medium !text-slate-500 hover:text-slate-800'">
            <span class="material-symbols-outlined text-[16px]" [class]="view === 'grid' ? 'text-sky-600' : ''">grid_view</span>
            <span class="hidden sm:inline">Cuadrícula</span>
          </button>
        </div>

        @if (canExport) {
          <div class="relative">
            <button type="button" (click)="menuOpen.set(!menuOpen())" [disabled]="exporting"
              [attr.aria-expanded]="menuOpen()" aria-haspopup="menu"
              class="flex items-center gap-2 rounded-xl !border !border-slate-200 bg-white px-3.5 py-2 !text-xs !font-semibold !text-slate-700 shadow-sm transition-colors hover:bg-slate-50 disabled:opacity-60">
              <span class="material-symbols-outlined text-[18px] text-slate-400">download</span>
              <span>{{ exporting ? 'Generando…' : 'Exportar' }}</span>
            </button>
            @if (menuOpen()) {
              <div class="fixed inset-0 z-30" (click)="menuOpen.set(false)" aria-hidden="true"></div>
              <div role="menu" class="absolute right-0 top-full z-40 mt-2 w-44 overflow-hidden rounded-xl !border !border-slate-200 bg-white py-1 shadow-lg">
                @for (format of formats; track format.value) {
                  <button type="button" role="menuitem" (click)="choose(format.value)"
                    class="bg-transparent flex w-full items-center gap-2 px-3 py-2 text-left !text-xs !font-medium !text-slate-700 hover:bg-slate-50">
                    <span class="material-symbols-outlined text-[18px] text-slate-400">{{ format.icon }}</span>{{ format.label }}
                  </button>
                }
              </div>
            }
          </div>
        }
      </div>
    </section>
  `,
  host: { class: 'block' },
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentToolbarComponent implements OnInit, OnDestroy {
  @Input() filters!: EquipmentFilters;
  @Input() sort = 'asset_tag';
  @Input() view: EquipmentView = 'table';
  @Input() types: readonly EquipmentType[] = [];
  @Input() locations: readonly LocationItem[] = [];
  @Input() canExport = false;
  @Input() exporting = false;

  @Output() readonly filtersChange = new EventEmitter<Partial<EquipmentFilters>>();
  @Output() readonly sortChange = new EventEmitter<string>();
  @Output() readonly viewChange = new EventEmitter<EquipmentView>();
  @Output() readonly filtersReset = new EventEmitter<void>();
  @Output() readonly exportRequested = new EventEmitter<ReportFormat>();

  readonly statuses = EQUIPMENT_STATUSES;
  readonly sortOptions = SORT_OPTIONS;
  readonly formats: readonly { value: ReportFormat; label: string; icon: string }[] = [
    { value: 'xlsx', label: 'Excel (.xlsx)', icon: 'table' },
    { value: 'csv', label: 'CSV (.csv)', icon: 'csv' },
    { value: 'pdf', label: 'PDF (.pdf)', icon: 'picture_as_pdf' },
  ];
  readonly menuOpen = signal(false);

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

  choose(format: ReportFormat): void {
    this.menuOpen.set(false);
    this.exportRequested.emit(format);
  }
}
