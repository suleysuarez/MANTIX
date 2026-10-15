import { toObservable, takeUntilDestroyed } from '@angular/core/rxjs-interop';
import {
  ChangeDetectionStrategy, Component, DestroyRef, ElementRef, OnInit, computed, effect, inject, input, output, signal, viewChild,
} from '@angular/core';
import { catchError, debounceTime, distinctUntilChanged, of, switchMap, tap } from 'rxjs';

import { apiErrorMessage } from '../../core/api-errors';
import { saveBlob } from '../../core/download';
import {
  DocumentFormat, ExportApiFilters, ExportColumnInfo, ExportCount, ExportOptions, ExportService,
} from '../../core/export.service';
import { QueueService, RequestCategory } from '../../core/queue.service';
import { readableError } from '../../core/reports.store';
import { Technician, TechniciansService } from '../../core/technicians.service';
import { ToastService } from '../../core/toast.service';
import { queueRangeError } from '../pending-requests/pending-ui';
import {
  ExportFilterValues, FORMAT_CARDS, RangeShortcut, SHORTCUTS, countMessage, dayString, shortcutOf, shortcutRange, toExportFilters,
} from './export-model';

export interface ChoiceOption {
  value: string;
  label: string;
}

/** Qué filtros ofrece el panel para un reporte; los listados pasan los suyos. */
export type ExportFilterKind = 'statuses' | 'priorities' | 'technicians' | 'categories';

type Phase = 'idle' | 'generating' | 'done' | 'error';
type CountState =
  | { status: 'idle' | 'loading' | 'failed' }
  | ({ status: 'ready' } & ExportCount);

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `h-10 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 text-[13px] text-on-surface ${FOCUS}`;

/**
 * Panel lateral de exportación a PDF o Excel. Parte de los filtros de la pantalla que lo abre,
 * cuenta en vivo los registros y no deja exportar un rango imposible, sin registros o demasiado grande.
 */
