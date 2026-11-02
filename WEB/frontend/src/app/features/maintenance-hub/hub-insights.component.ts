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
    <section class="glass rounded-2xl p-4" aria-label="Pulso del mantenimiento" [attr.aria-busy]="loading()">
      <header class="border-b border-brand-grey/60 pb-3 text-center">
        <h2 class="text-[19px] font-extrabold uppercase leading-tight tracking-tight text-brand-sidebar">Pulso del mantenimiento</h2>
        <p class="mt-0.5 text-[12px] text-on-surface-variant">Resumen de actividad y cumplimiento</p>
      </header>

      @if (overview(); as o) {
        <div class="divide-y divide-brand-grey/60 [&>*]:py-3 [&>*:last-child]:pb-0">
          <!-- Servicios por fecha -->
          <div>
            <h3 class="flex items-center gap-2 text-[13px] font-extrabold uppercase tracking-wide text-brand-sidebar"><span class="material-symbols-outlined text-[20px] text-brand-accentDeep" aria-hidden="true">event_note</span>Servicios por fecha</h3>
            <dl class="mt-2 grid grid-cols-3 gap-2">
              <div class="flex min-w-0 flex-col items-center justify-center gap-1 rounded-xl border px-1 py-2.5 text-center" [class]="o.upcoming.overdue ? 'border-brand-mustard/60 bg-secondary-fixed text-on-secondary-fixed' : 'border-brand-grey/60 bg-surface-container text-on-surface-variant'">
                <span class="material-symbols-outlined flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white/60 text-[20px]" aria-hidden="true">schedule</span>
                <dd class="m-0 text-[24px] font-extrabold leading-7">{{ o.upcoming.overdue }}</dd>
                <dt class="m-0 text-[10px] font-bold uppercase leading-3 tracking-wide">Vencidos</dt>
              </div>
              <div class="flex min-w-0 flex-col items-center justify-center gap-1 rounded-xl border px-1 py-2.5 text-center" [class]="'border-brand-accentLight bg-brand-accentLight/40 text-brand-accentDeep'">
                <span class="material-symbols-outlined flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white/60 text-[20px]" aria-hidden="true">event_available</span>
                <dd class="m-0 text-[24px] font-extrabold leading-7">{{ o.upcoming.next_7_days }}</dd>
                <dt class="m-0 text-[10px] font-bold uppercase leading-3 tracking-wide">Próx. 7 días</dt>
              </div>
              <div class="flex min-w-0 flex-col items-center justify-center gap-1 rounded-xl border px-1 py-2.5 text-center" [class]="'border-brand-accentLight bg-brand-accentLight/40 text-brand-accentDeep'">
                <span class="material-symbols-outlined flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white/60 text-[20px]" aria-hidden="true">calendar_month</span>
                <dd class="m-0 text-[24px] font-extrabold leading-7">{{ o.upcoming.next_30_days }}</dd>
                <dt class="m-0 text-[10px] font-bold uppercase leading-3 tracking-wide">Próx. 30 días</dt>
              </div>
            </dl>
          </div>

          <!-- Preventivo vs correctivo -->
          <div>
            <h3 class="flex items-center gap-2 text-[13px] font-extrabold uppercase tracking-wide text-brand-sidebar"><span class="material-symbols-outlined text-[20px] text-brand-accentDeep" aria-hidden="true">bar_chart</span>Preventivo vs correctivo</h3>
            @if (o.mix.preventive_pct !== null) {
              <p class="mt-2 flex flex-wrap items-baseline gap-x-2">
                <span class="text-[28px] font-extrabold leading-none text-brand-sidebar">{{ pct(o.mix.preventive_pct) }}</span>
                <span class="text-[12px] text-on-surface-variant">preventivo</span>
                @if (change(o.mix.change_pct)) {
                  <span class="rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="tone(o.mix.change_pct, 'higher')">{{ change(o.mix.change_pct) }}</span>
                }
              </p>
              <div class="mt-2 flex h-2.5 overflow-hidden rounded-full bg-surface-container" role="img"
                [attr.aria-label]="o.mix.preventive + ' preventivos, ' + o.mix.corrective + ' correctivos, ' + o.mix.other + ' otros'">
                <div class="h-full bg-brand-accentDeep" [style.width.%]="share(o.mix.preventive, o.mix.sample_size)"></div>
                <div class="h-full bg-brand-mustard" [style.width.%]="share(o.mix.corrective, o.mix.sample_size)"></div>
                <div class="h-full bg-brand-grey" [style.width.%]="share(o.mix.other, o.mix.sample_size)"></div>
              </div>
              <p class="mt-1.5 text-[11px] leading-4 text-on-surface-variant">
                {{ o.mix.preventive }} preventivos · {{ o.mix.corrective }} correctivos · {{ o.mix.other }} otros · n = {{ o.mix.sample_size }}
                @if (o.mix.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-2 py-0.5 text-[10px] font-bold text-on-secondary-fixed">Pocos datos</span> }
              </p>
            } @else {
              <div class="mt-1 flex flex-col items-center gap-1 text-center">
                <span class="material-symbols-outlined text-[30px] text-brand-slate" aria-hidden="true">monitoring</span>
                <p class="text-[12px] text-on-surface-variant">Sin trabajos registrados en el período.</p>
              </div>
            }
          </div>

          <!-- Cumplimiento del plan -->
          <div>
            <h3 class="flex items-center gap-2 text-[13px] font-extrabold uppercase tracking-wide text-brand-sidebar"><span class="material-symbols-outlined text-[20px] text-brand-accentDeep" style="font-variation-settings: 'FILL' 1" aria-hidden="true">check_circle</span>Cumplimiento del plan</h3>
            @if (o.compliance.compliance_pct !== null) {
              <p class="mt-2 flex flex-wrap items-baseline gap-x-2">
                <span class="text-[28px] font-extrabold leading-none text-brand-sidebar">{{ pct(o.compliance.compliance_pct) }}</span>
                <span class="text-[12px] text-on-surface-variant">a tiempo</span>
                @if (change(o.compliance.change_pct)) {
                  <span class="rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="tone(o.compliance.change_pct, 'higher')">{{ change(o.compliance.change_pct) }}</span>
                }
              </p>
              <div class="mt-2 h-2.5 overflow-hidden rounded-full bg-surface-container" role="img" [attr.aria-label]="o.compliance.on_time + ' de ' + o.compliance.planned + ' servicios a tiempo'">
                <div class="h-full rounded-full bg-brand-accentDeep" [style.width.%]="o.compliance.compliance_pct"></div>
              </div>
              <p class="mt-1.5 text-[11px] leading-4 text-on-surface-variant">
                {{ o.compliance.on_time }} de {{ o.compliance.planned }} servicios · n = {{ o.compliance.sample_size }}
                @if (o.compliance.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-2 py-0.5 text-[10px] font-bold text-on-secondary-fixed">Pocos datos</span> }
              </p>
            } @else {
              <p class="mt-2 text-center text-[12px] text-on-surface-variant">Aún no hay servicios con fecha en este período.</p>
            }
          </div>

          <!-- Duración real vs estimada -->
          <div>
            <h3 class="flex items-center gap-2 text-[13px] font-extrabold uppercase tracking-wide text-brand-sidebar">
              <span class="material-symbols-outlined text-[20px] text-brand-accentDeep" aria-hidden="true">timer</span>Duración real vs estimada
              <span class="material-symbols-outlined text-[16px] text-on-surface-variant" title="Promedio de horas reales frente a las estimadas de cada servicio" aria-label="Promedio de horas reales frente a las estimadas de cada servicio" role="img">info</span>
            </h3>
            @if (o.duration.variance_pct !== null) {
              <p class="mt-2 flex flex-wrap items-baseline gap-x-2">
                <span class="text-[28px] font-extrabold leading-none text-brand-sidebar">{{ hours(o.duration.average_actual_hours) }}</span>
                <span class="text-[12px] text-on-surface-variant">real · {{ hours(o.duration.average_estimated_hours) }} estimado</span>
                <span class="rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="tone(o.duration.variance_pct, 'lower')">{{ change(o.duration.variance_pct) || '= 0%' }}</span>
              </p>
              <p class="mt-1.5 text-[11px] leading-4 text-on-surface-variant">
                {{ o.duration.variance_pct > 0 ? 'Tardaron más de lo estimado' : o.duration.variance_pct < 0 ? 'Tardaron menos de lo estimado' : 'Justo lo estimado' }} · n = {{ o.duration.sample_size }}
                @if (o.duration.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-2 py-0.5 text-[10px] font-bold text-on-secondary-fixed">Pocos datos</span> }
              </p>
            } @else {
              <div class="mt-1 flex flex-col items-center gap-1 text-center">
                <span class="material-symbols-outlined text-[30px] text-brand-slate" aria-hidden="true">schedule</span>
                <p class="text-[12px] text-on-surface-variant">Se necesitan horas reales y estimadas para comparar.</p>
              </div>
            }
          </div>

          <!-- Costo y reprogramaciones -->
          <dl class="grid grid-cols-2 divide-x divide-brand-grey/60">
            <div class="pr-3 text-center">
              <dt class="flex items-center justify-center gap-1.5 text-[12px] font-extrabold uppercase tracking-wide text-brand-sidebar"><span class="material-symbols-outlined text-[20px] text-brand-accentDeep" aria-hidden="true">payments</span>Costo acumulado</dt>
              <dd class="ml-0 mt-1.5">
                @if (o.cost.records_with_cost > 0) {
                  <span class="block text-[20px] font-extrabold leading-6 text-brand-sidebar">{{ money(o.cost.total) }}</span>
                  @if (change(o.cost.change_pct)) {
                    <span class="mt-0.5 inline-block rounded-full px-1.5 py-0.5 text-[10px] font-bold" [class]="tone(o.cost.change_pct, 'lower')">{{ change(o.cost.change_pct) }}</span>
                  }
                  <span class="mt-0.5 block text-[11px] leading-4 text-on-surface-variant">n = {{ o.cost.records_with_cost }}@if (o.cost.average_per_record) { · prom. {{ money(o.cost.average_per_record) }} }
                    @if (o.cost.low_sample) { <span class="ml-1 rounded-full bg-secondary-fixed px-2 py-0.5 text-[10px] font-bold text-on-secondary-fixed">Pocos datos</span> }</span>
                } @else {
                  <span class="block text-[20px] font-extrabold leading-6 text-on-surface-variant">—</span>
                  <span class="block text-[11px] text-on-surface-variant">Sin datos de costos</span>
                }
              </dd>
            </div>
            <div class="pl-3 text-center">
              <dt class="flex items-center justify-center gap-1.5 text-[12px] font-extrabold uppercase tracking-wide text-brand-sidebar"><span class="material-symbols-outlined text-[20px] text-brand-accentDeep" aria-hidden="true">event_repeat</span>Reprogramados</dt>
              <dd class="ml-0 mt-1.5">
                <span class="block text-[20px] font-extrabold leading-6 text-brand-sidebar">{{ o.reschedules.count }}</span>
                @if (change(o.reschedules.change_pct)) {
                  <span class="mt-0.5 inline-block rounded-full px-1.5 py-0.5 text-[10px] font-bold" [class]="tone(o.reschedules.change_pct, 'lower')">{{ change(o.reschedules.change_pct) }}</span>
                }
                <span class="mt-0.5 block text-[11px] leading-4 text-on-surface-variant">Antes: {{ o.reschedules.previous }}</span>
              </dd>
            </div>
          </dl>
        </div>
      } @else if (loading()) {
        <div class="mt-3 space-y-2" role="status" aria-label="Cargando métricas">
          <div class="h-12 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
          <div class="h-16 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
          <div class="h-16 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
        </div>
      } @else {
        <p class="mt-3 text-center text-[12px] text-on-surface-variant">Las métricas no están disponibles en este momento.</p>
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

}
