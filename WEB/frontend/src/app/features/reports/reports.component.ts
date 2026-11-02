import { AsyncPipe, DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';

import { Period } from '../../core/dashboard-kpis.service';
import { ExportFormat, ReportDefinition, ReportKey } from '../../core/reports.service';
import { HISTORY_PAGE_SIZE, ReportsState, ReportsStore } from '../../core/reports.store';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { formatChange } from '../dashboard/dashboard-format';
import { BuilderChange, ReportBuilderComponent } from './report-builder.component';
import { EMPTY_VALUES, describeFilters } from './report-filters';
import { ReportPreviewComponent } from './report-preview.component';
import { PaginationComponent } from '../../shared/pagination.component';

const PERIODS: { id: Period; label: string }[] = [
  { id: '7d', label: '7 días' },
  { id: '30d', label: '30 días' },
  { id: '12m', label: '12 meses' },
];
const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
/** Cuántas exportaciones recientes se ven antes de «Ver todas». */
const RECENT_COUNT = 5;
const FORMAT_LABELS: Record<ExportFormat, string> = { xlsx: 'Excel', pdf: 'PDF', csv: 'CSV' };

/** Reportes: galería a la izquierda, constructor de filtros al centro y vista previa a la derecha. */
@Component({
  selector: 'app-reports',
  standalone: true,
  imports: [AsyncPipe, DatePipe, ReportBuilderComponent, ReportPreviewComponent, ToastHostComponent, PaginationComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (vm$ | async; as vm) {
      <div class="space-y-4">
        <!-- Encabezado con ilustración -->
        <header class="relative overflow-hidden rounded-2xl bg-gradient-to-r from-brand-sidebar to-primary-container px-6 py-4 md:px-8 lg:min-h-[10rem]">
          <div class="relative z-10 flex flex-col gap-2.5 md:max-w-[58%]">
            <span class="glass inline-flex w-fit items-center gap-2 rounded-full px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-brand-accentDeep">
              <span class="h-2 w-2 rounded-full bg-brand-mustard"></span> Centro de reportes
            </span>
            <h1 class="text-[24px] font-extrabold uppercase leading-tight tracking-tight text-white">Datos listos <span class="text-brand-accentLight">para compartir</span></h1>
            <p class="max-w-xl text-[13px] leading-snug text-brand-grey">Elige un reporte, filtra, revisa la vista previa y descárgalo en Excel, PDF o CSV.</p>
          </div>
<!-- Ilustración en un panel claro: la imagen trae fondo casi blanco. -->
          <div class="pointer-events-none absolute inset-y-4 right-6 hidden aspect-[13/10] overflow-hidden rounded-2xl bg-surface-container-lowest shadow-lg lg:flex lg:items-center lg:justify-center" aria-hidden="true">
            <img src="assets/images/reportes-hero.webp" alt="" width="720" height="554" class="h-full w-full object-contain mix-blend-multiply" />
          </div>
        </header>

        <!-- Actividad (propia de Reportes; no repite las métricas del Dashboard) -->
        <section class="glass space-y-3 rounded-2xl p-4" aria-label="Actividad de reportes" [attr.aria-busy]="vm.overviewLoading">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex items-center gap-3">
              <span class="flex h-11 w-11 items-center justify-center rounded-xl bg-brand-accentLight/60 text-brand-accentDeep" aria-hidden="true"><span class="material-symbols-outlined text-[24px]">insights</span></span>
              <div>
                <h2 class="text-[17px] font-extrabold leading-tight text-brand-sidebar">Actividad de reportes</h2>
                <p class="text-[12px] text-on-surface-variant">Resumen de tu uso de reportes y exportaciones.</p>
              </div>
            </div>
            <div class="flex items-center gap-1 rounded-full bg-surface-container p-0.5" role="group" aria-label="Periodo de la actividad">
              <span class="material-symbols-outlined pl-2.5 text-[18px] text-brand-accentDeep" aria-hidden="true">calendar_month</span>
              @for (p of periods; track p.id) {
                <button type="button" (click)="store.setPeriod(p.id)" [attr.aria-pressed]="vm.period === p.id"
                  class="rounded-full px-3.5 py-1.5 text-[12px] font-semibold transition-colors active:scale-95"
                  [class]="focus + (vm.period === p.id ? ' bg-brand-sidebar !text-white' : ' bg-transparent !text-brand-accentDeep hover:bg-surface-container-high')">{{ p.label }}</button>
              }
            </div>
          </div>
          @if (vm.overview; as o) {
            <dl class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
              <div class="flex min-w-0 items-center gap-4 rounded-2xl border border-brand-accentLight/70 bg-surface-container-lowest p-4">
                <span class="flex h-14 w-14 shrink-0 items-center justify-center rounded-xl bg-brand-accentLight/60 text-brand-accentDeep" aria-hidden="true"><span class="material-symbols-outlined text-[30px]">description</span></span>
                <div class="min-w-0">
                  <dd class="m-0 ml-0 flex flex-wrap items-baseline gap-x-2">
                    <span class="text-[30px] font-extrabold leading-none text-brand-sidebar">{{ o.generated }}</span>
                    @if (change(o.change_pct)) { <span class="rounded-full bg-surface-container px-2 py-0.5 text-[11px] font-bold text-on-surface-variant">{{ change(o.change_pct) }}</span> }
                  </dd>
                  <dt class="m-0 text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Generados</dt>
                  <dd class="m-0 ml-0 mt-0.5 text-[12px] text-on-surface-variant">antes: {{ o.previous }} · {{ o.people }} {{ o.people === 1 ? 'persona' : 'personas' }}
                    @if (o.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-1.5 py-0.5 text-[10px] font-bold text-on-secondary-fixed">pocos datos</span> }</dd>
                </div>
              </div>
              <div class="flex min-w-0 items-center gap-4 rounded-2xl border border-brand-accentLight/70 bg-surface-container-lowest p-4">
                <span class="flex h-14 w-14 shrink-0 items-center justify-center rounded-xl bg-brand-accentLight/60 text-brand-accentDeep" aria-hidden="true"><span class="material-symbols-outlined text-[30px]">trending_up</span></span>
                <div class="min-w-0">
                  <dd class="m-0 ml-0 text-[30px] font-extrabold leading-none text-brand-sidebar">{{ o.most_used.length }}</dd>
                  <dt class="m-0 text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Más usados</dt>
                  <dd class="m-0 ml-0 mt-0.5 text-[12px] text-on-surface">
                    @for (u of o.most_used.slice(0, 2); track u.report; let i = $index) { <span class="block break-words">{{ i + 1 }}. <strong>{{ u.count }}</strong> · {{ u.title }}</span> }
                    @empty { <span class="text-on-surface-variant">Aún no se ha generado ninguno.</span> }
                  </dd>
                </div>
              </div>
              <div class="flex min-w-0 items-center gap-4 rounded-2xl border border-brand-accentLight/70 bg-surface-container-lowest p-4">
                <span class="flex h-14 w-14 shrink-0 items-center justify-center rounded-xl bg-brand-accentLight/60 text-brand-accentDeep" aria-hidden="true"><span class="material-symbols-outlined text-[30px]">summarize</span></span>
                <div class="min-w-0">
                  <dd class="m-0 ml-0 text-[30px] font-extrabold leading-none text-brand-sidebar">{{ formats(o.by_format).length }}</dd>
                  <dt class="m-0 text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Formatos</dt>
                  <dd class="m-0 ml-0 mt-0.5 text-[12px] text-on-surface">
                    @for (f of formats(o.by_format); track f.key) { <span class="mr-3"><strong>{{ f.count }}</strong> {{ f.label }}</span> }
                    @empty { <span class="text-on-surface-variant">—</span> }
                  </dd>
                </div>
              </div>
              <div class="flex min-w-0 items-center gap-4 rounded-2xl border border-brand-accentLight/70 bg-surface-container-lowest p-4">
                <span class="flex h-14 w-14 shrink-0 items-center justify-center rounded-xl bg-brand-accentLight/60 text-brand-accentDeep" aria-hidden="true"><span class="material-symbols-outlined text-[30px]">schedule</span></span>
                <div class="min-w-0">
                  <dt class="m-0 text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Última exportación</dt>
                  <dd class="m-0 ml-0 mt-0.5 text-[12px] text-on-surface">
                    @if (o.last_export; as l) {
                      <span class="block break-words text-[14px] font-bold text-brand-sidebar">{{ l.title }}</span>
                      <span class="block break-words text-on-surface-variant">{{ formatLabel(l.export_format) }} · {{ l.row_count }} filas · {{ l.by ?? 'sistema' }} · {{ l.at | date: 'dd/MM HH:mm' }}</span>
                    } @else { <span class="text-on-surface-variant">Ninguna todavía.</span> }
                  </dd>
                </div>
              </div>
            </dl>
          } @else if (vm.overviewLoading) {
            <div class="h-24 animate-pulse rounded bg-surface-container motion-reduce:animate-none" role="status" aria-label="Cargando actividad"></div>
          } @else {
            <p class="text-[12px] text-on-surface-variant">La actividad de reportes no está disponible en este momento.</p>
          }
        </section>

        @if (vm.catalogError) {
          <p role="alert" class="flex flex-wrap items-center gap-3 rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">
            {{ vm.catalogError }}
            <button type="button" (click)="store.load()" class="bg-transparent p-0 font-bold underline !text-on-error-container">Reintentar</button>
          </p>
        }

        <!-- Galería: mosaico de tarjetas iguales -->
        <nav class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6" aria-label="Galería de reportes">
          @if (vm.catalog; as catalog) {
            @for (report of catalog.reports; track report.key) {
              <button type="button" (click)="select(report.key)" [attr.aria-pressed]="vm.selected === report.key"
                [class]="focus + ' flex h-full min-h-[9rem] flex-col items-start gap-3 rounded-2xl border p-4 text-left transition-all hover:-translate-y-0.5 hover:shadow-md motion-reduce:transition-none motion-reduce:hover:translate-y-0 ' + (vm.selected === report.key ? 'border-brand-accentDeep bg-brand-accentLight/50 ring-2 ring-brand-accentDeep/30' : 'border-brand-accentLight/70 bg-surface-container-lowest')">
                <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl" [class]="vm.selected === report.key ? 'bg-brand-sidebar text-white' : 'bg-brand-accentLight/60 text-brand-accentDeep'"><span class="material-symbols-outlined text-[24px]" aria-hidden="true">{{ report.icon }}</span></span>
                <span class="min-w-0">
                  <span class="block text-[14px] font-extrabold leading-tight text-brand-sidebar">{{ report.title }}</span>
                  <span class="mt-1.5 line-clamp-3 block text-[12px] leading-4 text-on-surface-variant">{{ report.description }}</span>
                </span>
              </button>
            }
          } @else if (vm.catalogLoading) {
            @for (n of skeleton; track n) { <div class="h-36 animate-pulse rounded-2xl bg-surface-container motion-reduce:animate-none" role="status" aria-label="Cargando galería"></div> }
          }
        </nav>

        <!-- Filtros a la izquierda; a la derecha, vista previa y exportaciones recientes -->
        @if (definition(vm); as def) {
          <div class="grid grid-cols-1 gap-4 lg:grid-cols-[19rem_minmax(0,1fr)]">
            <app-report-builder [definition]="def" (changed)="onChange($event)" (formatChange)="exportFormat.set($event)" />
            <section class="min-w-0 rounded-2xl border border-brand-accentLight/70 bg-surface-container-lowest shadow-sm" aria-label="Reporte y exportaciones">
              <app-report-preview [preview]="vm.preview" [title]="def.title" [icon]="def.icon" [summary]="summary(def)" [loading]="vm.previewLoading"
                [error]="vm.previewError" [invalid]="!current().valid" [maxRows]="vm.catalog?.max_rows ?? 10000">
                <ng-container actions>
                  <button type="button" (click)="refreshPreview()" [disabled]="!current().valid || vm.previewLoading"
                    [class]="focus + ' flex items-center gap-1.5 rounded-full border border-brand-accentLight bg-brand-accentLight/40 px-4 py-2 text-[13px] font-semibold !text-brand-sidebar hover:bg-brand-accentLight/70 disabled:opacity-50'">
                    <span class="material-symbols-outlined text-[18px]" aria-hidden="true">visibility</span> Vista previa
                  </button>
                  <button type="button" (click)="store.export(exportFormat(), current().values)" [disabled]="!canExport(vm) || vm.exporting !== null"
                    class="glass-btn flex items-center gap-1.5 rounded-full px-4 py-2 text-[13px] font-bold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
                    <span class="material-symbols-outlined text-[18px]" aria-hidden="true">file_download</span>
                    {{ vm.exporting ? 'Generando…' : 'Exportar ' + formatLabel(exportFormat()) }}
                  </button>
                </ng-container>
              </app-report-preview>
              @if (!canExport(vm) && vm.exporting === null) {
                <p class="px-4 pb-2 text-[11px] text-on-surface-variant">{{ exportHint(vm) }}</p>
              }

              <!-- Exportaciones recientes -->
              <section class="border-t border-brand-accentLight/70 px-4 pb-4 pt-3" aria-label="Exportaciones recientes">
                <div class="flex items-center justify-between gap-2">
                  <h2 class="flex items-center gap-2 text-[14px] font-extrabold text-brand-sidebar"><span class="material-symbols-outlined text-[20px] text-brand-accentDeep" aria-hidden="true">history</span>Exportaciones recientes</h2>
                  @if (vm.historyTotal > recentCount) {
                    <button type="button" (click)="showAll.set(!showAll())" [attr.aria-expanded]="showAll()"
                      [class]="focus + ' flex items-center gap-1 rounded-lg bg-transparent px-2 py-1 text-[12px] font-semibold !text-brand-accentDeep hover:bg-surface-container'">
                      {{ showAll() ? 'Ver menos' : 'Ver todas' }} <span class="material-symbols-outlined text-[16px]" aria-hidden="true">{{ showAll() ? 'expand_less' : 'arrow_forward' }}</span>
                    </button>
                  }
                </div>
                @if (vm.history.length > 0) {
                  <table class="mt-2 w-full border-collapse text-left text-[12px]">
                    <caption class="sr-only">Últimos reportes generados</caption>
                    <thead><tr class="text-[11px] uppercase tracking-wider text-on-surface-variant">
                      <th scope="col" class="px-2 py-1.5 font-bold">Reporte</th><th scope="col" class="px-2 py-1.5 font-bold">Formato</th>
                      <th scope="col" class="px-2 py-1.5 text-right font-bold">Filas</th><th scope="col" class="px-2 py-1.5 font-bold">Por</th><th scope="col" class="px-2 py-1.5 font-bold">Cuándo</th>
                    </tr></thead>
                    <tbody>
                      @for (run of shownHistory(vm); track run.id) {
                        <tr class="border-t border-brand-grey/60">
                          <td class="break-words px-2 py-1.5 font-semibold text-on-surface"><span class="mr-1.5 inline-block align-middle material-symbols-outlined text-[16px] text-brand-accentDeep" aria-hidden="true">description</span>{{ run.title }}</td>
                          <td class="px-2 py-1.5 text-on-surface">{{ formatLabel(run.export_format) }}</td>
                          <td class="px-2 py-1.5 text-right text-on-surface">{{ run.row_count }}</td>
                          <td class="break-words px-2 py-1.5 text-on-surface">{{ run.by ?? 'sistema' }}</td>
                          <td class="px-2 py-1.5 text-on-surface-variant">{{ run.at | date: 'dd/MM/yy HH:mm' }}</td>
                        </tr>
                      }
                    </tbody>
                  </table>
                  @if (showAll()) {
                    <app-pagination noun="exportaciones" [page]="vm.historyPage" [pageSize]="pageSize" [total]="vm.historyTotal" (pageChange)="store.loadHistory($event)" />
                  } @else {
                    <p class="mt-1 text-[11px] text-on-surface-variant">{{ vm.historyTotal }} {{ vm.historyTotal === 1 ? 'exportación' : 'exportaciones' }}</p>
                  }
                } @else {
                  <p class="mt-2 text-[12px] text-on-surface-variant">Todavía no se ha exportado ningún reporte.</p>
                }
              </section>
            </section>
          </div>
        }
      </div>
      <app-toast-host />
    }
  `,
})
export class ReportsComponent implements OnInit {
  readonly store = inject(ReportsStore);

  readonly vm$ = this.store.state$;
  readonly periods = PERIODS;
  readonly focus = FOCUS;
  readonly skeleton = [1, 2, 3, 4];
  readonly pageSize = HISTORY_PAGE_SIZE;
  readonly pageButton = `${FOCUS} rounded-full bg-transparent px-3 py-1 text-[12px] font-bold !text-brand-accentDeep hover:bg-surface-container-high disabled:opacity-40`;
  readonly change = formatChange;
  readonly formatLabel = (format: ExportFormat): string => FORMAT_LABELS[format];
  /** Últimos valores del constructor: alimentan la exportación y el estado de la vista previa. */
  readonly current = signal<BuilderChange>({ values: EMPTY_VALUES, compare: false, valid: true });
  /** Formato elegido en el panel de filtros; lo usa el botón «Exportar». */
  readonly exportFormat = signal<ExportFormat>('xlsx');
  /** Con «Ver todas» se muestra el historial completo y paginado; si no, solo las últimas. */
  readonly showAll = signal(false);
  readonly recentCount = RECENT_COUNT;

  shownHistory(vm: ReportsState): ReportsState['history'] {
    return this.showAll() ? vm.history : vm.history.slice(0, RECENT_COUNT);
  }

  /** Vuelve a pedir la vista previa con los filtros de ahora. */
  refreshPreview(): void {
    const { values, compare, valid } = this.current();
    if (valid) {
      this.store.requestPreview(values, compare);
    }
  }

  ngOnInit(): void {
    this.store.load();
  }

  definition(vm: ReportsState): ReportDefinition | null {
    return vm.catalog?.reports.find((report) => report.key === vm.selected) ?? null;
  }

  select(key: ReportKey): void {
    this.store.select(key);
  }

  onChange(change: BuilderChange): void {
    this.current.set(change);
    if (change.valid) {
      this.store.requestPreview(change.values, change.compare);
    }
  }

  summary(def: ReportDefinition): string {
    return describeFilters(def, this.current().values);
  }

  canExport(vm: ReportsState): boolean {
    return this.current().valid && !!vm.preview && vm.preview.total_rows > 0 && !vm.preview.truncated && !vm.previewLoading && !vm.previewError;
  }

  exportHint(vm: ReportsState): string {
    if (!this.current().valid) {
      return 'Corrige los filtros marcados para exportar.';
    }
    if (vm.preview?.truncated) {
      return 'Hay demasiadas filas: acota los filtros.';
    }
    return vm.preview && vm.preview.total_rows === 0 ? 'No hay filas que exportar con estos filtros.' : 'Espera la vista previa para exportar.';
  }

  formats(byFormat: Record<string, number>): { key: string; label: string; count: number }[] {
    return Object.entries(byFormat).map(([key, count]) => ({ key, count, label: FORMAT_LABELS[key as ExportFormat] ?? key }));
  }
}

