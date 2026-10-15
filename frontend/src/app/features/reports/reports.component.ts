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
        <header class="relative overflow-hidden rounded-2xl bg-gradient-to-r from-brand-sidebar to-primary-container px-6 py-6 md:px-8">
          <div class="relative z-10 flex flex-col gap-4 md:max-w-[58%]">
            <span class="glass inline-flex w-fit items-center gap-2 rounded-full px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-brand-accentDeep">
              <span class="h-2 w-2 rounded-full bg-brand-mustard"></span> Centro de reportes
            </span>
            <h1 class="text-[26px] font-extrabold uppercase leading-tight tracking-tight text-white">Datos listos <span class="text-brand-accentLight">para compartir</span></h1>
            <p class="max-w-xl text-[14px] leading-relaxed text-brand-grey">Elige un reporte, filtra, revisa la vista previa y descárgalo en Excel, PDF o CSV.</p>
            <div class="glass flex w-fit rounded-full p-0.5" role="group" aria-label="Periodo de la actividad">
              @for (p of periods; track p.id) {
                <button type="button" (click)="store.setPeriod(p.id)" [attr.aria-pressed]="vm.period === p.id"
                  class="rounded-full px-3 py-1 text-[12px] font-semibold transition-colors active:scale-95"
                  [class]="focus + (vm.period === p.id ? ' bg-brand-sidebar !text-white' : ' bg-transparent !text-brand-accentDeep hover:bg-surface-container')">{{ p.label }}</button>
              }
            </div>
          </div>
