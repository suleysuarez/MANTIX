import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Subject, debounceTime, distinctUntilChanged } from 'rxjs';

import { Period } from '../../core/dashboard-kpis.service';
import {
  PendingRequestsState,
  PendingRequestsStore,
  QUEUE_STATUSES,
  QueueStatus,
  isColumnHidden,
} from '../../core/pending-requests.store';
import { MaintenanceListItem } from '../../core/maintenance.service';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { changeTone, formatChange, formatPct } from '../dashboard/dashboard-format';
import { TicketChipComponent } from '../tickets/ticket-chip.component';
import { priorityMeta } from '../tickets/ticket-ui';
import { todayLocal } from '../../core/tickets.store';
import {
  COLUMNS, WAIT_CLASSES, categoryLabel, formatWait, share, waitHours, waitTone,
} from './pending-ui';
import { RequestDetailPanelComponent } from './request-detail-panel.component';

const PERIODS: { id: Period; label: string }[] = [
  { id: '7d', label: '7 días' },
  { id: '30d', label: '30 días' },
  { id: '12m', label: '12 meses' },
];
const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface ${FOCUS}`;

/** Bandeja de triaje: filtros y pulso de la cola a la izquierda, tablero al centro y detalle a la derecha. */
@Component({
  selector: 'app-pending-requests',
  standalone: true,
  imports: [AsyncPipe, TicketChipComponent, RequestDetailPanelComponent, ToastHostComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (vm$ | async; as vm) {
      <div class="space-y-4">
        <!-- Encabezado con ilustración -->
        <header class="relative overflow-hidden rounded-2xl bg-gradient-to-r from-brand-sidebar to-primary-container px-6 py-6 md:px-8 lg:min-h-[17rem]">
          <div class="relative z-10 flex flex-col gap-4 lg:max-w-[48%]">
            <span class="glass inline-flex w-fit items-center gap-2 rounded-full px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-brand-accentDeep">
              <span class="h-2 w-2 rounded-full bg-brand-mustard"></span> Bandeja de triaje
            </span>
            <h1 class="text-[26px] font-extrabold uppercase leading-tight tracking-tight text-white">
              Solicitudes <span class="text-brand-accentLight">pendientes</span>
            </h1>
            <p class="max-w-xl text-[14px] leading-relaxed text-brand-grey">
              Clasifica, asigna o rechaza lo que espera trabajo. Lo más antiguo aparece primero.
            </p>
            <div class="glass flex w-fit rounded-full p-0.5" role="group" aria-label="Periodo de las métricas">
              @for (p of periods; track p.id) {
                <button type="button" (click)="store.setPeriod(p.id)" [attr.aria-pressed]="vm.period === p.id"
                  class="rounded-full px-3 py-1 text-[12px] font-semibold transition-colors active:scale-95"
                  [class]="focus + (vm.period === p.id ? ' bg-brand-sidebar !text-white' : ' bg-transparent !text-brand-accentDeep hover:bg-surface-container')">{{ p.label }}</button>
              }
            </div>
          </div>
          <!-- Ilustración animada; con «reducir movimiento» se queda en el primer fotograma. -->
          <div class="pointer-events-none absolute inset-y-4 right-6 hidden aspect-video overflow-hidden rounded-2xl bg-surface-container-lowest shadow-lg lg:block" aria-hidden="true">
            <video class="h-full w-full object-cover" src="assets/videos/mensajes.mp4" poster="assets/videos/mensajes-poster.jpg"
              [muted]="true" playsinline preload="auto" [loop]="!reduceMotion" [autoplay]="!reduceMotion"></video>
          </div>
        </header>

        @if (vm.error) {
          <p role="alert" class="flex flex-wrap items-center gap-3 rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">
            {{ vm.error }}
            <button type="button" (click)="store.load()" class="rounded-md bg-transparent p-0 font-bold underline !text-on-error-container">Reintentar</button>
          </p>
        }

        <div [class]="'grid grid-cols-1 gap-4 lg:grid-cols-[17rem_minmax(0,1fr)] ' + (vm.selectedId !== null ? 'xl:grid-cols-[17rem_minmax(0,1fr)_24rem]' : '')">
          <!-- Riel izquierdo -->
          <div class="space-y-4">
            <form class="glass space-y-3 rounded-2xl p-4" role="search" aria-label="Filtros de la bandeja" (submit)="$event.preventDefault()">
              <div>
                <label for="q-search" class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Buscar</label>
                <input id="q-search" type="search" [class]="field + ' mt-1'" placeholder="Número, título o descripción"
                  [value]="vm.filters.search" (input)="search$.next($any($event.target).value)" maxlength="100" />
              </div>
              <div>
                <label for="q-priority" class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Prioridad</label>
                <select id="q-priority" [class]="field + ' mt-1'" (change)="store.setFilters({ priority: $any($event.target).value })">
                  <option value="" [selected]="!vm.filters.priority">Todas</option>
                  @for (p of priorities; track p) {
                    <option [value]="p" [selected]="vm.filters.priority === p">{{ priorityLabel(p) }}</option>
                  }
                </select>
              </div>
              <div>
                <label for="q-category" class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Categoría</label>
                <select id="q-category" [class]="field + ' mt-1'" (change)="store.setFilters({ category: $any($event.target).value })">
                  <option value="" [selected]="!vm.filters.category">Todas</option>
                  @for (c of vm.categories; track c.code) {
                    <option [value]="c.code" [selected]="vm.filters.category === c.code">{{ c.name }}</option>
                  }
                </select>
              </div>
              <div>
                <label for="q-order" class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Orden</label>
                <select id="q-order" [class]="field + ' mt-1'" (change)="store.setFilters({ order: $any($event.target).value })">
                  <option value="oldest" [selected]="vm.filters.order === 'oldest'">Más antiguas primero</option>
                  <option value="newest" [selected]="vm.filters.order === 'newest'">Más recientes primero</option>
                  <option value="priority" [selected]="vm.filters.order === 'priority'">Mayor prioridad primero</option>
                </select>
              </div>
              <fieldset class="space-y-1.5">
                <legend class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Recibidas entre</legend>
                <div class="grid grid-cols-2 gap-2">
                  <label class="sr-only" for="q-from">Desde</label>
                  <input id="q-from" type="date" [class]="field" [value]="vm.filters.dateFrom" [max]="today" aria-describedby="q-range-err"
                    [attr.aria-invalid]="!!vm.filterError" (change)="store.setFilters({ dateFrom: $any($event.target).value })" />
                  <label class="sr-only" for="q-to">Hasta</label>
                  <input id="q-to" type="date" [class]="field" [value]="vm.filters.dateTo" [attr.aria-invalid]="!!vm.filterError"
                    (change)="store.setFilters({ dateTo: $any($event.target).value })" />
                </div>
                <p id="q-range-err" class="min-h-4 text-[12px] text-error" role="alert">{{ vm.filterError }}</p>
              </fieldset>
              <label class="flex items-center gap-2 text-[13px] text-on-surface">
                <input type="checkbox" [checked]="vm.filters.unassignedOnly" (change)="store.setFilters({ unassignedOnly: $any($event.target).checked })"
                  class="h-4 w-4 accent-brand-accentDeep" />
                Solo sin técnico
              </label>
              @if (hasFilters(vm)) {
                <button type="button" (click)="store.clearFilters()"
                  [class]="focus + ' w-full rounded-lg border border-brand-accentDeep bg-transparent px-3 py-2 text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container'">Limpiar filtros</button>
              }
            </form>

            <section class="glass space-y-3 rounded-2xl p-4" aria-label="Pulso de la cola" [attr.aria-busy]="vm.summaryLoading">
              <h2 class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Pulso de la cola</h2>
              @if (vm.summary; as s) {
                <dl class="space-y-2 text-[13px]">
                  <div class="flex items-baseline justify-between gap-2"><dt class="text-on-surface-variant">En cola</dt><dd class="text-[20px] font-bold text-on-surface">{{ s.pending_total }}</dd></div>
                  <div class="flex items-baseline justify-between gap-2"><dt class="text-on-surface-variant">Sin técnico</dt><dd class="font-bold text-on-surface">{{ s.unassigned }}</dd></div>
                  <div class="flex items-baseline justify-between gap-2"><dt class="text-on-surface-variant">Más antigua</dt><dd class="font-bold text-on-surface">{{ s.oldest_wait_hours === null ? '—' : wait(s.oldest_wait_hours) }}</dd></div>
                  <div class="flex items-baseline justify-between gap-2"><dt class="text-on-surface-variant">Espera mediana</dt><dd class="font-bold text-on-surface">{{ s.median_wait_hours === null ? '—' : wait(s.median_wait_hours) }}</dd></div>
                </dl>
                <hr class="border-brand-grey/70" />
                <dl class="space-y-3 text-[13px]">
                  <div>
                    <dt class="text-on-surface-variant">Primera respuesta (media)</dt>
                    <dd class="mt-0.5">
                      @if (s.triage_time.value !== null) {
                        <span class="text-[18px] font-bold text-on-surface">{{ wait(s.triage_time.value) }}</span>
                        @if (changeText(s.triage_time.change_pct)) {
                          <span class="ml-2 rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="toneClass(s.triage_time.change_pct, 'lower')">{{ changeText(s.triage_time.change_pct) }}</span>
                        }
                        <span class="mt-0.5 block text-[11px] text-on-surface-variant">
                          mediana {{ s.triage_time.median_hours === null ? '—' : wait(s.triage_time.median_hours) }} · n = {{ s.triage_time.sample_size }}
                          @if (s.triage_time.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-1.5 py-0.5 text-[10px] font-bold text-on-secondary-fixed">pocos datos</span> }
                        </span>
                      } @else {
                        <span class="text-on-surface-variant" title="Sin decisiones en el periodo">—</span>
                      }
                    </dd>
                  </div>
                  <div>
                    <dt class="text-on-surface-variant">Aprobación / rechazo</dt>
                    <dd class="mt-0.5">
                      @if (s.decisions.approval_rate_pct !== null) {
                        <span class="text-[18px] font-bold text-on-surface">{{ pct(s.decisions.approval_rate_pct) }}</span>
                        <span class="text-[12px] text-on-surface-variant"> aprobadas</span>
                        @if (changeText(s.decisions.change_pct)) {
                          <span class="ml-2 rounded-full bg-surface-container px-2 py-0.5 text-[11px] font-bold text-on-surface-variant">{{ changeText(s.decisions.change_pct) }}</span>
                        }
                        <span class="mt-0.5 block text-[11px] text-on-surface-variant">
                          {{ s.decisions.approved }} aprobadas · {{ s.decisions.rejected }} rechazadas · n = {{ s.decisions.sample_size }}
                          @if (s.decisions.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-1.5 py-0.5 text-[10px] font-bold text-on-secondary-fixed">pocos datos</span> }
                        </span>
                      } @else {
                        <span class="text-on-surface-variant" title="Sin decisiones en el periodo">—</span>
                      }
                    </dd>
                  </div>
                </dl>
                <hr class="border-brand-grey/70" />
                <div>
                  <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Por prioridad</h3>
                  @for (row of s.by_priority; track row.key) {
                    <div class="mt-1.5">
                      <div class="flex justify-between text-[12px]"><span class="text-on-surface">{{ priorityLabel(row.key) }}</span><span class="font-bold">{{ row.count }}</span></div>
                      <div class="mt-0.5 h-1.5 overflow-hidden rounded-full bg-surface-container"><div class="h-full rounded-full bg-brand-accentDeep" [style.width.%]="share(row.count, s.pending_total)"></div></div>
                    </div>
                  } @empty { <p class="mt-1 text-[12px] text-on-surface-variant">Sin solicitudes en cola.</p> }
                </div>
                <div>
                  <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Por categoría</h3>
                  @for (row of s.by_category; track row.key) {
                    <div class="mt-1.5">
                      <div class="flex justify-between text-[12px]"><span class="text-on-surface">{{ categoryName(row.key, vm) }}</span><span class="font-bold">{{ row.count }}</span></div>
                      <div class="mt-0.5 h-1.5 overflow-hidden rounded-full bg-surface-container"><div class="h-full rounded-full bg-brand-slate" [style.width.%]="share(row.count, s.pending_total)"></div></div>
                    </div>
                  } @empty { <p class="mt-1 text-[12px] text-on-surface-variant">Sin solicitudes en cola.</p> }
                </div>
              } @else if (vm.summaryLoading) {
                <div class="space-y-2" role="status" aria-label="Cargando métricas">
                  <div class="h-5 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
                  <div class="h-5 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
                  <div class="h-16 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
                </div>
              } @else {
                <p class="text-[12px] text-on-surface-variant">Las métricas no están disponibles en este momento.</p>
              }
            </section>
          </div>

          <!-- Tablero -->
          <section class="min-w-0" aria-label="Tablero de solicitudes">
            @if (isEmpty(vm)) {
              <div class="glass flex flex-col items-center gap-3 rounded-2xl px-6 py-16 text-center">
                <img src="assets/images/cola-vacia.svg" alt="" width="256" height="223" class="h-auto w-48 mix-blend-multiply sm:w-64" />
                <h2 class="text-[16px] font-bold text-on-surface">{{ hasFilters(vm) ? 'Ninguna solicitud coincide con los filtros' : 'La bandeja está al día' }}</h2>
                <p class="max-w-sm text-[13px] text-on-surface-variant">{{ hasFilters(vm) ? 'Prueba con otra búsqueda o limpia los filtros.' : 'No hay solicitudes esperando trabajo.' }}</p>
                @if (hasFilters(vm)) {
                  <button type="button" (click)="store.clearFilters()" class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold">Limpiar filtros</button>
                }
              </div>
            } @else {
              <div class="grid grid-cols-1 gap-3 md:grid-cols-3">
                @for (col of columns; track col.status) {
                  @let c = vm.columns[col.status];
                  <div class="flex min-h-[14rem] flex-col gap-2 rounded-2xl bg-surface-container-low p-2.5" [attr.aria-label]="col.title">
                    <div class="flex items-center justify-between gap-2 px-1.5 pt-1">
                      <h2 class="flex items-center gap-1.5 text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">
                        <span class="material-symbols-outlined text-[18px]" aria-hidden="true">{{ col.icon }}</span>{{ col.title }}
                      </h2>
                      <span class="rounded-full bg-brand-accentLight px-2 py-0.5 text-[12px] font-bold text-brand-accentDeep" [attr.aria-label]="c.total + ' solicitudes'">{{ c.total }}</span>
                    </div>
                    <p class="px-1.5 text-[11px] text-on-surface-variant">{{ col.hint }}</p>

                    @if (hidden(col.status, vm)) {
                      <p class="m-2 rounded-lg bg-surface-container px-3 py-4 text-center text-[12px] text-on-surface-variant">Oculta por «Solo sin técnico».</p>
                    } @else if (c.loading && c.items.length === 0) {
                      @for (n of skeleton; track n) {
                        <div class="h-24 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none" role="status" aria-label="Cargando"></div>
                      }
                    } @else if (c.failed && c.items.length === 0) {
                      <p role="alert" class="m-2 rounded-lg bg-error-container px-3 py-3 text-[12px] text-on-error-container">No se pudo cargar esta columna.</p>
                    } @else if (c.items.length === 0) {
                      <div class="m-2 flex flex-1 flex-col items-center justify-center gap-1 px-3 py-6 text-center">
                        <img src="assets/images/columna-vacia.svg" alt="" width="160" height="88" class="h-auto w-36 mix-blend-multiply" />
                        <p class="text-[12px] text-on-surface-variant">Nada en «{{ col.title }}».</p>
                      </div>
                    } @else {
                      @for (item of c.items; track item.id) {
                        <button type="button" (click)="store.select(item.id)" [attr.aria-pressed]="vm.selectedId === item.id"
                          [class]="focus + ' block w-full rounded-xl border bg-surface-container-lowest p-3 text-left shadow-sm transition-all hover:-translate-y-0.5 hover:shadow-md motion-reduce:transition-none motion-reduce:hover:translate-y-0 ' + (vm.selectedId === item.id ? 'border-brand-accentDeep ring-2 ring-brand-accentDeep/30' : 'border-brand-grey')">
                          <span class="flex items-center justify-between gap-2">
                            <span class="font-mono text-[12px] font-bold text-brand-accentDeep">{{ item.ticket_number }}</span>
                            <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="waitClass(item)" [attr.title]="'En cola desde hace ' + waitText(item)">
                              <span class="material-symbols-outlined text-[13px]" aria-hidden="true">schedule</span>{{ waitText(item) }}
                            </span>
                          </span>
                          <span class="mt-1.5 line-clamp-2 block text-[13px] font-semibold leading-5 text-on-surface">{{ item.title }}</span>
                          <span class="mt-1 block truncate text-[12px] text-on-surface-variant">{{ equipmentLabel(item, vm) }}</span>
                          <span class="mt-2 flex flex-wrap items-center gap-1.5">
                            <app-ticket-chip kind="priority" [value]="item.priority" />
                            <span class="rounded-full bg-surface-container px-2 py-0.5 text-[11px] font-semibold text-on-surface-variant">{{ categoryName(item.category, vm) }}</span>
                          </span>
                        </button>
                      }
                      @if (c.items.length < c.total) {
                        <button type="button" (click)="store.loadMore(col.status)" [disabled]="c.loading"
                          [class]="focus + ' rounded-lg border border-brand-accentDeep bg-transparent px-3 py-2 text-[12px] font-semibold !text-brand-accentDeep hover:bg-surface-container disabled:opacity-50'">
                          {{ c.loading ? 'Cargando…' : 'Cargar más (' + (c.total - c.items.length) + ' restantes)' }}
                        </button>
                      }
                    }
                  </div>
                }
              </div>
            }
          </section>

          <!-- Detalle -->
          @if (vm.selectedId !== null) {
            <div class="fixed inset-0 z-40 bg-brand-navy/40 xl:hidden" (click)="store.select(null)" aria-hidden="true"></div>
            <div class="fixed inset-y-0 right-0 z-50 w-full max-w-md p-3 xl:sticky xl:top-4 xl:z-auto xl:h-fit xl:max-w-none xl:self-start xl:p-0">
              <app-request-detail-panel [detail]="vm.detail" [loading]="vm.detailLoading" [error]="vm.detailError" [busy]="vm.busy"
                [technicians]="vm.technicians" [categories]="vm.categories" [categoryNames]="categoryNames(vm)" (closed)="store.select(null)" />
            </div>
          }
        </div>
      </div>
      <app-toast-host />
    }
  `,
})
export class PendingRequestsComponent implements OnInit {
  readonly store = inject(PendingRequestsStore);
  private readonly destroyRef = inject(DestroyRef);

