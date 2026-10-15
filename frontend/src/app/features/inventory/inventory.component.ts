import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Subject, debounceTime, distinctUntilChanged } from 'rxjs';

import { Period } from '../../core/dashboard-kpis.service';
import { saveBlob, reportFilename } from '../../core/download';
import { InventoryItem, MovementKind } from '../../core/inventory.service';
import { InventoryState, InventoryStore, PAGE_SIZE } from '../../core/inventory.store';
import { LocalProfileService } from '../../core/local-profile.service';
import { ToastService } from '../../core/toast.service';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { ImportModalComponent } from './import-modal.component';
import { InventoryInsightsComponent } from './inventory-insights.component';
import { CATEGORIES, STATUS_META, categoryIcon, categoryLabel, itemsToCsv, minMarker, money } from './inventory-ui';
import { ItemDetailPanelComponent } from './item-detail-panel.component';
import { ItemFormModalComponent } from './item-form-modal.component';
import { MovementModalComponent } from './movement-modal.component';

const PERIODS: { id: Period; label: string }[] = [
  { id: '7d', label: '7 días' },
  { id: '30d', label: '30 días' },
  { id: '12m', label: '12 meses' },
];
const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface ${FOCUS}`;

type Modal = { kind: 'create' } | { kind: 'edit' } | { kind: 'move'; move: MovementKind; item: InventoryItem } | { kind: 'import' } | null;

/** Inventario: tarjetas con nivel de stock o tabla densa, alertas de reposición y pulso a la derecha. */
@Component({
  selector: 'app-inventory',
  standalone: true,
  imports: [AsyncPipe, InventoryInsightsComponent, ItemDetailPanelComponent, ItemFormModalComponent, MovementModalComponent, ImportModalComponent, ToastHostComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (vm$ | async; as vm) {
      <div class="space-y-4">
        <!-- Encabezado con ilustración -->
        <header class="relative overflow-hidden rounded-2xl bg-gradient-to-r from-brand-sidebar to-primary-container px-6 py-6 md:px-8">
          <div class="relative z-10 flex flex-col gap-4 md:max-w-[58%]">
            <span class="glass inline-flex w-fit items-center gap-2 rounded-full px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-brand-accentDeep">
              <span class="h-2 w-2 rounded-full bg-brand-mustard"></span> Repuestos y consumibles
            </span>
            <h1 class="text-[26px] font-extrabold uppercase leading-tight tracking-tight text-white">Inventario <span class="text-brand-accentLight">al día</span></h1>
            <p class="max-w-xl text-[14px] leading-relaxed text-brand-grey">Controla qué hay, qué se gasta en cada trabajo y qué toca reponer antes de quedarte sin stock.</p>
            <div class="flex flex-wrap items-center gap-3">
              @if (canManage()) {
                <button type="button" (click)="modal.set({ kind: 'create' })" class="glass-btn flex items-center gap-1.5 rounded-xl px-5 py-2.5 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white">
                  <span class="material-symbols-outlined text-[20px]" aria-hidden="true">add</span> Nuevo ítem
                </button>
                <button type="button" (click)="modal.set({ kind: 'import' })" class="glass flex items-center gap-1.5 rounded-xl bg-transparent px-4 py-2.5 text-[13px] font-bold !text-brand-accentDeep transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white">
                  <span class="material-symbols-outlined text-[18px]" aria-hidden="true">upload_file</span> Importar
                </button>
              }
              <div class="glass flex rounded-full p-0.5" role="group" aria-label="Periodo de las métricas">
                @for (p of periods; track p.id) {
                  <button type="button" (click)="store.setPeriod(p.id)" [attr.aria-pressed]="vm.period === p.id"
                    class="rounded-full px-3 py-1 text-[12px] font-semibold transition-colors active:scale-95"
                    [class]="focus + (vm.period === p.id ? ' bg-brand-sidebar !text-white' : ' bg-transparent !text-brand-accentDeep hover:bg-surface-container')">{{ p.label }}</button>
                }
              </div>
            </div>
          </div>
          <!-- Ilustración animada; con «reducir movimiento» se queda en el primer fotograma. -->
          <div class="pointer-events-none absolute inset-y-4 right-6 hidden aspect-video overflow-hidden rounded-2xl bg-surface-container-lowest shadow-lg lg:block" aria-hidden="true">
            <video class="h-full w-full object-cover" src="assets/videos/inventory.mp4" poster="assets/videos/inventario-poster.jpg"
              [muted]="true" playsinline preload="auto" [loop]="!reduceMotion" [autoplay]="!reduceMotion"></video>
          </div>
        </header>

        <!-- Alertas de reposición -->
        @if (vm.overview?.reorder?.length) {
          <section class="glass rounded-2xl p-3" aria-label="Alertas de reposición">
            <h2 class="flex items-center gap-2 px-1 text-[12px] font-bold uppercase tracking-wider text-on-secondary-fixed-variant">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">notification_important</span> Reponer ({{ vm.overview!.reorder.length }})
            </h2>
            <ul class="mt-2 flex gap-2 overflow-x-auto pb-1">
              @for (r of vm.overview!.reorder; track r.item_id) {
                <li class="shrink-0">
                  <button type="button" (click)="store.select(r.item_id)"
                    [class]="focus + ' flex flex-col rounded-xl px-3 py-2 text-left transition-colors ' + (r.stock === 0 ? 'bg-error-container hover:brightness-95' : 'bg-secondary-fixed hover:brightness-95')">
                    <span class="max-w-[12rem] truncate text-[12px] font-bold" [class]="r.stock === 0 ? 'text-on-error-container' : 'text-on-secondary-fixed'">{{ r.name }}</span>
                    <span class="text-[11px]" [class]="r.stock === 0 ? 'text-on-error-container' : 'text-on-secondary-fixed'">{{ r.stock }} de mín. {{ r.min_stock }} · pedir {{ r.suggested_order }}</span>
                  </button>
                </li>
              }
            </ul>
          </section>
        }

        <!-- Barra de filtros (cristal) -->
        <form class="glass grid grid-cols-1 gap-3 rounded-2xl p-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,1fr)_9rem_9rem_10rem_auto]" role="search" aria-label="Filtros del inventario" (submit)="$event.preventDefault()">
          <div>
            <label for="inv-search" class="sr-only">Buscar ítem</label>
            <input id="inv-search" type="search" [class]="field" placeholder="Buscar por SKU, nombre, proveedor o ubicación" maxlength="100" [value]="vm.filters.search" (input)="search$.next($any($event.target).value)" />
          </div>
          <div>
            <label for="inv-category" class="sr-only">Categoría</label>
            <select id="inv-category" [class]="field" (change)="store.setFilters({ category: $any($event.target).value })">
              <option value="" [selected]="!vm.filters.category">Todas las categorías</option>
              @for (c of categories; track c.code) { <option [value]="c.code" [selected]="vm.filters.category === c.code">{{ c.label }}</option> }
            </select>
          </div>
          <div>
            <label for="inv-status" class="sr-only">Estado</label>
            <select id="inv-status" [class]="field" (change)="store.setFilters({ status: $any($event.target).value })">
              <option value="" [selected]="!vm.filters.status">Todo el stock</option>
              <option value="low" [selected]="vm.filters.status === 'low'">Bajo mínimo</option>
              <option value="out" [selected]="vm.filters.status === 'out'">Agotados</option>
              <option value="ok" [selected]="vm.filters.status === 'ok'">En stock</option>
              <option value="stale" [selected]="vm.filters.status === 'stale'">Sin movimiento 90 d</option>
              <option value="inactive" [selected]="vm.filters.status === 'inactive'">Inactivos</option>
            </select>
          </div>
          <div>
            <label for="inv-sort" class="sr-only">Orden</label>
            <select id="inv-sort" [class]="field" (change)="store.setFilters({ sort: $any($event.target).value })">
              @for (s of sorts; track s.value) { <option [value]="s.value" [selected]="vm.filters.sort === s.value">{{ s.label }}</option> }
            </select>
          </div>
          <div class="flex items-center gap-1">
            <div class="flex rounded-full bg-surface-container p-0.5" role="group" aria-label="Vista">
              <button type="button" (click)="store.setView('grid')" [attr.aria-pressed]="vm.view === 'grid'" aria-label="Tarjetas"
                [class]="focus + ' flex h-8 w-9 items-center justify-center rounded-full ' + (vm.view === 'grid' ? 'bg-brand-sidebar !text-white' : 'bg-transparent !text-brand-accentDeep')"><span class="material-symbols-outlined text-[18px]" aria-hidden="true">grid_view</span></button>
              <button type="button" (click)="store.setView('table')" [attr.aria-pressed]="vm.view === 'table'" aria-label="Tabla"
                [class]="focus + ' flex h-8 w-9 items-center justify-center rounded-full ' + (vm.view === 'table' ? 'bg-brand-sidebar !text-white' : 'bg-transparent !text-brand-accentDeep')"><span class="material-symbols-outlined text-[18px]" aria-hidden="true">table_rows</span></button>
            </div>
            <button type="button" (click)="exportCsv()" [disabled]="vm.total === 0" aria-label="Exportar CSV" title="Exportar los ítems filtrados a CSV"
              [class]="focus + ' flex h-8 w-9 items-center justify-center rounded-full bg-transparent !text-brand-accentDeep hover:bg-surface-container-high disabled:opacity-40'"><span class="material-symbols-outlined text-[18px]" aria-hidden="true">file_download</span></button>
            @if (hasFilters(vm)) {
              <button type="button" (click)="store.clearFilters()" [class]="focus + ' rounded-lg bg-transparent px-2 py-1 text-[12px] font-semibold !text-brand-accentDeep hover:bg-surface-container'">Limpiar</button>
            }
          </div>
        </form>

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <section class="min-w-0 space-y-3" aria-label="Ítems" [attr.aria-busy]="vm.loading">
            @if (vm.error) {
              <p role="alert" class="flex flex-wrap items-center gap-3 rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">
                {{ vm.error }}
                <button type="button" (click)="store.load()" class="bg-transparent p-0 font-bold underline !text-on-error-container">Reintentar</button>
              </p>
            }

            @if (vm.items.length > 0) {
              @if (vm.view === 'grid') {
                <ul class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3" [class.opacity-60]="vm.loading">
                  @for (item of vm.items; track item.id) {
                    <li class="flex flex-col rounded-2xl border bg-surface-container-lowest p-3 shadow-sm transition-shadow hover:shadow-md motion-reduce:transition-none"
                      [class]="vm.selectedId === item.id ? 'border-brand-accentDeep ring-2 ring-brand-accentDeep/30' : 'border-brand-grey'">
                      <button type="button" (click)="store.select(item.id)" [attr.aria-label]="'Abrir ' + item.name" [class]="focus + ' flex flex-1 flex-col bg-transparent p-0 text-left'">
                        <span class="flex items-start justify-between gap-2">
                          <span class="flex min-w-0 items-center gap-2">
                            <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-brand-accentLight/60 text-brand-accentDeep"><span class="material-symbols-outlined text-[20px]" aria-hidden="true">{{ icon(item.category) }}</span></span>
                            <span class="min-w-0">
                              <span class="block truncate text-[13px] font-semibold text-on-surface">{{ item.name }}</span>
                              <span class="block truncate font-mono text-[11px] text-on-surface-variant">{{ item.sku }}</span>
                            </span>
                          </span>
                          <span class="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="item.is_active ? meta[item.status].chip : 'bg-surface-container text-on-surface-variant'">{{ item.is_active ? meta[item.status].label : 'Inactivo' }}</span>
                        </span>
                        <span class="mt-3 flex items-baseline justify-between text-[12px]">
                          <span class="text-on-surface-variant">Stock</span>
                          <span><strong class="text-[18px] text-on-surface">{{ item.stock }}</strong> <span class="text-on-surface-variant">{{ item.unit }}</span></span>
                        </span>
                        <span class="relative mt-1 block h-2.5 overflow-hidden rounded-full bg-surface-container" role="img"
                          [attr.aria-label]="'Nivel de stock ' + item.level_pct + '%, mínimo ' + item.min_stock">
                          <span class="block h-full rounded-full" [class]="meta[item.status].bar" [style.width.%]="item.level_pct"></span>
                          @if (marker(item); as m) { <span class="absolute inset-y-0 w-0.5 bg-on-surface" [style.left.%]="m"></span> }
                        </span>
                        <span class="mt-1 flex justify-between text-[11px] text-on-surface-variant">
                          <span>mín. {{ item.min_stock }}{{ item.max_stock !== null ? ' · máx. ' + item.max_stock : '' }}</span>
                          <span>{{ fmt(item.stock_value) }}</span>
                        </span>
                      </button>
                      @if (item.is_active && (canConsume() || canManage())) {
                        <div class="mt-3 flex gap-2 border-t border-brand-grey/60 pt-2">
                          @if (canConsume()) {
                            <button type="button" (click)="openMove(item, 'out')" [disabled]="item.stock === 0" [class]="quick">Consumir</button>
                          }
                          @if (canManage()) {
                            <button type="button" (click)="openMove(item, 'in')" [class]="quick">Entrada</button>
                          }
                        </div>
                      }
                    </li>
                  }
                </ul>
              } @else {
                <div class="overflow-hidden rounded-2xl border border-brand-grey bg-surface-container-lowest">
                  <div class="overflow-x-auto">
                    <table class="w-full min-w-[720px] border-collapse text-left text-[12px]">
                      <caption class="sr-only">Ítems de inventario</caption>
                      <thead>
                        <tr class="border-b border-brand-grey bg-surface-container-low text-[11px] uppercase tracking-wider text-on-surface-variant">
                          <th scope="col" class="px-3 py-2" [attr.aria-sort]="ariaSort(vm, 'name')"><button type="button" (click)="sortBy(vm, 'name')" [class]="sortButton">Ítem {{ arrow(vm, 'name') }}</button></th>
                          <th scope="col" class="px-3 py-2 font-bold">Categoría</th>
                          <th scope="col" class="px-3 py-2 text-right" [attr.aria-sort]="ariaSort(vm, 'stock')"><button type="button" (click)="sortBy(vm, 'stock')" [class]="sortButton">Stock {{ arrow(vm, 'stock') }}</button></th>
                          <th scope="col" class="px-3 py-2 text-right font-bold">Mín / Máx</th>
                          <th scope="col" class="px-3 py-2 text-right" [attr.aria-sort]="ariaSort(vm, 'stock_value')"><button type="button" (click)="sortBy(vm, 'stock_value')" [class]="sortButton">Valor {{ arrow(vm, 'stock_value') }}</button></th>
                          <th scope="col" class="px-3 py-2 font-bold">Estado</th>
                        </tr>
                      </thead>
                      <tbody [class.opacity-60]="vm.loading">
                        @for (item of vm.items; track item.id) {
                          <tr class="cursor-pointer border-b border-brand-grey/60 hover:bg-surface-container-low" (click)="store.select(item.id)">
                            <th scope="row" class="px-3 py-2 font-normal">
                              <button type="button" (click)="store.select(item.id); $event.stopPropagation()" [class]="focus + ' bg-transparent p-0 text-left'">
                                <span class="block font-semibold text-on-surface">{{ item.name }}</span><span class="block font-mono text-[11px] text-on-surface-variant">{{ item.sku }}</span>
                              </button>
                            </th>
                            <td class="px-3 py-2 text-on-surface">{{ categoryName(item.category) }}</td>
                            <td class="px-3 py-2 text-right font-semibold text-on-surface">{{ item.stock }} <span class="font-normal text-on-surface-variant">{{ item.unit }}</span></td>
                            <td class="px-3 py-2 text-right text-on-surface-variant">{{ item.min_stock }} / {{ item.max_stock ?? '—' }}</td>
                            <td class="px-3 py-2 text-right text-on-surface">{{ fmt(item.stock_value) }}</td>
                            <td class="px-3 py-2"><span class="rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="item.is_active ? meta[item.status].chip : 'bg-surface-container text-on-surface-variant'">{{ item.is_active ? meta[item.status].label : 'Inactivo' }}</span></td>
                          </tr>
                        }
                      </tbody>
                    </table>
                  </div>
                </div>
              }

              <nav class="flex flex-wrap items-center justify-between gap-2 px-1 text-[12px] text-on-surface-variant" aria-label="Paginación">
                <span>{{ rangeText(vm) }}</span>
                <span class="flex items-center gap-1">
                  <button type="button" (click)="store.setPage(vm.page - 1)" [disabled]="vm.page <= 1 || vm.loading" [class]="pageButton">Anterior</button>
                  <span class="px-2 font-semibold text-on-surface">{{ vm.page }} / {{ pages(vm) }}</span>
                  <button type="button" (click)="store.setPage(vm.page + 1)" [disabled]="vm.page >= pages(vm) || vm.loading" [class]="pageButton">Siguiente</button>
                </span>
              </nav>
            } @else if (vm.loading) {
              <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3" role="status" aria-label="Cargando inventario">
                @for (n of skeleton; track n) { <div class="h-36 animate-pulse rounded-2xl bg-surface-container motion-reduce:animate-none"></div> }
              </div>
            } @else if (!vm.error) {
              <div class="glass flex flex-col items-center gap-2 rounded-2xl px-6 py-12 text-center">
                <img src="assets/images/cola-vacia.svg" alt="" width="224" height="195" class="h-auto w-44 mix-blend-multiply" />
                <h2 class="text-[15px] font-bold text-on-surface">{{ hasFilters(vm) ? 'Ningún ítem coincide con los filtros' : 'Aún no hay ítems en el inventario' }}</h2>
                <p class="max-w-sm text-[13px] text-on-surface-variant">{{ hasFilters(vm) ? 'Prueba con otra búsqueda o limpia los filtros.' : 'Crea el primero o impórtalos desde un archivo CSV o Excel.' }}</p>
                @if (!hasFilters(vm) && canManage()) {
                  <button type="button" (click)="modal.set({ kind: 'create' })" class="glass-btn mt-1 rounded-xl px-5 py-2 text-[13px] font-bold">Nuevo ítem</button>
                }
              </div>
            }
          </section>

          <app-inventory-insights [overview]="vm.overview" [loading]="vm.overviewLoading" />
        </div>
      </div>

      @if (canManage()) {
        <button type="button" (click)="modal.set({ kind: 'create' })" aria-label="Nuevo ítem"
          class="glass-btn fixed bottom-4 right-4 z-30 flex h-14 w-14 items-center justify-center rounded-full shadow-lg lg:hidden focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
          <span class="material-symbols-outlined text-[28px]" aria-hidden="true">add</span>
        </button>
      }

      @if (vm.selectedId !== null) {
        <div class="fixed inset-0 z-40 bg-brand-navy/40" (click)="store.select(null)" aria-hidden="true"></div>
        <div class="fixed inset-y-0 right-0 z-50 w-full max-w-md p-3">
          <app-item-detail-panel [item]="vm.item" [movements]="vm.movements" [movementsTotal]="vm.movementsTotal" [loading]="vm.detailLoading"
            [error]="vm.detailError" [busy]="vm.busy" [canManage]="canManage()" (closed)="store.select(null)" (edit)="modal.set({ kind: 'edit' })"
            (move)="vm.item && modal.set({ kind: 'move', move: $event, item: vm.item })" />
        </div>
      }

      @switch (modal()?.kind) {
        @case ('create') { <app-item-form-modal [busy]="vm.busy" (closed)="modal.set(null)" /> }
        @case ('edit') { @if (vm.item) { <app-item-form-modal [item]="vm.item" [busy]="vm.busy" (closed)="modal.set(null)" /> } }
        @case ('import') { <app-import-modal [busy]="vm.busy" (closed)="modal.set(null)" /> }
        @case ('move') {
          @if (moveModal(); as m) { <app-movement-modal [item]="m.item" [initialKind]="m.move" [canManage]="canManage()" [busy]="vm.busy" (closed)="modal.set(null)" /> }
        }
      }
      <app-toast-host />
    }
  `,
})
export class InventoryComponent implements OnInit {
  readonly store = inject(InventoryStore);
  private readonly profile = inject(LocalProfileService);
  private readonly toasts = inject(ToastService);
  private readonly destroyRef = inject(DestroyRef);