@Component({
  selector: 'app-export-drawer',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { '(keydown.escape)': 'close()' },
  template: `
    <div class="fixed inset-0 z-50 flex justify-end" role="presentation">
      <div class="absolute inset-0 bg-brand-sidebar/50" (click)="close()" aria-hidden="true"></div>
      <aside role="dialog" aria-modal="true" aria-labelledby="exp-title"
        class="tw-reset relative flex h-full w-full max-w-[28rem] flex-col bg-surface-container-lowest shadow-2xl">
        <header class="flex items-start justify-between gap-3 border-b border-brand-grey px-5 py-4">
          <div>
            <h2 id="exp-title" class="text-[17px] font-bold text-on-surface">Exportar {{ title() }}</h2>
            <p class="text-[12px] text-on-surface-variant">Elige el formato, el periodo y lo que quieres incluir.</p>
          </div>
          <button #closeButton type="button" (click)="close()" aria-label="Cerrar panel de exportación"
            [class]="focus + ' rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container'">
            <span class="material-symbols-outlined text-[22px]" aria-hidden="true">close</span>
          </button>
        </header>

        <div class="min-h-0 flex-1 space-y-5 overflow-y-auto px-5 py-4">
          @if (phase() === 'done') {
            <div class="flex flex-col items-center gap-3 rounded-2xl bg-brand-accentLight/40 px-4 py-8 text-center" role="status">
              <span class="material-symbols-outlined text-[40px] text-brand-accentDeep" aria-hidden="true">task_alt</span>
              <p class="text-[15px] font-bold text-on-surface">Archivo generado</p>
              <p class="break-all font-mono text-[12px] text-on-surface-variant">{{ fileName() }}</p>
              <p class="text-[12px] text-on-surface-variant">La descarga empezó sola. Si no la ves, descárgalo de nuevo.</p>
              <div class="flex gap-2">
                <button type="button" (click)="downloadAgain()" [class]="focus + ' glass-btn rounded-lg px-4 py-2 text-[13px] font-bold'">Descargar de nuevo</button>
                <button type="button" (click)="close()" [class]="focus + ' rounded-lg bg-transparent px-4 py-2 text-[13px] font-bold !text-brand-accentDeep hover:bg-surface-container-high'">Cerrar</button>
              </div>
            </div>
          } @else {
            <fieldset [disabled]="phase() === 'generating'" class="space-y-5">
              <!-- Formato -->
              <div role="radiogroup" aria-label="Formato" class="grid grid-cols-2 gap-3">
                @for (card of cards; track card.id) {
                  <button type="button" role="radio" [attr.aria-checked]="format() === card.id" (click)="format.set(card.id)"
                    [class]="focus + ' flex flex-col items-start gap-1.5 rounded-2xl border p-3 text-left transition-all ' + (format() === card.id ? 'border-brand-accentDeep bg-brand-accentLight/40 ring-2 ring-brand-accentDeep/30' : 'border-brand-grey bg-surface-container-lowest hover:border-brand-slate')">
                    <span class="material-symbols-outlined text-[28px] text-brand-accentDeep" aria-hidden="true">{{ card.icon }}</span>
                    <span class="text-[14px] font-bold text-on-surface">{{ card.title }}</span>
                    <span class="text-[11px] leading-4 text-on-surface-variant">{{ card.text }}</span>
                  </button>
                }
              </div>

              <!-- Periodo -->
              <section aria-label="Periodo" class="space-y-2">
                <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Periodo (fecha de creación)</h3>
                <div class="flex flex-wrap gap-1.5">
                  @for (s of shortcuts; track s.id) {
                    <button type="button" (click)="pickShortcut(s.id)" [attr.aria-pressed]="shortcut() === s.id"
                      [class]="focus + ' rounded-full border px-3 py-1 text-[12px] font-semibold ' + (shortcut() === s.id ? 'border-brand-sidebar bg-brand-sidebar !text-white' : 'border-brand-grey bg-transparent !text-brand-accentDeep hover:bg-surface-container')">{{ s.label }}</button>
                  }
                </div>
                <div class="grid grid-cols-2 gap-2">
                  <div>
                    <label for="exp-from" class="text-[11px] font-semibold text-on-surface-variant">Desde</label>
                    <input id="exp-from" type="date" [class]="field" [value]="dateFrom()" [max]="today" aria-describedby="exp-range-err"
                      [attr.aria-invalid]="!!rangeError()" (change)="setDate('from', $any($event.target).value)" />
                  </div>
                  <div>
                    <label for="exp-to" class="text-[11px] font-semibold text-on-surface-variant">Hasta</label>
                    <input id="exp-to" type="date" [class]="field" [value]="dateTo()" [attr.aria-invalid]="!!rangeError()"
                      (change)="setDate('to', $any($event.target).value)" />
                  </div>
                </div>
                <p id="exp-range-err" class="min-h-4 text-[12px] text-error" role="alert">{{ rangeError() }}</p>
              </section>

              <!-- Filtros de la pantalla -->
              @if (filterKinds().includes('statuses') && statusOptions().length) {
                <section aria-label="Estado" class="space-y-1.5">
                  <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Estado</h3>
                  <div class="flex flex-wrap gap-1.5">
                    @for (o of statusOptions(); track o.value) {
                      <button type="button" (click)="toggle(statuses, o.value)" [attr.aria-pressed]="statuses().includes(o.value)" [class]="chip(statuses().includes(o.value))">{{ o.label }}</button>
                    }
                  </div>
                </section>
              }
              @if (filterKinds().includes('priorities') && priorityOptions().length) {
                <section aria-label="Prioridad" class="space-y-1.5">
                  <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Prioridad</h3>
                  <div class="flex flex-wrap gap-1.5">
                    @for (o of priorityOptions(); track o.value) {
                      <button type="button" (click)="toggle(priorities, o.value)" [attr.aria-pressed]="priorities().includes(o.value)" [class]="chip(priorities().includes(o.value))">{{ o.label }}</button>
                    }
                  </div>
                </section>
              }
              @if (filterKinds().includes('categories') && categories().length) {
                <section aria-label="Categoría" class="space-y-1.5">
                  <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Categoría</h3>
                  <div class="flex flex-wrap gap-1.5">
                    @for (c of categories(); track c.code) {
                      <button type="button" (click)="toggle(categoryCodes, c.code)" [attr.aria-pressed]="categoryCodes().includes(c.code)" [class]="chip(categoryCodes().includes(c.code))">{{ c.name }}</button>
                    }
                  </div>
                </section>
              }
              @if (filterKinds().includes('technicians') && technicians().length) {
                <section aria-label="Técnico" class="space-y-1.5">
                  <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Técnico</h3>
                  <div class="flex flex-wrap gap-1.5">
                    @for (t of technicians(); track t.id) {
                      <button type="button" (click)="toggleNumber(technicianIds, t.id)" [attr.aria-pressed]="technicianIds().includes(t.id)" [class]="chip(technicianIds().includes(t.id))">{{ t.full_name }}</button>
                    }
                  </div>
                </section>
              }

              <!-- Contenido -->
              @if (format() === 'xlsx') {
                <section aria-label="Columnas" class="space-y-1.5">
                  <div class="flex items-center justify-between">
                    <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Columnas del Excel</h3>
                    <span class="flex gap-2 text-[11px]">
                      <button type="button" (click)="selectAllColumns()" [class]="focus + ' bg-transparent p-0 font-bold underline !text-brand-accentDeep'">Todas</button>
                      <button type="button" (click)="selected.set([])" [class]="focus + ' bg-transparent p-0 font-bold underline !text-brand-accentDeep'">Ninguna</button>
                    </span>
                  </div>
                  <ul class="grid grid-cols-2 gap-x-3 gap-y-1">
                    @for (c of columns(); track c.key) {
                      <li>
                        <label class="flex items-center gap-2 text-[12px] text-on-surface">
                          <input type="checkbox" [checked]="selected().includes(c.key)" (change)="toggle(selected, c.key)" class="h-4 w-4 accent-brand-accentDeep" />
                          {{ c.label }}
                        </label>
                      </li>
                    }
                  </ul>
                  @if (selected().length === 0) { <p class="text-[12px] text-error" role="alert">Elige al menos una columna.</p> }
                </section>
              } @else {
                <section aria-label="Contenido del PDF" class="space-y-1.5">
                  <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Contenido del PDF</h3>
                  <label class="flex items-center gap-2 text-[13px] text-on-surface">
                    <input type="checkbox" [checked]="includeSummary()" (change)="setSummary($any($event.target).checked)" class="h-4 w-4 accent-brand-accentDeep" />
                    Incluir resumen ejecutivo
                  </label>
                  <label class="flex items-center gap-2 text-[13px]" [class]="includeSummary() ? 'text-on-surface' : 'text-on-surface-variant'">
                    <input type="checkbox" [checked]="includeCharts() && includeSummary()" [disabled]="!includeSummary()" (change)="includeCharts.set($any($event.target).checked)" class="h-4 w-4 accent-brand-accentDeep" />
                    Incluir gráficos
                  </label>
                </section>
              }
            </fieldset>
          }
        </div>

        @if (phase() !== 'done') {
          <footer class="space-y-2 border-t border-brand-grey px-5 py-4">
            <p [class]="'rounded-lg px-3 py-2 text-[13px] font-semibold ' + toneClass()" role="status" aria-live="polite">{{ summaryText() }}</p>
            @if (phase() === 'error') {
              <p class="rounded-lg bg-error-container px-3 py-2 text-[13px] text-on-error-container" role="alert">{{ errorText() }}</p>
            }
            <button type="button" (click)="generate()" [disabled]="!canExport()"
              [class]="focus + ' glass-btn flex w-full items-center justify-center gap-2 rounded-xl px-4 py-3 text-[14px] font-bold disabled:cursor-not-allowed disabled:opacity-50'">
              @if (phase() === 'generating') {
                <span class="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent motion-reduce:animate-none" aria-hidden="true"></span> Generando…
              } @else {
                <span class="material-symbols-outlined text-[20px]" aria-hidden="true">{{ phase() === 'error' ? 'refresh' : 'download' }}</span>
                {{ phase() === 'error' ? 'Reintentar' : 'Exportar ' + (format() === 'pdf' ? 'PDF' : 'Excel') }}
              }
            </button>
          </footer>
        }
      </aside>
    </div>
  `,
})
export class ExportDrawerComponent implements OnInit {
  private readonly api = inject(ExportService);
  private readonly techniciansApi = inject(TechniciansService);
  private readonly queue = inject(QueueService);
  private readonly toasts = inject(ToastService);
  private readonly destroyRef = inject(DestroyRef);

