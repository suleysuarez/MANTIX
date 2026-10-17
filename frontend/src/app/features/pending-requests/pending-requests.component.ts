import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed, toSignal } from '@angular/core/rxjs-interop';
import { Observable, Subject, debounceTime, distinctUntilChanged } from 'rxjs';

import { Period } from '../../core/dashboard-kpis.service';
import {
  PendingRequestsState,
  PendingRequestsStore,
  isColumnHidden,
} from '../../core/pending-requests.store';
import { PermissionsService } from '../../core/permissions.service';
import { MaintenanceListItem } from '../../core/maintenance.service';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { changeTone, formatChange, formatPct } from '../dashboard/dashboard-format';
import { KanbanBoardComponent, KanbanCardDirective, KanbanColumn, KanbanMove, KanbanOutcome } from '../kanban/kanban-board.component';
import { Choice, TransitionDialogComponent } from '../kanban/transition-dialog.component';
import { TransitionFlow, allowedTargets, permissionBlock } from '../kanban/transition-flow';
import { statusMeta } from '../tickets/ticket-ui';
import {
  WAIT_CLASSES, categoryLabel, columnText, formatWait, priorityTag, share, waitHours, waitTone,
} from './pending-ui';
import { RequestDetailPanelComponent } from './request-detail-panel.component';
import { DateRangeFilterComponent } from '../../shared/date-range-filter.component';

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
  imports: [AsyncPipe, RequestDetailPanelComponent, ToastHostComponent, DateRangeFilterComponent, KanbanBoardComponent, KanbanCardDirective, TransitionDialogComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (vm$ | async; as vm) {
      <div class="space-y-4">
        <!-- Encabezado con ilustración -->
        <header class="relative overflow-hidden rounded-2xl bg-gradient-to-r from-brand-sidebar to-primary-container px-6 py-4 md:px-8 lg:min-h-[10rem]">
          <div class="relative z-10 flex flex-col gap-2.5 lg:max-w-[48%]">
            <span class="glass inline-flex w-fit items-center gap-2 rounded-full px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-brand-accentDeep">
              <span class="h-2 w-2 rounded-full bg-brand-mustard"></span> Bandeja de triaje
            </span>
            <h1 class="text-[24px] font-extrabold uppercase leading-tight tracking-tight text-white">
              Solicitudes <span class="text-brand-accentLight">pendientes</span>
            </h1>
            <p class="max-w-xl text-[13px] leading-snug text-brand-grey">
              Clasifica, asigna o rechaza lo que espera trabajo. Arrastra una tarjeta a otra columna para cambiar su estado.
            </p>
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

        <!-- Filtros: una sola barra a todo el ancho -->
        <form class="glass space-y-3 rounded-2xl p-4" role="search" aria-label="Filtros de la bandeja" (submit)="$event.preventDefault()">
          <div class="grid grid-cols-1 items-end gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_repeat(3,minmax(0,1fr))_auto_auto]">
            <div>
              <label for="q-search" class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Buscar</label>
              <input id="q-search" type="search" [class]="field + ' mt-1 h-10'" placeholder="Número, título o descripción"
                [value]="vm.filters.search" (input)="search$.next($any($event.target).value)" maxlength="100" />
            </div>
            <div>
              <label for="q-priority" class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Prioridad</label>
              <select id="q-priority" [class]="field + ' mt-1 h-10'" (change)="store.setFilters({ priority: $any($event.target).value })">
                <option value="" [selected]="!vm.filters.priority">Todas</option>
                @for (p of vm.priorities; track p.code) {
                  <option [value]="p.code" [selected]="vm.filters.priority === p.code">{{ p.name }}</option>
                }
              </select>
            </div>
            <div>
              <label for="q-category" class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Categoría</label>
              <select id="q-category" [class]="field + ' mt-1 h-10'" (change)="store.setFilters({ category: $any($event.target).value })">
                <option value="" [selected]="!vm.filters.category">Todas</option>
                @for (c of vm.categories; track c.code) {
                  <option [value]="c.code" [selected]="vm.filters.category === c.code">{{ c.name }}</option>
                }
              </select>
            </div>
            <div>
              <label for="q-order" class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Orden</label>
              <select id="q-order" [class]="field + ' mt-1 h-10'" (change)="store.setFilters({ order: $any($event.target).value })">
                <option value="newest" [selected]="vm.filters.order === 'newest'">Más recientes</option>
                <option value="priority" [selected]="vm.filters.order === 'priority'">Mayor prioridad</option>
              </select>
            </div>
            <label class="flex h-10 items-center gap-2 whitespace-nowrap text-[13px] text-on-surface">
              <input type="checkbox" [checked]="vm.filters.unassignedOnly" (change)="store.setFilters({ unassignedOnly: $any($event.target).checked })"
                class="h-4 w-4 accent-brand-accentDeep" />
              Solo sin técnico
            </label>
            <button type="button" (click)="store.clearFilters()" [disabled]="!hasFilters(vm)"
              [class]="focus + ' h-10 whitespace-nowrap rounded-lg border border-brand-accentDeep bg-transparent px-4 text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container disabled:opacity-40'">Limpiar filtros</button>
          </div>
          <app-date-range-filter [inline]="true" label="Recibidas entre" [from]="vm.filters.dateFrom" [to]="vm.filters.dateTo"
            (rangeChange)="store.setFilters({ dateFrom: $event.from, dateTo: $event.to })" />
        </form>

        <!-- Pulso de la cola: indicadores en una franja a todo el ancho -->
        <section class="glass space-y-4 rounded-2xl p-4" aria-label="Pulso de la cola" [attr.aria-busy]="vm.summaryLoading">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Pulso de la cola</h2>
            <span class="text-[11px] text-on-surface-variant">Decisiones de los últimos {{ periodLabel(vm.period) }}</span>
          </div>
          @if (vm.summary; as s) {
            <dl class="grid grid-cols-2 gap-3 lg:grid-cols-4">
              <div class="rounded-xl bg-surface-container-lowest p-3 text-center">
                <dt class="text-[11px] font-semibold uppercase tracking-wider text-on-surface-variant">En cola</dt>
                <dd class="ml-0 mt-1 text-[26px] font-extrabold leading-none text-brand-accentDeep">{{ s.pending_total }}</dd>
              </div>
              <div class="rounded-xl bg-surface-container-lowest p-3 text-center">
                <dt class="text-[11px] font-semibold uppercase tracking-wider text-on-surface-variant">Sin técnico</dt>
                <dd class="ml-0 mt-1 text-[26px] font-extrabold leading-none text-on-surface">{{ s.unassigned }}</dd>
              </div>
              <div class="rounded-xl bg-surface-container-lowest p-3 text-center">
                <dt class="text-[11px] font-semibold uppercase tracking-wider text-on-surface-variant">Más antigua</dt>
                <dd class="ml-0 mt-1 text-[26px] font-extrabold leading-none text-on-surface">{{ s.oldest_wait_hours === null ? '—' : wait(s.oldest_wait_hours) }}</dd>
              </div>
              <div class="rounded-xl bg-surface-container-lowest p-3 text-center">
                <dt class="text-[11px] font-semibold uppercase tracking-wider text-on-surface-variant">Espera mediana</dt>
                <dd class="ml-0 mt-1 text-[26px] font-extrabold leading-none text-on-surface">{{ s.median_wait_hours === null ? '—' : wait(s.median_wait_hours) }}</dd>
              </div>
            </dl>
            <div class="grid grid-cols-1 gap-x-6 gap-y-4 md:grid-cols-2 xl:grid-cols-4">
              <div>
                <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Primera respuesta (media)</h3>
                @if (s.triage_time.value !== null) {
                  <p class="mt-1">
                    <span class="text-[20px] font-bold text-on-surface">{{ wait(s.triage_time.value) }}</span>
                    @if (changeText(s.triage_time.change_pct)) {
                      <span class="ml-2 rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="toneClass(s.triage_time.change_pct, 'lower')">{{ changeText(s.triage_time.change_pct) }}</span>
                    }
                  </p>
                  <p class="text-[11px] text-on-surface-variant">
                    mediana {{ s.triage_time.median_hours === null ? '—' : wait(s.triage_time.median_hours) }} · n = {{ s.triage_time.sample_size }}
                    @if (s.triage_time.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-1.5 py-0.5 text-[10px] font-bold text-on-secondary-fixed">pocos datos</span> }
                  </p>
                } @else {
                  <p class="mt-1 text-on-surface-variant" title="Sin decisiones en el periodo">—</p>
                }
              </div>
              <div>
                <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Aprobación / rechazo</h3>
                @if (s.decisions.approval_rate_pct !== null) {
                  <p class="mt-1">
                    <span class="text-[20px] font-bold text-on-surface">{{ pct(s.decisions.approval_rate_pct) }}</span>
                    <span class="text-[12px] text-on-surface-variant"> aprobadas</span>
                    @if (changeText(s.decisions.change_pct)) {
                      <span class="ml-2 rounded-full bg-surface-container px-2 py-0.5 text-[11px] font-bold text-on-surface-variant">{{ changeText(s.decisions.change_pct) }}</span>
                    }
                  </p>
                  <p class="text-[11px] text-on-surface-variant">
                    {{ s.decisions.approved }} aprobadas · {{ s.decisions.rejected }} rechazadas · n = {{ s.decisions.sample_size }}
                    @if (s.decisions.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-1.5 py-0.5 text-[10px] font-bold text-on-secondary-fixed">pocos datos</span> }
                  </p>
                } @else {
                  <p class="mt-1 text-on-surface-variant" title="Sin decisiones en el periodo">—</p>
                }
              </div>
              <div>
                <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Por prioridad</h3>
                @for (row of s.by_priority; track row.key) {
                  <div class="mt-1.5">
                    <div class="flex justify-between gap-2 text-[12px]"><span class="text-on-surface">{{ priorityTag(row.key, vm.priorities).label }}</span><span class="font-bold">{{ row.count }}</span></div>
                    <div class="mt-0.5 h-1.5 overflow-hidden rounded-full bg-surface-container"><div class="h-full rounded-full bg-brand-accentDeep" [style.width.%]="share(row.count, s.pending_total)"></div></div>
                  </div>
                } @empty { <p class="mt-1 text-[12px] text-on-surface-variant">Sin solicitudes en cola.</p> }
              </div>
              <div>
                <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Por categoría</h3>
                @for (row of s.by_category; track row.key) {
                  <div class="mt-1.5">
                    <div class="flex justify-between gap-2 text-[12px]"><span class="text-on-surface">{{ categoryName(row.key, vm) }}</span><span class="font-bold">{{ row.count }}</span></div>
                    <div class="mt-0.5 h-1.5 overflow-hidden rounded-full bg-surface-container"><div class="h-full rounded-full bg-brand-slate" [style.width.%]="share(row.count, s.pending_total)"></div></div>
                  </div>
                } @empty { <p class="mt-1 text-[12px] text-on-surface-variant">Sin solicitudes en cola.</p> }
              </div>
            </div>
          } @else if (vm.summaryLoading) {
            <div class="grid grid-cols-2 gap-3 lg:grid-cols-4" role="status" aria-label="Cargando métricas">
              <div class="h-16 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none"></div>
              <div class="h-16 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none"></div>
              <div class="h-16 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none"></div>
              <div class="h-16 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none"></div>
            </div>
          } @else {
            <p class="text-[12px] text-on-surface-variant">Las métricas no están disponibles en este momento.</p>
          }
        </section>

        <div>
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
              <app-kanban-board ariaLabel="Tablero de solicitudes" [columns]="boardColumns(vm)" [key]="requestKey" [label]="requestLabel"
                [validTargets]="validTargets" [handler]="moveRequest" [invalidMessage]="invalidMove" [disabled]="!canManage()"
                emptyText="Nada por aquí" emptyImage="assets/images/columna-vacia.svg" [minColumnWidth]="170" (loadMore)="store.loadMore($event)">
                <ng-template appKanbanCard let-item>
                  <article role="button" tabindex="0" (click)="store.select(item.id)" (keydown.enter)="store.select(item.id)" [attr.aria-pressed]="vm.selectedId === item.id"
                    [class]="focus + ' block cursor-pointer space-y-2 rounded-xl border bg-surface-container-lowest p-3 pr-9 shadow-sm transition-all hover:shadow-md ' + (vm.selectedId === item.id ? 'border-brand-accentDeep ring-2 ring-brand-accentDeep/30' : 'border-brand-grey')">
                    <div class="flex flex-wrap items-center justify-between gap-1">
                      <span class="font-mono text-[12px] font-bold text-brand-accentDeep">{{ item.ticket_number }}</span>
                      <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="waitClass(item)" [attr.title]="'En cola desde hace ' + waitText(item)">
                        <span class="material-symbols-outlined text-[13px]" aria-hidden="true">schedule</span>{{ waitText(item) }}
                      </span>
                    </div>
                    <p class="line-clamp-2 break-words text-[13px] font-semibold leading-5 text-on-surface" [attr.title]="item.title">{{ item.title }}</p>
                    <p class="line-clamp-2 break-words text-[12px] text-on-surface-variant">{{ equipmentLabel(item, vm) }}</p>
                    <div class="flex flex-wrap items-center gap-1.5">
                      @let tag = priorityTag(item.priority, vm.priorities);
                      <span class="inline-flex max-w-full items-center break-words rounded-full px-2 py-0.5 text-[11px] font-bold leading-4" [class]="tag.classes">{{ tag.label }}</span>
                      <span class="inline-flex max-w-full break-words rounded-full bg-surface-container px-2 py-0.5 text-[11px] font-semibold leading-4 text-on-surface-variant">{{ categoryName(item.category, vm) }}</span>
                    </div>
                  </article>
                </ng-template>
              </app-kanban-board>
            }
          </section>

          <!-- Detalle -->
          @if (vm.selectedId !== null) {
            <div class="fixed inset-0 z-40 bg-brand-navy/40" (click)="store.select(null)" aria-hidden="true"></div>
            <div class="fixed inset-y-0 right-0 z-50 w-full max-w-md overflow-y-auto p-3">
              <app-request-detail-panel [detail]="vm.detail" [loading]="vm.detailLoading" [error]="vm.detailError" [busy]="vm.busy"
                [technicians]="vm.technicians" [categories]="vm.categories" [categoryNames]="categoryNames(vm)" (closed)="store.select(null)" />
            </div>
          }
        </div>
      </div>
      @if (flow.dialog(); as d) {
        <app-transition-dialog [title]="d.title" [subtitle]="d.subtitle" [confirmLabel]="d.confirm" [requires]="d.requires"
          [categories]="categoryChoices(vm)" [priorities]="priorityChoices(vm)" [technicians]="vm.technicians" [initial]="d.initial" [busy]="flow.busy()"
          (confirmed)="d.answer($event)" (cancelled)="d.answer(null)" />
      }
      <app-toast-host />
    }
  `,
})
export class PendingRequestsComponent implements OnInit {
  readonly store = inject(PendingRequestsStore);
  private readonly destroyRef = inject(DestroyRef);

  private readonly permissions = inject(PermissionsService);

  readonly vm$ = this.store.state$;
  private readonly state = toSignal(this.store.state$, { initialValue: null });
  readonly periodLabel = (period: Period): string => PERIODS.find((p) => p.id === period)?.label ?? period;
  /** Solo quien gestiona solicitudes puede moverlas; el servidor lo vuelve a comprobar (403). */
  readonly canManage = signal(false);
  /** Diálogo de los pasos que piden datos (el mismo flujo que en Tickets). */
  readonly flow = new TransitionFlow();
  private columnsCache: {
    columns: PendingRequestsState['columns'];
    workflow: PendingRequestsState['workflow'];
    filters: PendingRequestsState['filters'];
    result: KanbanColumn<MaintenanceListItem>[];
  } | null = null;
  readonly focus = FOCUS;
  readonly field = FIELD;
  readonly search$ = new Subject<string>();
  /** Respeta la preferencia del sistema: sin movimiento, el video no se reproduce. */
  readonly reduceMotion = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

  readonly wait = formatWait;
  readonly pct = formatPct;
  readonly share = share;
  readonly priorityTag = priorityTag;
  readonly changeText = formatChange;

  async ngOnInit(): Promise<void> {
    this.search$
      .pipe(debounceTime(300), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe((search) => this.store.setFilters({ search }));
    this.store.load();
    this.canManage.set(await this.permissions.can('solicitudes:editar'));
  }

  readonly requestKey = (item: MaintenanceListItem): number => item.id;
  readonly requestLabel = (item: MaintenanceListItem): string => item.ticket_number;

  /** Columnas del tablero: una por estado de la bandeja que define el servidor. Se reutiliza el arreglo si nada cambió. */
  boardColumns(vm: PendingRequestsState): KanbanColumn<MaintenanceListItem>[] {
    const cache = this.columnsCache;
    if (cache && cache.columns === vm.columns && cache.workflow === vm.workflow && cache.filters === vm.filters) {
      return cache.result;
    }
    const result = vm.statuses.map((status) => {
      const column = vm.columns[status];
      const text = columnText(status);
      const empty = column.items.length === 0;
      return {
        id: status,
        title: text.title,
        hint: text.hint,
        dot: statusMeta(status).dot,
        items: column.items,
        total: column.total,
        loading: column.loading,
        notice: isColumnHidden(status, vm.filters, vm.workflow)
          ? 'Oculta por «Solo sin técnico».'
          : empty && column.loading ? 'Cargando…' : empty && column.failed ? 'No se pudo cargar esta columna.' : undefined,
      };
    });
    this.columnsCache = { columns: vm.columns, workflow: vm.workflow, filters: vm.filters, result };
    return result;
  }

  /** Pasos válidos desde cada estado, tal como los define el State Pattern del servidor. */
  readonly validTargets = (item: MaintenanceListItem, from: string): string[] => allowedTargets(item, from, this.state()?.workflow ?? []);

  readonly invalidMove = (move: KanbanMove<MaintenanceListItem>, allowed: string[]): string => {
    const blocked = permissionBlock(move.item, move.to, this.state()?.workflow ?? [], (status) => columnText(status).title);
    if (blocked) {
      return blocked;
    }
    const label = (status: string): string => `«${columnText(status).title}»`;
    const next = allowed.length ? ` Desde ahí solo puede ir a ${allowed.map(label).join(', ')}.` : ' Ese estado es final.';
    return `No se puede pasar ${move.item.ticket_number} de ${label(move.from)} a ${label(move.to)}.${next}`;
  };

  /** Paso pedido arrastrando: si el estado destino exige datos se piden antes; si se cancelan, la tarjeta vuelve. */
  readonly moveRequest = (move: KanbanMove<MaintenanceListItem>): Observable<KanbanOutcome> => {
    const requires = this.state()?.workflow.find((state) => state.status === move.to)?.requires ?? [];
    return this.flow.run(
      {
        to: move.to,
        requires,
        title: move.to === 'triaged' ? 'Clasificar solicitud' : undefined,
        subtitle: `${move.item.ticket_number} pasará a «${columnText(move.to).title}».`,
        initial: { category: move.item.category ?? '', priority: move.item.priority },
      },
      (data) => this.store.move(move.item, move.from, move.to, data),
    );
  };

  categoryChoices(vm: PendingRequestsState): Choice[] {
    return vm.categories.map((c) => ({ value: c.code, label: c.name }));
  }

  priorityChoices(vm: PendingRequestsState): Choice[] {
    return vm.priorities.map((p) => ({ value: p.code, label: p.name }));
  }

  hasFilters(vm: PendingRequestsState): boolean {
    const f = vm.filters;
    return !!(f.search.trim() || f.priority || f.category || f.unassignedOnly || f.dateFrom || f.dateTo || f.order !== 'newest');
  }

  isEmpty(vm: PendingRequestsState): boolean {
    return (
      !vm.loading &&
      vm.statuses.length > 0 &&
      vm.statuses.every((status) => vm.columns[status].items.length === 0 && !vm.columns[status].failed)
    );
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