  readonly vm$ = this.store.state$;
  readonly periods = PERIODS;
  readonly columns = COLUMNS;
  readonly priorities = ['critical', 'high', 'medium', 'low'];
  readonly skeleton = [1, 2];
  readonly focus = FOCUS;
  readonly field = FIELD;
  /** Tope del selector «desde»: las solicitudes recibidas no son futuras. */
  readonly today = todayLocal();
  readonly search$ = new Subject<string>();
  /** Respeta la preferencia del sistema: sin movimiento, el video no se reproduce. */
  readonly reduceMotion = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

  readonly wait = formatWait;
  readonly pct = formatPct;
  readonly share = share;
  readonly priorityLabel = (code: string): string => priorityMeta(code).label;
  readonly changeText = formatChange;

  ngOnInit(): void {
    this.search$
      .pipe(debounceTime(300), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe((search) => this.store.setFilters({ search }));
    this.store.load();
  }

  hasFilters(vm: PendingRequestsState): boolean {
    const f = vm.filters;
    return !!(f.search.trim() || f.priority || f.category || f.unassignedOnly || f.dateFrom || f.dateTo || f.order !== 'oldest');
  }

  isEmpty(vm: PendingRequestsState): boolean {
    return (
      !vm.loading &&
      QUEUE_STATUSES.every((status) => vm.columns[status].items.length === 0 && !vm.columns[status].failed)
    );
  }

  hidden(status: QueueStatus, vm: PendingRequestsState): boolean {
    return isColumnHidden(status, vm.filters);
  }

  toneClass(changePct: number | null, betterWhen: 'higher' | 'lower'): string {
    const tone = changeTone(changePct, betterWhen);
    return tone === 'good'
      ? 'bg-primary-fixed text-on-primary-fixed-variant'
      : tone === 'bad'
        ? 'bg-secondary-fixed text-on-secondary-fixed'
        : 'bg-surface-container text-on-surface-variant';
  }

  categoryNames(vm: PendingRequestsState): Map<string, string> {
    return new Map(vm.categories.map((c) => [c.code, c.name]));
  }

  categoryName(code: string | null | undefined, vm: PendingRequestsState): string {
    return categoryLabel(code, this.categoryNames(vm));
  }

  equipmentLabel(item: MaintenanceListItem, vm: PendingRequestsState): string {
    const equipment = vm.equipmentById.get(item.equipment_id);
    return equipment ? `${equipment.asset_tag} · ${equipment.brand} ${equipment.model}` : `Equipo #${item.equipment_id}`;
  }

  waitText(item: MaintenanceListItem): string {
    return formatWait(waitHours(item.created_at));
  }

  waitClass(item: MaintenanceListItem): string {
    return WAIT_CLASSES[waitTone(waitHours(item.created_at))];
  }
}
