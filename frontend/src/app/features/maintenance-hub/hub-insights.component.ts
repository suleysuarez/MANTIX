import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import { MaintenanceOverview } from '../../core/maintenance-overview.service';
import { Tone, changeTone, formatChange, formatHours, formatPct } from '../dashboard/dashboard-format';

const TONE_CLASS: Record<Tone, string> = {
  good: 'bg-primary-fixed text-on-primary-fixed-variant',
  bad: 'bg-secondary-fixed text-on-secondary-fixed',
  neutral: 'bg-surface-container text-on-surface-variant',
};

/** Pulso del mantenimiento: métricas propias del módulo (no repiten las del Dashboard). */
@Component({
  selector: 'app-hub-insights',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="glass space-y-4 rounded-2xl p-4" aria-label="Pulso del mantenimiento" [attr.aria-busy]="loading()">
      <h2 class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Pulso del mantenimiento</h2>

      @if (overview(); as o) {
        <!-- Próximos servicios -->
        <div>
          <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Servicios por fecha</h3>
          <dl class="mt-1.5 grid grid-cols-3 gap-2 text-center">
            <div class="rounded-xl px-1 py-2" [class]="o.upcoming.overdue ? 'bg-error-container text-on-error-container' : 'bg-surface-container text-on-surface-variant'">
              <dd class="text-[20px] font-bold leading-6">{{ o.upcoming.overdue }}</dd><dt class="text-[11px] font-semibold">Vencidos</dt>
            </div>
            <div class="rounded-xl bg-brand-accentLight/60 px-1 py-2 text-brand-accentDeep">
              <dd class="text-[20px] font-bold leading-6">{{ o.upcoming.next_7_days }}</dd><dt class="text-[11px] font-semibold">Próx. 7 días</dt>
            </div>
            <div class="rounded-xl bg-brand-accentLight/60 px-1 py-2 text-brand-accentDeep">
              <dd class="text-[20px] font-bold leading-6">{{ o.upcoming.next_30_days }}</dd><dt class="text-[11px] font-semibold">Próx. 30 días</dt>
            </div>
          </dl>
        </div>

        <!-- Preventivo vs correctivo -->
        <div>
          <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Preventivo vs correctivo</h3>
          @if (o.mix.preventive_pct !== null) {
            <p class="mt-1 flex flex-wrap items-baseline gap-x-2">
              <span class="text-[22px] font-bold text-on-surface">{{ pct(o.mix.preventive_pct) }}</span>
              <span class="text-[12px] text-on-surface-variant">preventivo</span>
              @if (change(o.mix.change_pct)) {
                <span class="rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="tone(o.mix.change_pct, 'higher')">{{ change(o.mix.change_pct) }}</span>
              }
            </p>
            <div class="mt-1.5 flex h-2.5 overflow-hidden rounded-full bg-surface-container" role="img"
              [attr.aria-label]="o.mix.preventive + ' preventivos, ' + o.mix.corrective + ' correctivos, ' + o.mix.other + ' otros'">
              <div class="h-full bg-brand-accentDeep" [style.width.%]="share(o.mix.preventive, o.mix.sample_size)"></div>
              <div class="h-full bg-brand-mustard" [style.width.%]="share(o.mix.corrective, o.mix.sample_size)"></div>
              <div class="h-full bg-brand-grey" [style.width.%]="share(o.mix.other, o.mix.sample_size)"></div>
            </div>
            <p class="mt-1 text-[11px] text-on-surface-variant">
              {{ o.mix.preventive }} preventivos · {{ o.mix.corrective }} correctivos · {{ o.mix.other }} otros · n = {{ o.mix.sample_size }}
              @if (o.mix.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-1.5 py-0.5 text-[10px] font-bold text-on-secondary-fixed">pocos datos</span> }
            </p>
          } @else {
            <p class="mt-1 text-[12px] text-on-surface-variant">Sin trabajos registrados en el periodo.</p>
          }
        </div>

        <!-- Cumplimiento del plan por semana -->
        <div>
          <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Cumplimiento del plan</h3>
          @if (o.compliance.compliance_pct !== null) {
            <p class="mt-1 flex flex-wrap items-baseline gap-x-2">
              <span class="text-[22px] font-bold text-on-surface">{{ pct(o.compliance.compliance_pct) }}</span>
              <span class="text-[12px] text-on-surface-variant">a tiempo</span>
              @if (change(o.compliance.change_pct)) {
                <span class="rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="tone(o.compliance.change_pct, 'higher')">{{ change(o.compliance.change_pct) }}</span>
              }
            </p>
            <ul class="mt-2 flex h-14 items-end gap-1" aria-label="Cumplimiento por semana">
              @for (week of o.compliance.weeks; track week.week_start) {
                <li class="flex h-full min-w-0 flex-1 flex-col justify-end" [attr.title]="weekLabel(week.week_start) + ': ' + week.on_time + ' de ' + week.planned + ' a tiempo'">
                  <div class="rounded-t bg-brand-accentDeep" [style.height.%]="week.compliance_pct ?? 0" [class.opacity-60]="(week.compliance_pct ?? 0) < 60"></div>
                </li>
              }
            </ul>
            <p class="mt-1 text-[11px] text-on-surface-variant">
              {{ o.compliance.on_time }} de {{ o.compliance.planned }} servicios · n = {{ o.compliance.sample_size }}
              @if (o.compliance.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-1.5 py-0.5 text-[10px] font-bold text-on-secondary-fixed">pocos datos</span> }
            </p>
          } @else {
            <p class="mt-1 text-[12px] text-on-surface-variant">Aún no hay servicios con fecha en este periodo.</p>
          }
        </div>

        <!-- Real vs estimado -->
        <div>
          <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Duración real vs estimada</h3>
          @if (o.duration.variance_pct !== null) {
            <p class="mt-1 flex flex-wrap items-baseline gap-x-2">
              <span class="text-[22px] font-bold text-on-surface">{{ hours(o.duration.average_actual_hours) }}</span>
              <span class="text-[12px] text-on-surface-variant">real · {{ hours(o.duration.average_estimated_hours) }} estimado</span>
              <span class="rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="tone(o.duration.variance_pct, 'lower')">{{ change(o.duration.variance_pct) || '= 0%' }}</span>
            </p>
            <p class="mt-1 text-[11px] text-on-surface-variant">
              {{ o.duration.variance_pct > 0 ? 'Tardaron más de lo estimado' : o.duration.variance_pct < 0 ? 'Tardaron menos de lo estimado' : 'Justo lo estimado' }} · n = {{ o.duration.sample_size }}
              @if (o.duration.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-1.5 py-0.5 text-[10px] font-bold text-on-secondary-fixed">pocos datos</span> }
            </p>
          } @else {
            <p class="mt-1 text-[12px] text-on-surface-variant">Faltan servicios con horas reales y estimadas.</p>
          }
        </div>

        <!-- Costo y reprogramaciones -->
        <dl class="grid grid-cols-2 gap-3 border-t border-brand-grey/70 pt-3 text-[12px]">
          <div>
            <dt class="text-on-surface-variant">Costo acumulado</dt>
            <dd class="mt-0.5">
              @if (o.cost.records_with_cost > 0) {
                <span class="text-[17px] font-bold text-on-surface">{{ money(o.cost.total) }}</span>
                @if (change(o.cost.change_pct)) {
                  <span class="ml-1 rounded-full px-1.5 py-0.5 text-[10px] font-bold" [class]="tone(o.cost.change_pct, 'lower')">{{ change(o.cost.change_pct) }}</span>
                }
                <span class="block text-[11px] text-on-surface-variant">n = {{ o.cost.records_with_cost }}@if (o.cost.average_per_record) { · prom. {{ money(o.cost.average_per_record) }} }
                  @if (o.cost.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-1.5 py-0.5 text-[10px] font-bold text-on-secondary-fixed">pocos datos</span> }</span>
              } @else {
                <span class="text-on-surface-variant" title="Ningún registro del periodo reporta costo">—</span>
              }
            </dd>
          </div>
          <div>
            <dt class="text-on-surface-variant">Reprogramados</dt>
            <dd class="mt-0.5">
              <span class="text-[17px] font-bold text-on-surface">{{ o.reschedules.count }}</span>
              @if (change(o.reschedules.change_pct)) {
                <span class="ml-1 rounded-full px-1.5 py-0.5 text-[10px] font-bold" [class]="tone(o.reschedules.change_pct, 'lower')">{{ change(o.reschedules.change_pct) }}</span>
              }
              <span class="block text-[11px] text-on-surface-variant">antes: {{ o.reschedules.previous }}</span>
            </dd>
          </div>
        </dl>
      } @else if (loading()) {
        <div class="space-y-2" role="status" aria-label="Cargando métricas">
          <div class="h-12 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
          <div class="h-16 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
          <div class="h-16 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
        </div>
      } @else {
        <p class="text-[12px] text-on-surface-variant">Las métricas no están disponibles en este momento.</p>
      }
    </section>
  `,
})
export class HubInsightsComponent {
  readonly overview = input<MaintenanceOverview | null>(null);
  readonly loading = input(false);

  readonly pct = formatPct;
  readonly hours = formatHours;
  readonly change = formatChange;

  tone(changePct: number | null, betterWhen: 'higher' | 'lower'): string {
    return TONE_CLASS[changeTone(changePct, betterWhen)];
  }

  share(part: number, whole: number): number {
    return whole > 0 ? (part / whole) * 100 : 0;
  }

  money(value: string): string {
    return Number(value).toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  weekLabel(iso: string): string {
    const date = new Date(iso);
    return `semana del ${date.getUTCDate()}/${date.getUTCMonth() + 1}`;
  }
}
