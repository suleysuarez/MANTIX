import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';

import { apiErrorMessage } from '../../core/api-errors';
import { HistoryEntry, HistoryKind, ProfileService } from '../../core/profile.service';
import { dateRangeError } from '../../shared/date-range';
import { DateRangeFilterComponent } from '../../shared/date-range-filter.component';
import { PaginationComponent } from '../../shared/pagination.component';
import { dayBoundaryIso } from '../reports/report-filters';
import { KIND_OPTIONS, KIND_STYLES, actionInfo, byText } from './profile-ui';

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const PAGE_SIZE = 15;

/** Historial propio: inicios de sesión, cambios en mis datos y lo que otros hicieron en mi cuenta. */
@Component({
  selector: 'app-profile-history',
  standalone: true,
  imports: [DatePipe, DateRangeFilterComponent, PaginationComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="space-y-3" aria-label="Historial" [attr.aria-busy]="loading()">
      <form class="glass rounded-2xl p-4" aria-label="Filtros del historial" (submit)="$event.preventDefault()">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-[minmax(0,16rem)_1fr_auto] sm:items-end">
          <div>
            <label for="ph-kind" class="text-[12px] font-bold text-on-surface">Tipo</label>
            <select id="ph-kind" class="mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface {{ focus }}"
              (change)="setKind($any($event.target).value)">
              @for (o of kinds; track o.value) { <option [value]="o.value" [selected]="kind() === o.value">{{ o.label }}</option> }
            </select>
          </div>
          <app-date-range-filter [inline]="true" label="Fecha" [from]="dateFrom()" [to]="dateTo()" (rangeChange)="setRange($event.from, $event.to)" />
          <button type="button" (click)="clear()" [disabled]="!filtered()"
            class="rounded-lg bg-transparent px-3 py-2 text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container disabled:opacity-40 {{ focus }}">Limpiar</button>
        </div>
      </form>

      @if (error()) {
        <p role="alert" class="flex flex-wrap items-center gap-3 rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">
          {{ error() }}
          <button type="button" (click)="load(page())" class="rounded-lg bg-transparent px-2 py-1 text-[13px] font-bold underline {{ focus }}">Reintentar</button>
        </p>
      }

      @if (items().length) {
        <ol class="glass divide-y divide-brand-grey/40 rounded-2xl">
          @for (entry of items(); track entry.id) {
            <li class="flex items-center gap-3 px-4 py-3">
              <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full" [class]="styleOf(entry)" aria-hidden="true">
                <span class="material-symbols-outlined text-[20px]">{{ info(entry).icon }}</span>
              </span>
              <div class="min-w-0 flex-1">
                <p class="truncate text-[13px] font-semibold text-on-surface">{{ info(entry).label }}</p>
                <p class="truncate text-[12px] text-on-surface-variant">
                  {{ kindLabel(entry.kind) }}@if (by(entry)) { · {{ by(entry) }} }@if (entry.ip_address) { · IP {{ entry.ip_address }} }
                </p>
              </div>
              <time class="shrink-0 font-mono text-[12px] text-on-surface-variant" [attr.datetime]="entry.created_at">{{ entry.created_at | date: 'dd/MM/yyyy HH:mm' }}</time>
            </li>
          }
        </ol>
        <app-pagination noun="eventos" [page]="page()" [pageSize]="pageSize" [total]="total()" [loading]="loading()" (pageChange)="load($event)" />
      } @else if (loading()) {
        <div class="space-y-2" role="status" aria-label="Cargando historial">
          @for (n of skeleton; track n) { <div class="h-14 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none"></div> }
        </div>
      } @else if (!error()) {
        <div class="glass flex flex-col items-center gap-2 rounded-2xl px-6 py-12 text-center">
          <span class="material-symbols-outlined text-[40px] text-on-surface-variant" aria-hidden="true">history_toggle_off</span>
          <h2 class="text-[15px] font-bold text-on-surface">{{ filtered() ? 'Ningún evento coincide con los filtros' : 'Aún no hay eventos en tu historial' }}</h2>
          <p class="max-w-sm text-[13px] text-on-surface-variant">{{ filtered() ? 'Prueba con otro tipo o limpia los filtros.' : 'Aquí verás tus inicios de sesión y los cambios en tu cuenta.' }}</p>
        </div>
      }
    </section>
  `,
})
export class ProfileHistoryComponent implements OnInit {
  private readonly api = inject(ProfileService);

  readonly kinds = KIND_OPTIONS;
  readonly focus = FOCUS;
  readonly pageSize = PAGE_SIZE;
  readonly skeleton = [1, 2, 3, 4, 5];
  readonly info = actionInfo;
  readonly by = byText;

  readonly kind = signal<HistoryKind | ''>('');
  readonly dateFrom = signal('');
  readonly dateTo = signal('');
  readonly items = signal<HistoryEntry[]>([]);
  readonly total = signal(0);
  readonly page = signal(1);
  readonly loading = signal(true);
  readonly error = signal('');

  ngOnInit(): void {
    this.load(1);
  }

  filtered(): boolean {
    return !!(this.kind() || this.dateFrom() || this.dateTo());
  }

  setKind(value: HistoryKind | ''): void {
    this.kind.set(value);
    this.load(1);
  }

  setRange(from: string, to: string): void {
    this.dateFrom.set(from);
    this.dateTo.set(to);
    if (!dateRangeError(from, to)) {
      this.load(1);
    }
  }

  clear(): void {
    this.kind.set('');
    this.dateFrom.set('');
    this.dateTo.set('');
    this.load(1);
  }

  load(page: number): void {
    if (page < 1) {
      return;
    }
    this.loading.set(true);
    this.error.set('');
    this.api
      .history({
        kind: this.kind(),
        dateFrom: dayBoundaryIso(this.dateFrom(), false) ?? undefined,
        dateTo: dayBoundaryIso(this.dateTo(), true) ?? undefined,
        page,
        size: PAGE_SIZE,
      })
      .subscribe({
        next: ({ items, total }) => {
          if (items.length === 0 && page > 1) {
            this.load(page - 1);
            return;
          }
          this.items.set(items);
          this.total.set(total);
          this.page.set(page);
          this.loading.set(false);
        },
        error: (error) => {
          this.loading.set(false);
          this.error.set(apiErrorMessage(error, 'No se pudo cargar tu historial.'));
        },
      });
  }

  styleOf(entry: HistoryEntry): string {
    return KIND_STYLES[entry.kind];
  }

  kindLabel(kind: HistoryKind): string {
    return this.kinds.find((option) => option.value === kind)?.label ?? '';
  }
}
