import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, input, signal } from '@angular/core';

import { PreviewColumn, ReportPreview } from '../../core/reports.service';
import { formatChange } from '../dashboard/dashboard-format';

/** Columnas que se ven en la tabla; el resto va al detalle expandible de cada fila. */
export const MAX_VISIBLE_COLUMNS = 7;

/** Vista previa del reporte: primeras filas, total, aviso de límite y comparativo con el periodo anterior. */
@Component({
  selector: 'app-report-preview',
  standalone: true,
  imports: [DatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section aria-label="Vista previa" [attr.aria-busy]="loading()">
      <header class="flex flex-wrap items-center justify-between gap-3 px-4 pb-3 pt-4">
        <div class="flex min-w-0 items-center gap-3">
          <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-brand-accentLight/60 text-brand-accentDeep" aria-hidden="true"><span class="material-symbols-outlined text-[24px]">{{ icon() }}</span></span>
          <div class="min-w-0">
            <h2 class="break-words text-[16px] font-extrabold leading-tight text-brand-sidebar">{{ preview()?.title ?? title() }}</h2>
            <p class="break-words text-[12px] text-on-surface-variant">{{ summary() }}
              @if (preview(); as p) { · <span class="font-bold text-brand-accentDeep">{{ p.total_rows }}{{ p.truncated ? '+' : '' }} filas</span> }
            </p>
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-2"><ng-content select="[actions]" /></div>
      </header>

      @if (invalid()) {
        <p role="status" class="m-4 rounded-lg bg-surface-container px-3 py-3 text-[13px] text-on-surface-variant">
          Corrige los filtros marcados para ver la vista previa.
        </p>
      } @else if (error()) {
        <p role="alert" class="m-4 rounded-lg bg-error-container px-3 py-3 text-[13px] text-on-error-container">{{ error() }}</p>
      } @else if (preview()) {
        @let p = preview()!;
        @if (p.comparison; as c) {
          <div class="mx-4 mt-3 grid grid-cols-3 gap-2 rounded-xl bg-surface-container-low p-3 text-center" aria-label="Comparativo con el periodo anterior">
            <div><p class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Este periodo</p><p class="text-[20px] font-bold text-on-surface">{{ c.current_total }}</p></div>
            <div><p class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Periodo anterior</p><p class="text-[20px] font-bold text-on-surface">{{ c.previous_total }}</p>
              <p class="text-[11px] text-on-surface-variant">{{ c.previous_from | date: 'dd/MM/yy' }} – {{ c.previous_to | date: 'dd/MM/yy' }}</p></div>
            <div><p class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Variación</p>
              @if (change(c.change_pct)) { <p class="text-[20px] font-bold text-on-surface">{{ change(c.change_pct) }}</p> }
              @else { <p class="text-[20px] font-bold text-on-surface-variant" title="El periodo anterior no tiene filas">—</p> }
            </div>
          </div>
        }
        @if (p.truncated) {
          <p role="alert" class="mx-4 mt-3 rounded-lg bg-secondary-fixed px-3 py-2 text-[12px] font-semibold text-on-secondary-fixed">
            Hay más de {{ maxRows() }} filas. Acota los filtros para poder exportar.
          </p>
        }
        @if (p.rows.length > 0) {
          @let shown = visible(p.columns);
          @let extra = hidden(p.columns);
          <!-- Sin deslizamiento horizontal: la tabla ocupa su ancho, las celdas largas saltan de línea y las columnas que no caben van al detalle de la fila. -->
          <div class="p-4 pt-3" [class.opacity-60]="loading()">
            <table class="w-full table-auto border-collapse text-left text-[12px]">
              <caption class="sr-only">Primeras filas de {{ p.title }}</caption>
              <thead>
                <tr class="border-b border-brand-grey text-[11px] uppercase tracking-wider text-on-surface-variant">
                  @if (extra.length > 0) { <th scope="col" class="w-8 px-1 py-2"><span class="sr-only">Detalle</span></th> }
                  @for (col of shown; track col.key) { <th scope="col" class="px-1.5 py-2 align-bottom font-bold leading-4">{{ col.header }}</th> }
                </tr>
              </thead>
              <tbody>
                @for (row of p.rows; track $index) {
                  <tr class="border-b border-brand-grey/60 align-top last:border-0">
                    @if (extra.length > 0) {
                      <td class="px-1 py-1.5">
                        <button type="button" (click)="toggle($index)" [attr.aria-expanded]="isOpen($index)" [attr.aria-label]="(isOpen($index) ? 'Ocultar' : 'Ver') + ' el detalle de la fila ' + ($index + 1)"
                          class="flex h-6 w-6 items-center justify-center rounded-md bg-transparent !text-brand-accentDeep hover:bg-surface-container-high focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
                          <span class="material-symbols-outlined text-[18px]" aria-hidden="true">{{ isOpen($index) ? 'expand_less' : 'expand_more' }}</span>
                        </button>
                      </td>
                    }
                    @for (col of shown; track col.key) { <td class="break-words px-1.5 py-1.5 leading-4 text-on-surface [overflow-wrap:anywhere]" [attr.title]="row[col.key]">{{ row[col.key] }}</td> }
                  </tr>
                  @if (extra.length > 0 && isOpen($index)) {
                    <tr class="border-b border-brand-grey/60 bg-surface-container-low">
                      <td [attr.colspan]="shown.length + 1" class="px-3 py-2">
                        <dl class="grid grid-cols-2 gap-x-6 gap-y-1.5 md:grid-cols-3">
                          @for (col of extra; track col.key) {
                            <div class="min-w-0"><dt class="m-0 text-[10px] font-bold uppercase tracking-wider text-on-surface-variant">{{ col.header }}</dt><dd class="m-0 ml-0 break-words text-[12px] text-on-surface [overflow-wrap:anywhere]">{{ row[col.key] || '—' }}</dd></div>
                          }
                        </dl>
                      </td>
                    </tr>
                  }
                }
              </tbody>
            </table>
          </div>
          <p class="px-4 pb-3 text-[11px] text-on-surface-variant">Mostrando {{ p.rows.length }} de {{ p.total_rows }}{{ p.truncated ? '+' : '' }} filas.</p>
        } @else {
          <div class="flex flex-col items-center gap-2 px-6 py-10 text-center">
            <img src="assets/images/cola-vacia.svg" alt="" width="192" height="167" class="h-auto w-40 mix-blend-multiply" />
            <h3 class="text-[15px] font-bold text-on-surface">Ninguna fila coincide con estos filtros</h3>
            <p class="max-w-sm text-[13px] text-on-surface-variant">Amplía el rango de fechas o quita algún filtro.</p>
          </div>
        }
      } @else if (loading()) {
        <div class="space-y-2 p-4" role="status" aria-label="Generando vista previa">
          @for (n of skeleton; track n) { <div class="h-8 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div> }
        </div>
      } @else {
        <p class="m-4 text-[13px] text-on-surface-variant">Elige un reporte para ver su vista previa.</p>
      }
    </section>
  `,
})
export class ReportPreviewComponent {
  readonly preview = input<ReportPreview | null>(null);
  readonly title = input('Vista previa');
  /** Icono del reporte, junto al título. */
  readonly icon = input('description');
  readonly summary = input('');
  readonly loading = input(false);
  readonly error = input('');
  /** El formulario del constructor tiene errores: no se pide la vista previa. */
  readonly invalid = input(false);
  readonly maxRows = input(10_000);

  readonly skeleton = [1, 2, 3, 4, 5];
  readonly change = formatChange;
  /** Filas con el detalle abierto (las columnas que no caben en la tabla). */
  private readonly open = signal<ReadonlySet<number>>(new Set());

  /** Columnas esenciales: las primeras que caben en un escritorio común sin scroll (1366 px). */
  visible(columns: readonly PreviewColumn[]): PreviewColumn[] {
    return columns.slice(0, MAX_VISIBLE_COLUMNS);
  }

  hidden(columns: readonly PreviewColumn[]): PreviewColumn[] {
    return columns.slice(MAX_VISIBLE_COLUMNS);
  }

  isOpen = (index: number): boolean => this.open().has(index);

  toggle(index: number): void {
    this.open.update((set) => {
      const next = new Set(set);
      if (!next.delete(index)) {
        next.add(index);
      }
      return next;
    });
  }
}
