import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import { ReportPreview } from '../../core/reports.service';
import { formatChange } from '../dashboard/dashboard-format';

/** Vista previa del reporte: primeras filas, total, aviso de límite y comparativo con el periodo anterior. */
@Component({
  selector: 'app-report-preview',
  standalone: true,
  imports: [DatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="rounded-2xl border border-brand-grey bg-surface-container-lowest" aria-label="Vista previa" [attr.aria-busy]="loading()">
      <header class="flex flex-wrap items-start justify-between gap-2 border-b border-brand-grey px-4 py-3">
        <div class="min-w-0">
          <h2 class="text-[15px] font-bold text-on-surface">{{ preview()?.title ?? title() }}</h2>
          <p class="text-[12px] text-on-surface-variant">{{ summary() }}</p>
        </div>
        @if (preview(); as p) {
          <span class="rounded-full bg-brand-accentLight/60 px-2.5 py-1 text-[12px] font-bold text-brand-accentDeep">{{ p.total_rows }}{{ p.truncated ? '+' : '' }} filas</span>
        }
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
          <div class="overflow-x-auto p-4 pt-3" [class.opacity-60]="loading()">
            <table class="w-full min-w-[520px] border-collapse text-left text-[12px]">
              <caption class="sr-only">Primeras filas de {{ p.title }}</caption>
              <thead>
                <tr class="border-b border-brand-grey text-[11px] uppercase tracking-wider text-on-surface-variant">
                  @for (col of p.columns; track col.key) { <th scope="col" class="whitespace-nowrap px-2 py-2 font-bold">{{ col.header }}</th> }
                </tr>
              </thead>
              <tbody>
                @for (row of p.rows; track $index) {
                  <tr class="border-b border-brand-grey/60 last:border-0">
                    @for (col of p.columns; track col.key) { <td class="max-w-[14rem] truncate px-2 py-1.5 text-on-surface" [attr.title]="row[col.key]">{{ row[col.key] }}</td> }
                  </tr>
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
  readonly summary = input('');
  readonly loading = input(false);
  readonly error = input('');
  /** El formulario del constructor tiene errores: no se pide la vista previa. */
  readonly invalid = input(false);
  readonly maxRows = input(10_000);

  readonly skeleton = [1, 2, 3, 4, 5];
  readonly change = formatChange;
}