  readonly vm$ = this.store.state$;
  readonly periods = PERIODS;
  readonly categories = CATEGORIES;
  readonly sorts = [
    { value: 'name', label: 'Nombre (A–Z)' },
    { value: '-stock_value', label: 'Mayor valor' },
    { value: 'stock', label: 'Menor stock' },
    { value: '-stock', label: 'Mayor stock' },
    { value: '-updated_at', label: 'Recién actualizados' },
  ];
  readonly skeleton = [1, 2, 3, 4, 5, 6];
  readonly focus = FOCUS;
  /** Respeta la preferencia del sistema: sin movimiento, el video no se reproduce. */
  readonly reduceMotion = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
  readonly field = FIELD;
  readonly meta = STATUS_META;
  readonly icon = categoryIcon;
  readonly categoryName = categoryLabel;
  readonly marker = minMarker;
  readonly fmt = money;
  readonly search$ = new Subject<string>();
  readonly canManage = signal(false);
  readonly canConsume = signal(false);
  readonly modal = signal<Modal>(null);
  readonly quick = `${FOCUS} flex-1 rounded-lg border border-brand-accentDeep bg-transparent px-2 py-1.5 text-[12px] font-semibold !text-brand-accentDeep hover:bg-surface-container disabled:opacity-40`;
  readonly pageButton = `${FOCUS} rounded-full bg-transparent px-3 py-1 text-[12px] font-bold !text-brand-accentDeep hover:bg-surface-container-high disabled:opacity-40`;
  readonly sortButton = `${FOCUS} bg-transparent p-0 text-[11px] font-bold uppercase tracking-wider !text-on-surface-variant hover:!text-on-surface`;

