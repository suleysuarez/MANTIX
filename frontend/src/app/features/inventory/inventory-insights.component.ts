import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import { InventoryOverview } from '../../core/inventory.service';
import { Tone, changeTone, formatChange } from '../dashboard/dashboard-format';
import { money } from './inventory-ui';

const TONE_CLASS: Record<Tone, string> = {
  good: 'bg-primary-fixed text-on-primary-fixed-variant',
  bad: 'bg-secondary-fixed text-on-secondary-fixed',
  neutral: 'bg-surface-container text-on-surface-variant',
};
const MONTHS = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
const CHART_W = 240;
const CHART_H = 70;

interface Bar {
  x: number;
  width: number;
  height: number;
  units: number;
  label: string;
}

/** Métricas propias del inventario: valor, consumo, rotación y lo que pide atención. */
@Component({
  selector: 'app-inventory-insights',
  standalone: true,
  imports: [DatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="glass space-y-4 rounded-2xl p-4" aria-label="Pulso del inventario" [attr.aria-busy]="loading()">
      <h2 class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Pulso del inventario</h2>

      @if (overview(); as o) {
        <div>
          <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Valor del stock</h3>
          <p class="mt-1 flex flex-wrap items-baseline gap-x-2">
            <span class="text-[22px] font-bold text-on-surface">{{ fmt(o.stock_value.total) }}</span>
            @if (change(o.stock_value.change_pct)) {
              <span class="rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="tone(o.stock_value.change_pct, 'higher')">{{ change(o.stock_value.change_pct) }}</span>
            }
          </p>
          <p class="text-[11px] text-on-surface-variant">{{ o.stock_value.items }} ítems activos · al costo actual@if (o.stock_value.previous) { · inicio del periodo {{ fmt(o.stock_value.previous) }} }</p>
        </div>

        <dl class="grid grid-cols-2 gap-2 text-center">
          <div class="rounded-xl px-1 py-2" [class]="o.low_stock ? 'bg-secondary-fixed text-on-secondary-fixed' : 'bg-surface-container text-on-surface-variant'">
            <dd class="text-[20px] font-bold leading-6">{{ o.low_stock }}</dd><dt class="text-[11px] font-semibold">Bajo mínimo</dt>
          </div>
          <div class="rounded-xl px-1 py-2" [class]="o.out_of_stock ? 'bg-error-container text-on-error-container' : 'bg-surface-container text-on-surface-variant'">
            <dd class="text-[20px] font-bold leading-6">{{ o.out_of_stock }}</dd><dt class="text-[11px] font-semibold">Agotados</dt>
          </div>
        </dl>

        <div>
          <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Consumo y rotación</h3>
          @if (o.consumption.movements > 0) {
            <p class="mt-1 flex flex-wrap items-baseline gap-x-2">
              <span class="text-[22px] font-bold text-on-surface">{{ o.consumption.units }}</span>
              <span class="text-[12px] text-on-surface-variant">unidades · {{ fmt(o.consumption.value) }}</span>
              @if (change(o.consumption.change_pct)) {
                <span class="rounded-full bg-surface-container px-2 py-0.5 text-[11px] font-bold text-on-surface-variant">{{ change(o.consumption.change_pct) }}</span>
              }
            </p>
            <p class="mt-0.5 text-[11px] text-on-surface-variant">
              n = {{ o.consumption.movements }} movimientos
              @if (o.consumption.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-1.5 py-0.5 text-[10px] font-bold text-on-secondary-fixed">pocos datos</span> }
              @if (o.rotation.value !== null) { · rotación {{ o.rotation.value }}× }
              @if (change(o.rotation.change_pct)) { <span class="ml-1 rounded-full px-1.5 py-0.5 text-[10px] font-bold" [class]="tone(o.rotation.change_pct, 'higher')">{{ change(o.rotation.change_pct) }}</span> }
            </p>
          } @else {
            <p class="mt-1 text-[12px] text-on-surface-variant">Sin consumo registrado en el periodo.</p>
          }
        </div>

        <div>
          <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Consumo por mes (12 meses)</h3>
          @if (hasConsumption(o)) {
            <svg [attr.viewBox]="'0 0 ' + chartW + ' ' + (chartH + 14)" class="mt-1 h-24 w-full" role="img" aria-label="Unidades consumidas por mes">
              <line x1="0" [attr.x2]="chartW" [attr.y1]="chartH" [attr.y2]="chartH" stroke="currentColor" class="text-brand-grey" />
              @for (bar of bars(o); track $index) {
                <g>
                  <title>{{ bar.label }}: {{ bar.units }} unidades</title>
                  <rect [attr.x]="bar.x" [attr.y]="chartH - bar.height" [attr.width]="bar.width" [attr.height]="bar.height" rx="2" class="fill-brand-accentDeep" />
                  @if (bar.units > 0) { <text [attr.x]="bar.x + bar.width / 2" [attr.y]="chartH - bar.height - 2" text-anchor="middle" font-size="7" class="fill-on-surface-variant">{{ bar.units }}</text> }
                  <text [attr.x]="bar.x + bar.width / 2" [attr.y]="chartH + 10" text-anchor="middle" font-size="7" class="fill-on-surface-variant">{{ bar.label }}</text>
                </g>
              }
            </svg>
          } @else {
            <p class="mt-1 text-[12px] text-on-surface-variant">Sin consumo en los últimos 12 meses.</p>
          }
        </div>

        <div>
          <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Más usados en mantenimiento</h3>
          <ul class="mt-1.5 space-y-1">
            @for (u of o.most_used; track u.item_id) {
              <li class="flex justify-between gap-2 text-[12px]"><span class="min-w-0 truncate text-on-surface">{{ u.name }}</span><strong class="shrink-0">{{ u.units }}</strong></li>
            } @empty {
              <li class="text-[12px] text-on-surface-variant">Ningún consumo vinculado a trabajos en el periodo.</li>
            }
          </ul>
        </div>

        <div>
          <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Sin movimiento en 90 días ({{ o.stale_count }})</h3>
          <ul class="mt-1.5 space-y-1">
            @for (s of o.stale_items; track s.item_id) {
              <li class="flex justify-between gap-2 text-[12px]">
                <span class="min-w-0 truncate text-on-surface">{{ s.name }}</span>
                <span class="shrink-0 text-on-surface-variant">{{ s.stock }} u. · {{ s.last_movement_at ? (s.last_movement_at | date: 'dd/MM/yy') : 'nunca' }}</span>
              </li>
            } @empty {
              <li class="text-[12px] text-on-surface-variant">Todo el stock se ha movido recientemente.</li>
            }
          </ul>
        </div>
      } @else if (loading()) {
        <div class="space-y-2" role="status" aria-label="Cargando métricas">
          <div class="h-12 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
          <div class="h-16 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
          <div class="h-20 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
        </div>
      } @else {
        <p class="text-[12px] text-on-surface-variant">Las métricas no están disponibles en este momento.</p>
      }
    </section>
  `,
})
export class InventoryInsightsComponent {
  readonly overview = input<InventoryOverview | null>(null);
  readonly loading = input(false);

  readonly chartW = CHART_W;
  readonly chartH = CHART_H;
  readonly fmt = money;
  readonly change = formatChange;

  tone(changePct: number | null, betterWhen: 'higher' | 'lower'): string {
    return TONE_CLASS[changeTone(changePct, betterWhen)];
  }

  hasConsumption(overview: InventoryOverview): boolean {
    return overview.monthly_consumption.some((m) => m.units > 0);
  }

  bars(overview: InventoryOverview): Bar[] {
    const months = overview.monthly_consumption;
    const max = Math.max(...months.map((m) => m.units), 1);
    const slot = CHART_W / Math.max(months.length, 1);
    const width = slot * 0.62;
    return months.map((m, index) => ({
      x: index * slot + (slot - width) / 2,
      width,
      height: m.units ? Math.max((m.units / max) * (CHART_H - 14), 2) : 0,
      units: m.units,
      label: MONTHS[new Date(m.month).getUTCMonth()],
    }));
  }
}
