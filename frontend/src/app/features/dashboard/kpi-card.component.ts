import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';
import { RouterLink } from '@angular/router';

import { Tone, formatChange, sparkline } from './dashboard-format';

const SPARK_W = 120;
const SPARK_H = 32;

/** Pares texto/fondo con contraste WCAG AA (>= 4.5:1) para texto pequeño. */
const TONE_BADGE: Record<Tone, string> = {
  good: 'bg-[#D1FAE5] text-[#047857]',
  bad: 'bg-[#FEF3C7] text-[#92400E]',
  neutral: 'bg-[#F1F5F9] text-[#475569]',
};
/** Trazos gráficos: >= 3:1 sobre blanco. */
const TONE_LINE: Record<Tone, string> = { good: '#047857', bad: '#A16207', neutral: '#2563EB' };

/** Tarjeta KPI: valor, estadística descriptiva, variación vs. el periodo anterior y sparkline. */
@Component({
  selector: 'app-kpi-card',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <a [routerLink]="link()" [queryParams]="queryParams()"
      class="group flex min-h-[148px] flex-col gap-2 rounded-[18px] bg-white p-4 shadow-[0_8px_25px_rgba(15,23,42,0.05)] transition-all duration-200 hover:-translate-y-[3px] hover:shadow-[0_12px_28px_rgba(37,99,235,0.12)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#2563EB] motion-reduce:transition-none motion-reduce:hover:translate-y-0"
      [attr.aria-label]="label() + ': ' + (empty() ? 'sin datos suficientes' : value() + (lowSample() ? ', pocos datos' : ''))">
      <div class="flex items-start justify-between gap-3">
        <div class="flex items-center gap-2">
          <span class="flex h-8 w-8 items-center justify-center rounded-full bg-[#DBEAFE] text-[#2563EB]">
            <span class="material-symbols-outlined text-[18px]" aria-hidden="true">{{ icon() }}</span>
          </span>
          <span class="text-[12px] font-bold uppercase tracking-wider text-[#64748B]">{{ label() }}</span>
        </div>
        <span class="material-symbols-outlined text-[18px] text-[#64748B] transition-transform group-hover:translate-x-0.5 motion-reduce:transition-none" aria-hidden="true">arrow_forward</span>
      </div>

      @if (empty()) {
        <div class="flex flex-1 flex-col justify-center">
          <span class="text-[22px] font-bold leading-7 text-[#64748B]">—</span>
          <p class="text-[12px] text-[#64748B]">{{ emptyText() }}</p>
        </div>
      } @else {
        <div class="flex items-end justify-between gap-3">
          <div class="min-w-0">
            <span class="block text-[28px] font-bold leading-8 text-[#0b1f3a]">{{ value() }}</span>
            <p class="text-[12px] text-[#64748B]">{{ caption() }}</p>
          </div>
          @if (spark(); as points) {
            <svg [attr.viewBox]="'0 0 ' + sparkW + ' ' + sparkH" class="h-8 w-[90px] shrink-0 sm:w-[110px]" role="img" aria-label="Tendencia del periodo">
              <polyline [attr.points]="points" fill="none" [attr.stroke]="lineColor()" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
          }
        </div>
        @if (detail()) {
          <p class="text-[11px] font-medium text-[#475569]">{{ detail() }}</p>
        }
        @if (spread()) {
          <p class="text-[11px] text-[#64748B]" [attr.title]="spreadTitle()">{{ spread() }}</p>
        }
        <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px]">
          @if (change()) {
            <span class="rounded-full px-2 py-0.5 font-bold" [class]="badgeClass()">{{ change() }}</span>
            <span class="text-[#64748B]">{{ changeHint() }}</span>
          }
          @if (n() !== null) {
            <span class="text-[#64748B]">n = {{ n() }}</span>
          }
          @if (lowSample()) {
            <span class="rounded-full bg-[#FEF3C7] px-2 py-0.5 font-bold text-[#92400E]">Pocos datos</span>
          }
        </div>
        <ng-content />
      }
    </a>
  `,
})
export class KpiCardComponent {
  readonly label = input.required<string>();
  readonly icon = input.required<string>();
  readonly link = input.required<string>();
  readonly queryParams = input<Record<string, string> | null>(null);
  /** Valor ya formateado; `null` activa el estado vacío. */
  readonly value = input<string | null>(null);
  readonly caption = input('');
  /** Línea de apoyo bajo el valor, p. ej. «Prom. 5,2 h · P90 18 h». */
  readonly detail = input('');
  /** Dispersión (mín, máx, desviación); se muestra y también como tooltip. */
  readonly spread = input('');
  readonly emptyText = input('Sin datos suficientes en este periodo');
  readonly changePct = input<number | null>(null);
  readonly changeHint = input('vs. periodo anterior');
  readonly tone = input<Tone>('neutral');
  readonly series = input<(number | null)[]>([]);
  /** Tamaño de muestra; `null` lo oculta (p. ej. el backlog no es una muestra). */
  readonly n = input<number | null>(null);
  readonly lowSample = input(false);

  readonly sparkW = SPARK_W;
  readonly sparkH = SPARK_H;
  readonly empty = computed(() => this.value() === null);
  readonly change = computed(() => formatChange(this.changePct()));
  readonly badgeClass = computed(() => TONE_BADGE[this.tone()]);
  readonly lineColor = computed(() => TONE_LINE[this.tone()]);
  readonly spark = computed(() => sparkline(this.series(), SPARK_W, SPARK_H));
  readonly spreadTitle = computed(() => `Dispersión del tiempo de resolución: ${this.spread()}`);
}