  async ngOnInit(): Promise<void> {
    this.search$
      .pipe(debounceTime(300), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe((search) => this.store.setFilters({ search }));
    this.store.load();
    const [manage, consume] = await Promise.all([this.profile.can('inventory.manage'), this.profile.can('inventory.consume')]);
    this.canManage.set(manage);
    this.canConsume.set(consume);
  }

  moveModal(): { move: MovementKind; item: InventoryItem } | null {
    const modal = this.modal();
    return modal?.kind === 'move' ? { move: modal.move, item: modal.item } : null;
  }

  openMove(item: InventoryItem, move: MovementKind): void {
    this.modal.set({ kind: 'move', move, item });
  }

  hasFilters(vm: InventoryState): boolean {
    const f = vm.filters;
    return !!(f.search.trim() || f.category || f.status);
  }

  pages(vm: InventoryState): number {
    return Math.max(Math.ceil(vm.total / PAGE_SIZE), 1);
  }

  rangeText(vm: InventoryState): string {
    const from = (vm.page - 1) * PAGE_SIZE + 1;
    return `${from}–${from + vm.items.length - 1} de ${vm.total}`;
  }

  sortBy(vm: InventoryState, field: string): void {
    this.store.setFilters({ sort: vm.filters.sort === field ? `-${field}` : field });
  }

  arrow(vm: InventoryState, field: string): string {
    return vm.filters.sort === field ? '▲' : vm.filters.sort === `-${field}` ? '▼' : '';
  }

  ariaSort(vm: InventoryState, field: string): 'ascending' | 'descending' | 'none' {
    return vm.filters.sort === field ? 'ascending' : vm.filters.sort === `-${field}` ? 'descending' : 'none';
  }

  exportCsv(): void {
    this.store.exportAll().subscribe({
      next: (items) => saveBlob(new Blob(['﻿' + itemsToCsv(items)], { type: 'text/csv;charset=utf-8' }), reportFilename('inventario', 'csv')),
      error: () => this.toasts.error('No se pudo exportar el inventario. Inténtalo de nuevo.'),
    });
  }
}