<!-- Ilustración en un panel claro: la imagen trae fondo casi blanco. -->
          <div class="pointer-events-none absolute inset-y-4 right-6 hidden aspect-[13/10] overflow-hidden rounded-2xl bg-surface-container-lowest shadow-lg lg:flex lg:items-center lg:justify-center" aria-hidden="true">
            <img src="assets/images/reportes-hero.webp" alt="" width="720" height="554" class="h-full w-full object-contain mix-blend-multiply" />
          </div>
        </header>

        <!-- Actividad (propia de Reportes; no repite las métricas del Dashboard) -->
        <section class="glass rounded-2xl px-4 py-3" aria-label="Actividad de reportes" [attr.aria-busy]="vm.overviewLoading">
          @if (vm.overview; as o) {
            <dl class="grid grid-cols-2 gap-x-6 gap-y-3 md:grid-cols-4">
              <div>
                <dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Generados</dt>
                <dd class="mt-0.5 flex flex-wrap items-baseline gap-x-2">
                  <span class="text-[22px] font-bold text-on-surface">{{ o.generated }}</span>
                  @if (change(o.change_pct)) { <span class="rounded-full bg-surface-container px-2 py-0.5 text-[11px] font-bold text-on-surface-variant">{{ change(o.change_pct) }}</span> }
                  <span class="w-full text-[11px] text-on-surface-variant">antes: {{ o.previous }} · {{ o.people }} {{ o.people === 1 ? 'persona' : 'personas' }}
                    @if (o.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-1.5 py-0.5 text-[10px] font-bold text-on-secondary-fixed">pocos datos</span> }</span>
                </dd>
              </div>
              <div>
                <dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Más usados</dt>
                <dd class="mt-0.5 text-[12px] text-on-surface">
                  @for (u of o.most_used.slice(0, 3); track u.report) { <span class="block truncate"><strong>{{ u.count }}</strong> · {{ u.title }}</span> }
                  @empty { <span class="text-on-surface-variant">Aún no se ha generado ninguno.</span> }
                </dd>
              </div>
              <div>
                <dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Formatos</dt>
                <dd class="mt-0.5 text-[12px] text-on-surface">
                  @for (f of formats(o.by_format); track f.key) { <span class="mr-2"><strong>{{ f.count }}</strong> {{ f.label }}</span> }
                  @empty { <span class="text-on-surface-variant">—</span> }
                </dd>
              </div>
              <div>
                <dt class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Última exportación</dt>
                <dd class="mt-0.5 text-[12px] text-on-surface">
                  @if (o.last_export; as l) {
                    <span class="block truncate font-semibold">{{ l.title }}</span>
                    <span class="block text-on-surface-variant">{{ formatLabel(l.export_format) }} · {{ l.row_count }} filas · {{ l.by ?? 'sistema' }} · {{ l.at | date: 'dd/MM HH:mm' }}</span>
                  } @else { <span class="text-on-surface-variant">Ninguna todavía.</span> }
                </dd>
              </div>
            </dl>
          } @else if (vm.overviewLoading) {
            <div class="h-12 animate-pulse rounded bg-surface-container motion-reduce:animate-none" role="status" aria-label="Cargando actividad"></div>
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

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-[15rem_minmax(0,1fr)] xl:grid-cols-[15rem_19rem_minmax(0,1fr)]">
          <!-- Galería -->
          <nav class="space-y-2 lg:row-span-2 xl:row-span-1" aria-label="Galería de reportes">
            @if (vm.catalog; as catalog) {
              @for (report of catalog.reports; track report.key) {
                <button type="button" (click)="select(report.key)" [attr.aria-pressed]="vm.selected === report.key"
                  [class]="focus + ' flex w-full items-start gap-3 rounded-2xl border p-3 text-left transition-all hover:-translate-y-0.5 hover:shadow-md motion-reduce:transition-none motion-reduce:hover:translate-y-0 ' + (vm.selected === report.key ? 'border-brand-accentDeep bg-brand-accentLight/40 ring-2 ring-brand-accentDeep/30' : 'border-brand-grey bg-surface-container-lowest')">
                  <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-brand-accentLight/60 text-brand-accentDeep"><span class="material-symbols-outlined text-[20px]" aria-hidden="true">{{ report.icon }}</span></span>
                  <span class="min-w-0">
                    <span class="block text-[13px] font-bold text-on-surface">{{ report.title }}</span>
                    <span class="mt-0.5 block text-[11px] leading-4 text-on-surface-variant">{{ report.description }}</span>
                  </span>
                </button>
              }
            } @else if (vm.catalogLoading) {
              @for (n of skeleton; track n) { <div class="h-20 animate-pulse rounded-2xl bg-surface-container motion-reduce:animate-none" role="status" aria-label="Cargando galería"></div> }
            }
          </nav>

          @if (definition(vm); as def) {
            <div>
              <app-report-builder [definition]="def" [canExport]="canExport(vm)" [exportHint]="exportHint(vm)" [exporting]="vm.exporting"
                (changed)="onChange($event)" (exportRequested)="store.export($event, current().values)" />
            </div>
            <div class="min-w-0 lg:col-start-2 xl:col-start-3">
              <app-report-preview [preview]="vm.preview" [title]="def.title" [summary]="summary(def)" [loading]="vm.previewLoading"
                [error]="vm.previewError" [invalid]="!current().valid" [maxRows]="vm.catalog?.max_rows ?? 10000" />
            </div>
          }
        </div>

        <!-- Historial -->
        <section class="glass rounded-2xl p-4" aria-label="Exportaciones recientes">
          <h2 class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Exportaciones recientes</h2>
          @if (vm.history.length > 0) {
            <div class="mt-2 overflow-x-auto">
              <table class="w-full min-w-[560px] border-collapse text-left text-[12px]">
                <caption class="sr-only">Últimos reportes generados</caption>
                <thead><tr class="border-b border-brand-grey text-[11px] uppercase tracking-wider text-on-surface-variant">
                  <th scope="col" class="px-2 py-1.5 font-bold">Reporte</th><th scope="col" class="px-2 py-1.5 font-bold">Formato</th>
                  <th scope="col" class="px-2 py-1.5 text-right font-bold">Filas</th><th scope="col" class="px-2 py-1.5 font-bold">Por</th><th scope="col" class="px-2 py-1.5 font-bold">Cuándo</th>
                </tr></thead>
                <tbody>
                  @for (run of vm.history; track run.id) {
                    <tr class="border-b border-brand-grey/60 last:border-0">
                      <td class="px-2 py-1.5 font-semibold text-on-surface">{{ run.title }}</td>
                      <td class="px-2 py-1.5 text-on-surface">{{ formatLabel(run.export_format) }}</td>
                      <td class="px-2 py-1.5 text-right text-on-surface">{{ run.row_count }}</td>
                      <td class="px-2 py-1.5 text-on-surface">{{ run.by ?? 'sistema' }}</td>
                      <td class="px-2 py-1.5 text-on-surface-variant">{{ run.at | date: 'dd/MM/yy HH:mm' }}</td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
            <app-pagination noun="exportaciones" [page]="vm.historyPage" [pageSize]="pageSize" [total]="vm.historyTotal" (pageChange)="store.loadHistory($event)" />
          } @else {
            <p class="mt-2 text-[12px] text-on-surface-variant">Todavía no se ha exportado ningún reporte.</p>
          }
        </section>
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