  readonly report = input.required<string>();
  readonly title = input('registros');
  /** Filtros de la pantalla que lo abre: el panel parte de ellos. */
  readonly initial = input<ExportFilterValues | null>(null);
  readonly filterKinds = input<ExportFilterKind[]>(['statuses', 'priorities']);
  readonly statusOptions = input<ChoiceOption[]>([]);
  readonly priorityOptions = input<ChoiceOption[]>([]);
  readonly closed = output<void>();

  readonly cards = FORMAT_CARDS;
  readonly shortcuts = SHORTCUTS;
  readonly focus = FOCUS;
  readonly field = FIELD;
  readonly today = dayString(new Date());
  private readonly closeButton = viewChild<ElementRef<HTMLButtonElement>>('closeButton');

  readonly format = signal<DocumentFormat>('pdf');
  readonly shortcut = signal<RangeShortcut>('all');
  readonly dateFrom = signal('');
  readonly dateTo = signal('');
  readonly statuses = signal<string[]>([]);
  readonly priorities = signal<string[]>([]);
  readonly categoryCodes = signal<string[]>([]);
  readonly technicianIds = signal<number[]>([]);
  readonly selected = signal<string[]>([]);
  readonly includeSummary = signal(true);
  readonly includeCharts = signal(true);

  readonly options = signal<ExportOptions | null>(null);
  readonly technicians = signal<Technician[]>([]);
  readonly categories = signal<RequestCategory[]>([]);
  readonly count = signal<CountState>({ status: 'idle' });
  readonly phase = signal<Phase>('idle');
  readonly errorText = signal('');
  readonly fileName = signal('');
  private lastFile: { blob: Blob; filename: string } | null = null;

  readonly columns = computed<ExportColumnInfo[]>(() => this.options()?.columns ?? []);
  readonly rangeError = computed(() => queueRangeError(this.dateFrom(), this.dateTo()));
  readonly filterValues = computed<ExportFilterValues>(() => ({
    statuses: this.statuses(), priorities: this.priorities(), categories: this.categoryCodes(),
    technicianIds: this.technicianIds(), dateFrom: this.dateFrom(), dateTo: this.dateTo(),
  }));
  /** Filtros del servidor, o `null` mientras el rango sea inválido (entonces no se consulta). */
  private readonly apiFilters = computed<ExportApiFilters | null>(() => (this.rangeError() ? null : toExportFilters(this.filterValues())));

  readonly summaryText = computed(() => {
    if (this.rangeError()) {
      return 'Corrige el rango de fechas para ver cuántos registros se exportarán.';
    }
    const state = this.count();
    if (state.status === 'failed') {
      return 'No se pudo contar los registros. Revisa tu conexión.';
    }
    if (state.status !== 'ready') {
      return 'Contando registros…';
    }
    return countMessage(state.total, state.max_rows, state.warn_rows).text;
  });
  readonly toneClass = computed(() => {
    const state = this.count();
    const tone = this.rangeError() || state.status === 'failed' ? 'error' : state.status === 'ready' ? countMessage(state.total, state.max_rows, state.warn_rows).tone : 'ok';
    return { ok: 'bg-brand-accentLight/40 text-brand-accentDeep', warn: 'bg-secondary-fixed text-on-secondary-fixed', error: 'bg-error-container text-on-error-container' }[tone];
  });
  readonly canExport = computed(() => {
    const state = this.count();
    return (
      this.phase() !== 'generating' &&
      !this.rangeError() &&
      state.status === 'ready' &&
      state.total > 0 &&
      !state.over_limit &&
      (this.format() === 'pdf' || this.selected().length > 0)
    );
  });

  constructor() {
    // Contador en vivo: cada cambio de filtros espera 300 ms y descarta la respuesta de una consulta anterior.
    toObservable(this.apiFilters)
      .pipe(
        distinctUntilChanged((a, b) => JSON.stringify(a) === JSON.stringify(b)),
        tap((filters) => this.count.set(filters ? { status: 'loading' } : { status: 'idle' })),
        debounceTime(300),
        switchMap((filters) =>
          filters
            ? this.api.count(this.report(), filters).pipe(
                tap((result) => this.count.set({ status: 'ready', ...result })),
                catchError(() => {
                  this.count.set({ status: 'failed' });
                  return of(null);
                }),
              )
            : of(null),
        ),
        takeUntilDestroyed(this.destroyRef),
      )
      .subscribe();
    effect(() => this.closeButton()?.nativeElement.focus(), { allowSignalWrites: false });
  }

  ngOnInit(): void {
    const initial = this.initial();
    if (initial) {
      this.statuses.set(initial.statuses);
      this.priorities.set(initial.priorities);
      this.categoryCodes.set(initial.categories);
      this.technicianIds.set(initial.technicianIds);
      this.dateFrom.set(initial.dateFrom);
      this.dateTo.set(initial.dateTo);
      this.shortcut.set(shortcutOf(initial.dateFrom, initial.dateTo, new Date()));
    }
    this.api.options(this.report()).subscribe({
      next: (options) => {
        this.options.set(options);
        this.selected.set(options.columns.filter((c) => c.default_xlsx).map((c) => c.key));
      },
      error: (error) => {
        this.phase.set('error');
        this.errorText.set(apiErrorMessage(error, 'No se pudieron cargar las opciones de exportación.'));
      },
    });
    if (this.filterKinds().includes('technicians')) {
      this.techniciansApi.list().subscribe({ next: (list) => this.technicians.set(list), error: () => this.technicians.set([]) });
    }
    if (this.filterKinds().includes('categories')) {
      this.queue.categories().subscribe({ next: (list) => this.categories.set(list), error: () => this.categories.set([]) });
    }
  }

  chip(active: boolean): string {
    return `${FOCUS} rounded-full border px-3 py-1 text-[12px] font-semibold ${
      active ? 'border-brand-sidebar bg-brand-sidebar !text-white' : 'border-brand-grey bg-transparent !text-brand-accentDeep hover:bg-surface-container'
    }`;
  }

  pickShortcut(id: RangeShortcut): void {
    this.shortcut.set(id);
    const range = shortcutRange(id, new Date());
    if (range) {
      this.dateFrom.set(range.from);
      this.dateTo.set(range.to);
    }
  }

  setDate(side: 'from' | 'to', value: string): void {
    (side === 'from' ? this.dateFrom : this.dateTo).set(value);
    this.shortcut.set('custom');
  }

  toggle(target: { (): string[]; update: (fn: (v: string[]) => string[]) => void }, value: string): void {
    target.update((list) => (list.includes(value) ? list.filter((v) => v !== value) : [...list, value]));
  }

  toggleNumber(target: { (): number[]; update: (fn: (v: number[]) => number[]) => void }, value: number): void {
    target.update((list) => (list.includes(value) ? list.filter((v) => v !== value) : [...list, value]));
  }

  selectAllColumns(): void {
    this.selected.set(this.columns().map((c) => c.key));
  }

  setSummary(checked: boolean): void {
    this.includeSummary.set(checked);
  }

  /** Genera y descarga el archivo; un segundo clic mientras se genera se ignora. */
  generate(): void {
    const filters = this.apiFilters();
    if (!this.canExport() || !filters) {
      return;
    }
    const format = this.format();
    this.phase.set('generating');
    this.errorText.set('');
    this.api
      .export(this.report(), format, {
        filters,
        columns: format === 'xlsx' ? this.columns().filter((c) => this.selected().includes(c.key)).map((c) => c.key) : undefined,
        include_summary: this.includeSummary(),
        include_charts: this.includeCharts() && this.includeSummary(),
      })
      .subscribe({
        next: (file) => {
          this.lastFile = file;
          saveBlob(file.blob, file.filename);
          this.fileName.set(file.filename);
          this.phase.set('done');
          this.toasts.success(`Archivo generado: ${file.filename}`);
        },
        error: async (error) => {
          this.errorText.set(apiErrorMessage(await readableError(error), 'No se pudo generar el archivo. Inténtalo de nuevo.'));
          this.phase.set('error');
        },
      });
  }

  downloadAgain(): void {
    if (this.lastFile) {
      saveBlob(this.lastFile.blob, this.lastFile.filename);
    }
  }

  close(): void {
    // Cerrar mientras se genera cancelaría la descarga a medias: se espera a que termine.
    if (this.phase() !== 'generating') {
      this.closed.emit();
    }
  }
}
