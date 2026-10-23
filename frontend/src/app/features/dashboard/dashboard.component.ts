import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { Period, TrendsResponse } from '../../core/dashboard-kpis.service';
import { DashboardMode, DashboardState, DashboardStore } from '../../core/dashboard.store';
import { formatDate } from '../../core/equipment-status';
import { LocalProfileService } from '../../core/local-profile.service';
import { PermissionsService } from '../../core/permissions.service';
import { priorityMeta, statusMeta } from '../tickets/ticket-ui';
import {
  bucketLabel,
  changeTone,
  formatCentral,
  formatDowntime,
  formatHours,
  formatPct,
  formatSpread,
  reasonLabel,
} from './dashboard-format';
import { KpiCardComponent } from './kpi-card.component';

const CARD = 'rounded-[18px] bg-white p-4 shadow-[0_8px_25px_rgba(15,23,42,0.05)]';
const LINK_FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#2563EB]';
const PERIODS: { id: Period; label: string; caption: string }[] = [
  { id: '7d', label: '7 días', caption: 'últimos 7 días' },
  { id: '30d', label: '30 días', caption: 'últimos 30 días' },
  { id: '12m', label: '12 meses', caption: 'últimos 12 meses' },
];
const CHART_W = 600;
const CHART_H = 150;

export interface ChartBar {
  x: number;
  width: number;
  createdH: number;
  resolvedH: number;
  label: string;
  created: number;
  resolved: number;
  showLabel: boolean;
}

/** Smart component: pide los KPI del periodo global al store y los presenta. */
@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [AsyncPipe, RouterLink, KpiCardComponent],
  template: `
    @if (state$ | async; as state) {
      <div class="tw-reset flex w-full flex-col gap-3 font-sans text-[#1E293B]" [attr.aria-busy]="state.loading">
        <!-- Hero: saludo + visual sobre un único fondo -->
        <section class="hero group relative overflow-hidden rounded-[18px] bg-[linear-gradient(135deg,#eef6ff_0%,#f8fbff_100%)] p-4 shadow-[0_8px_25px_rgba(15,23,42,0.05)] lg:min-h-[250px] lg:p-5">
          <div class="pointer-events-none absolute -right-20 -top-24 h-80 w-80 rounded-full bg-[#2563EB]/[0.07]"></div>
          <div class="pointer-events-none absolute bottom-[-6rem] left-[38%] h-64 w-64 rotate-45 rounded-[40px] bg-[#3B82F6]/[0.06]"></div>

          <div class="hero-visual absolute inset-y-0 right-0 hidden w-[60%] lg:block">
            <video class="hero-gif pointer-events-none h-full w-full object-contain object-right mix-blend-multiply"
              src="assets/videos/dashboard1.mp4" autoplay muted loop playsinline preload="auto" aria-hidden="true"></video>
            <div class="holo pointer-events-none absolute inset-x-8 bottom-5 flex translate-y-2 items-center justify-around gap-4 rounded-[18px] px-5 py-3 text-[#3E5C76] opacity-0 transition-[opacity,transform] duration-300 ease-out group-hover:translate-y-0 group-hover:opacity-100 group-focus-within:translate-y-0 group-focus-within:opacity-100 motion-reduce:transition-none [@media(hover:none)]:translate-y-0 [@media(hover:none)]:opacity-100">
              <div class="flex items-center gap-3">
                <span class="material-symbols-outlined text-[26px]">desktop_windows</span>
                <div>
                  <span class="block text-[22px] font-bold leading-6">{{ pct(state.kpis?.availability?.value ?? null) }}</span>
                  <span class="block text-[10px] font-bold uppercase tracking-wider text-[#3E5C76]">Disponibilidad</span>
                </div>
              </div>
              <span class="h-8 w-[2px] rounded-full bg-[#D4A017]"></span>
              <div class="flex items-center gap-3">
                <span class="material-symbols-outlined text-[26px]">verified</span>
                <div>
                  <span class="block text-[22px] font-bold leading-6">{{ pct(state.kpis?.sla_compliance_pct?.value ?? null) }}</span>
                  <span class="block text-[10px] font-bold uppercase tracking-wider text-[#3E5C76]">Cumplimiento SLA</span>
                </div>
              </div>
            </div>
          </div>

          <div class="relative z-10 flex flex-col gap-2 lg:max-w-[40%]">
            <span class="inline-flex w-fit items-center gap-2 rounded-full bg-white/80 px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-[#1E293B]">
              <span class="h-2 w-2 rounded-full bg-[#D4A017]"></span>
              {{ userName() ? 'Hola, ' + userName() : 'Plataforma central' }}
            </span>
            <h1 class="text-[22px] font-extrabold uppercase leading-[1.1] tracking-tight text-[#0b1f3a] md:text-[28px]">
              Sistema inteligente <br />de mantenimiento
            </h1>
            <p class="max-w-md text-[12px] leading-4 text-[#64748B]">
              Gestión de incidentes y control en tiempo real del parque tecnológico empresarial.
            </p>
          </div>
        </section>

        <!-- Selector de periodo global -->
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h2 class="text-[15px] font-bold text-[#0b1f3a]">
            Indicadores · {{ periodCaption(state.period) }}
            @if (state.loading) {
              <span class="ml-2 inline-block h-2 w-2 animate-pulse rounded-full bg-[#2563EB] motion-reduce:animate-none" role="status" aria-label="Actualizando"></span>
            }
          </h2>
          <div class="flex rounded-full bg-white p-0.5 shadow-[0_4px_12px_rgba(15,23,42,0.06)]" role="group" aria-label="Periodo de los indicadores">
            @for (p of periods; track p.id) {
              <button type="button" (click)="setPeriod(p.id)" [attr.aria-pressed]="state.period === p.id"
                class="rounded-full px-3 py-1 text-[12px] font-semibold transition-colors active:scale-95"
                [class]="focus + (state.period === p.id ? ' bg-[#0b1f3a] !text-white' : ' bg-transparent !text-[#64748B] hover:bg-[#F1F5F9] hover:!text-[#1E293B]')">
                {{ p.label }}
              </button>
            }
          </div>
        </div>

        @if (!state.loading && !state.kpis && mode() !== 'requester') {
          <p role="alert" class="rounded-xl bg-[#FEF3C7] px-4 py-3 text-[13px] font-medium text-[#92400E]">
            No se pudieron cargar los indicadores. Revisa tu conexión o tus permisos e inténtalo de nuevo.
            <button type="button" (click)="reload()" class="ml-2 bg-transparent p-0 font-bold underline">Reintentar</button>
          </p>
        }

        <!-- Quien solo ve lo que pidió: el estado de sus solicitudes -->
        @if (mode() === 'requester') {
          <section class="grid grid-cols-1 gap-3 lg:grid-cols-3" aria-label="Mis solicitudes">
            @let mine = state.mine;
            @if (mine) {
              <div [class]="card + ' flex flex-col gap-3 lg:col-span-2'">
                <div>
                  <h2 class="text-[15px] font-bold">Mis solicitudes por estado</h2>
                  <p class="text-[11px] text-[#64748B]">{{ mine.tickets.total }} en total · {{ mine.tickets.open }} abiertas@if (mine.tickets.overdue > 0) { · {{ mine.tickets.overdue }} fuera de plazo }</p>
                </div>
                @if (mine.tickets.by_status.length) {
                  <ul class="grid grid-cols-2 gap-2 sm:grid-cols-3">
                    @for (item of mine.tickets.by_status; track item.key) {
                      <li class="flex items-center justify-between gap-2 rounded-xl bg-[#F8FAFC] px-3 py-2.5">
                        <span class="flex min-w-0 items-center gap-2 text-[12px] font-semibold"><span [class]="'h-2 w-2 shrink-0 rounded-full ' + statusDot(item.key)" aria-hidden="true"></span><span class="truncate">{{ statusLabel(item.key) }}</span></span>
                        <span class="text-[18px] font-extrabold text-[#0b1f3a]">{{ item.count }}</span>
                      </li>
                    }
                  </ul>
                } @else {
                  <p class="rounded-[14px] bg-[#F8FAFC] px-3 py-8 text-center text-[13px] text-[#64748B]">Aún no has creado solicitudes. Cuando reportes un problema, aquí verás cómo avanza.</p>
                }
              </div>
              <div [class]="card + ' flex flex-col gap-3'">
                <div>
                  <h2 class="text-[15px] font-bold">Abiertas por prioridad</h2>
                  <p class="text-[11px] text-[#64748B]">Lo que aún está en curso</p>
                </div>
                @if (mine.tickets.open_by_priority.length) {
                  <ul class="flex flex-col gap-2">
                    @for (item of mine.tickets.open_by_priority; track item.key) {
                      <li class="flex items-center justify-between rounded-xl bg-[#F8FAFC] px-3 py-2.5 text-[13px]"><span class="font-semibold">{{ priorityLabel(item.key) }}</span><span class="font-extrabold text-[#0b1f3a]">{{ item.count }}</span></li>
                    }
                  </ul>
                } @else {
                  <p class="rounded-[14px] bg-[#F0FDF4] px-3 py-6 text-center text-[12px] text-[#047857]">No tienes solicitudes abiertas.</p>
                }
                <a routerLink="/tickets" [class]="'mt-auto text-center text-[12px] font-medium !text-[#2563EB] hover:underline ' + focus">Ver mis tickets</a>
              </div>
            } @else if (state.loading) {
              <div class="h-40 animate-pulse rounded-[18px] bg-white motion-reduce:animate-none lg:col-span-3" role="status" aria-label="Cargando tus solicitudes"></div>
            } @else {
              <p role="alert" class="rounded-xl bg-[#FEF3C7] px-4 py-3 text-[13px] font-medium text-[#92400E] lg:col-span-3">
                No se pudo cargar el estado de tus solicitudes.
                <button type="button" (click)="reload()" class="ml-2 bg-transparent p-0 font-bold underline">Reintentar</button>
              </p>
            }
          </section>
        }

        @if (mode() !== 'requester') {
        <!-- 4 KPI -->
        <section class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4" aria-label="Indicadores clave">
          @let k = state.kpis;
          <app-kpi-card label="MTTR · mediana" icon="timer" link="/tickets" [queryParams]="{ status: 'resolved' }"
            [value]="k && k.mttr_hours.value !== null ? hours(k.mttr_hours.value) : null"
            [caption]="k ? mttrCaption(k.first_assignment_hours.value) : ''"
            [detail]="k && k.mttr_hours.value !== null ? central(k.mttr_hours) : ''"
            [spread]="k && k.mttr_hours.value !== null ? spread(k.mttr_hours) : ''"
            emptyText="Aún no hay tickets resueltos en este periodo"
            [changePct]="k?.mttr_hours?.change_pct ?? null" [tone]="tone(k?.mttr_hours?.change_pct ?? null, 'lower')"
            changeHint="mediana vs. periodo anterior"
            [n]="k ? k.mttr_hours.sample_size : null" [lowSample]="k?.mttr_hours?.low_sample ?? false"
            [series]="series(state.trends, 'mttr_hours')" />

          <app-kpi-card label="Cumplimiento SLA" icon="verified" link="/tickets" [queryParams]="{ status: 'resolved' }"
            [value]="k && k.sla_compliance_pct.value !== null ? pct(k.sla_compliance_pct.value) : null"
            [caption]="k ? slaCaption(k) : ''"
            [emptyText]="k && k.sla_compliance_pct.excluded_no_sla ? k.sla_compliance_pct.excluded_no_sla + ' resueltos sin SLA definido: no se miden' : 'Aún no hay tickets resueltos con SLA'"
            [changePct]="k?.sla_compliance_pct?.change_pct ?? null" [tone]="tone(k?.sla_compliance_pct?.change_pct ?? null, 'higher')"
            [n]="k ? k.sla_compliance_pct.sample_size : null" [lowSample]="k?.sla_compliance_pct?.low_sample ?? false"
            [series]="series(state.trends, 'sla_compliance_pct')" />

          <app-kpi-card label="Disponibilidad" icon="monitor_heart" link="/equipos"
            [value]="k && k.availability.value !== null ? pct(k.availability.value) : null"
            [caption]="k ? k.availability.operational + ' de ' + k.availability.total + ' equipos operativos' : ''"
            emptyText="Sin equipos registrados"
            [changePct]="k?.availability?.change_pct ?? null" [tone]="tone(k?.availability?.change_pct ?? null, 'higher')"
            changeHint="vs. inicio del periodo" />

          <app-kpi-card label="Backlog" icon="inbox" link="/tickets"
            [value]="k ? '' + k.backlog.open : null" [caption]="k && k.backlog.open ? 'tickets abiertos' : 'Sin tickets abiertos'"
            [changePct]="k?.backlog?.change_pct ?? null" [tone]="tone(k?.backlog?.change_pct ?? null, 'lower')"
            changeHint="vs. inicio del periodo">
            @if (k && k.backlog.open > 0) {
              <div class="mt-1">
                <div class="flex h-2 w-full overflow-hidden rounded-full bg-[#E2E8F0]" role="img"
                  [attr.aria-label]="k.backlog.age_0_2_days + ' de 0 a 2 días, ' + k.backlog.age_3_7_days + ' de 3 a 7 días, ' + k.backlog.age_over_7_days + ' de más de 7 días'">
                  <div class="h-full bg-[#93C5FD]" [style.width.%]="share(k.backlog.age_0_2_days, k.backlog.open)"></div>
                  <div class="h-full bg-[#2563EB]" [style.width.%]="share(k.backlog.age_3_7_days, k.backlog.open)"></div>
                  <div class="h-full bg-[#A16207]" [style.width.%]="share(k.backlog.age_over_7_days, k.backlog.open)"></div>
                </div>
                <p class="mt-1 text-[11px] text-[#64748B]">0-2 d: {{ k.backlog.age_0_2_days }} · 3-7 d: {{ k.backlog.age_3_7_days }} · +7 d: <strong class="text-[#92400E]">{{ k.backlog.age_over_7_days }}</strong></p>
              </div>
            }
          </app-kpi-card>
        </section>

        <!-- Gráficos -->
        <section class="grid grid-cols-1 gap-3 lg:grid-cols-3">
          <div [class]="card + ' flex flex-col gap-3 ' + (mode() === 'global' ? 'lg:col-span-2' : 'lg:col-span-3')">
            <div class="flex flex-wrap items-start justify-between gap-2">
              <div>
                <h2 class="text-[15px] font-bold">Tickets creados y resueltos</h2>
                <p class="text-[11px] text-[#64748B]">{{ periodCaption(state.period) }}</p>
              </div>
              <div class="flex items-center gap-3 text-[11px] text-[#64748B]">
                <span class="flex items-center gap-1"><span class="h-2.5 w-2.5 rounded-sm bg-[#93C5FD]"></span>Creados</span>
                <span class="flex items-center gap-1"><span class="h-2.5 w-2.5 rounded-sm bg-[#2563EB]"></span>Resueltos</span>
                @if (state.kpis?.resolution_rate_pct?.value !== null && state.kpis) {
                  <span class="rounded-full bg-[#FEF3C7] px-2 py-0.5 font-bold text-[#92400E]">Resolución {{ pct(state.kpis.resolution_rate_pct.value) }}</span>
                }
              </div>
            </div>
            @let bars = chart(state.trends);
            @if (bars.length) {
              <svg [attr.viewBox]="'0 0 ' + chartW + ' ' + (chartH + 20)" class="h-48 w-full" role="img"
                [attr.aria-label]="'Tickets creados y resueltos, ' + periodCaption(state.period)">
                <line x1="0" [attr.x2]="chartW" [attr.y1]="chartH" [attr.y2]="chartH" stroke="#E2E8F0" />
                @for (bar of bars; track $index) {
                  <g>
                    <title>{{ bar.label }}: {{ bar.created }} creados, {{ bar.resolved }} resueltos</title>
                    <rect [attr.x]="bar.x" [attr.y]="chartH - bar.createdH" [attr.width]="bar.width" [attr.height]="bar.createdH" rx="2" fill="#93C5FD" />
                    <rect [attr.x]="bar.x + bar.width + 1" [attr.y]="chartH - bar.resolvedH" [attr.width]="bar.width" [attr.height]="bar.resolvedH" rx="2" fill="#2563EB" />
                    @if (bar.created) {
                      <text [attr.x]="bar.x + bar.width / 2" [attr.y]="chartH - bar.createdH - 3" text-anchor="middle" [attr.font-size]="bars.length > 12 ? 8 : 10" font-weight="600" fill="#475569">{{ bar.created }}</text>
                    }
                    @if (bar.resolved) {
                      <text [attr.x]="bar.x + bar.width * 1.5 + 1" [attr.y]="chartH - bar.resolvedH - 3" text-anchor="middle" [attr.font-size]="bars.length > 12 ? 8 : 10" font-weight="700" fill="#1D4ED8">{{ bar.resolved }}</text>
                    }
                    @if (bar.showLabel) {
                      <text [attr.x]="bar.x + bar.width" [attr.y]="chartH + 14" text-anchor="middle" [attr.font-size]="bars.length > 12 ? 9 : 11" fill="#475569">{{ bar.label }}</text>
                    }
                  </g>
                }
              </svg>
            } @else {
              <div class="flex h-44 flex-col items-center justify-center gap-1 rounded-[14px] bg-[#F8FAFC] text-center">
                <span class="material-symbols-outlined text-[28px] text-[#94A3B8]">bar_chart</span>
                <p class="text-[12px] text-[#64748B]">{{ state.trends ? 'No hay tickets en este periodo.' : 'Gráfico no disponible.' }}</p>
              </div>
            }
          </div>

          @if (mode() === 'global') {
          <div [class]="card + ' flex flex-col gap-3'">
            <div>
              <h2 class="text-[15px] font-bold">Equipos con más incidencias</h2>
              <p class="text-[11px] text-[#64748B]">Candidatos a revisar o reemplazar</p>
            </div>
            @if (state.topEquipment?.length) {
              <ul class="flex flex-col gap-2">
                @for (item of state.topEquipment; track item.equipment_id) {
                  <li>
                    <a routerLink="/tickets" [queryParams]="{ equipmentId: item.equipment_id }"
                      [class]="'block rounded-lg px-1 py-0.5 !text-inherit transition-colors hover:bg-[#F1F5F9] ' + focus">
                      <div class="flex items-baseline justify-between gap-2 text-[12px]">
                        <span class="min-w-0 truncate font-semibold">{{ item.asset_tag }} <span class="font-normal text-[#64748B]">{{ item.brand }} {{ item.model }}</span></span>
                        <span class="shrink-0 font-bold">{{ item.tickets }}</span>
                      </div>
                      <div class="mt-1 h-1.5 overflow-hidden rounded-full bg-[#E2E8F0]">
                        <div class="h-full rounded-full bg-[#2563EB]" [style.width.%]="share(item.tickets, state.topEquipment![0].tickets)"></div>
                      </div>
                    </a>
                  </li>
                }
              </ul>
            } @else {
              <p class="flex flex-1 items-center justify-center rounded-[14px] bg-[#F8FAFC] px-3 py-6 text-center text-[12px] text-[#64748B]">
                {{ state.topEquipment ? 'Ningún equipo con incidencias en este periodo.' : 'Dato no disponible.' }}
              </p>
            }
          </div>
          }
        </section>

        <section class="grid grid-cols-1 gap-3 lg:grid-cols-3">
          <div [class]="card + ' flex flex-col gap-3 lg:col-span-3'">
            <div class="flex flex-wrap items-start justify-between gap-2">
              <div>
                <h2 class="text-[15px] font-bold">{{ mode() === 'technician' ? 'Mi carga y mi rendimiento' : 'Rendimiento del equipo técnico' }}</h2>
                <p class="text-[11px] text-[#64748B]">{{ periodCaption(state.period) }} · ordenado por tickets abiertos (carga), no por desempeño</p>
              </div>
              @if (canSeeTechnicians()) {
                <a routerLink="/technicians" [class]="'shrink-0 text-[12px] font-medium !text-[#2563EB] hover:underline ' + focus">Ver técnicos</a>
              }
            </div>
            @let techs = state.technicians;
            @if (techs?.length) {
              <div class="overflow-x-auto">
                <table class="w-full min-w-[680px] border-collapse text-left text-[12px]">
                  <caption class="sr-only">Rendimiento por técnico en {{ periodCaption(state.period) }}</caption>
                  <thead>
                    <tr class="border-b border-[#E2E8F0] text-[11px] uppercase tracking-wider text-[#64748B]">
                      <th scope="col" class="py-2 pr-3 font-bold">Técnico</th>
                      <th scope="col" class="px-3 py-2 text-right font-bold">Abiertos</th>
                      <th scope="col" class="px-3 py-2 text-right font-bold">Resueltos</th>
                      <th scope="col" class="px-3 py-2 text-right font-bold">MTTR (mediana)</th>
                      <th scope="col" class="px-3 py-2 text-right font-bold">SLA</th>
                      <th scope="col" class="px-3 py-2 text-right font-bold">n</th>
                      <th scope="col" class="py-2 pl-3 text-right font-bold">Reabiertos</th>
                    </tr>
                  </thead>
                  <tbody>
                    @for (t of techs; track t.technician_id) {
                      <tr class="border-b border-[#F1F5F9] last:border-0">
                        <th scope="row" class="py-2 pr-3 font-normal">
                          <span class="flex items-center gap-2">
                            <span class="h-2 w-2 shrink-0 rounded-full" [class]="t.is_available ? 'bg-[#047857]' : 'bg-[#A16207]'"
                              [attr.title]="t.is_available ? 'Disponible' : 'No disponible'"></span>
                            <span class="min-w-0">
                              <span class="block truncate font-semibold text-[#1E293B]">{{ t.full_name }}</span>
                              <span class="block truncate text-[11px] text-[#64748B]">{{ t.specialization || 'General' }}</span>
                            </span>
                          </span>
                        </th>
                        <td class="px-3 py-2 text-right text-[14px] font-bold text-[#0b1f3a]">{{ t.open_tickets }}</td>
                        <td class="px-3 py-2 text-right">{{ t.resolved }}</td>
                        <td class="px-3 py-2 text-right">
                          @if (t.mttr_median_hours !== null) {
                            <span class="font-semibold">{{ hours(t.mttr_median_hours) }}</span>
                            @if (t.low_sample) {
                              <span class="ml-1 rounded-full bg-[#FEF3C7] px-1.5 py-0.5 text-[10px] font-bold text-[#92400E]">pocos datos</span>
                            }
                          } @else {
                            <span class="text-[#64748B]" title="Sin tickets resueltos en el periodo">—</span>
                          }
                        </td>
                        <td class="px-3 py-2 text-right">
                          @if (t.sla_compliance_pct !== null) {
                            <span class="font-semibold">{{ pct(t.sla_compliance_pct) }}</span>
                            <span class="text-[11px] text-[#64748B]"> (n = {{ t.sla_sample_size }})</span>
                            @if (t.sla_low_sample) {
                              <span class="ml-1 rounded-full bg-[#FEF3C7] px-1.5 py-0.5 text-[10px] font-bold text-[#92400E]">pocos datos</span>
                            }
                          } @else {
                            <span class="text-[#64748B]" [attr.title]="t.sla_excluded_no_sla ? t.sla_excluded_no_sla + ' resueltos sin SLA definido: no se miden' : 'Sin tickets resueltos con SLA'">—</span>
                          }
                          @if (t.sla_excluded_no_sla) {
                            <span class="block text-[10px] text-[#64748B]">{{ t.sla_excluded_no_sla }} sin SLA excluidos</span>
                          }
                        </td>
                        <td class="px-3 py-2 text-right text-[#475569]">{{ t.sample_size }}</td>
                        <td class="py-2 pl-3 text-right" [class]="t.reopened ? 'font-bold text-[#92400E]' : 'text-[#475569]'">{{ t.reopened }}</td>
                      </tr>
                    }
                  </tbody>
                </table>
              </div>
              <p class="text-[11px] text-[#64748B]">n = tickets resueltos en el periodo. Las prioridades sin SLA no entran en el cumplimiento. Reabiertos: pasaron de resuelto a en curso.</p>
            } @else {
              <p class="flex flex-1 items-center justify-center rounded-[14px] bg-[#F8FAFC] px-3 py-6 text-center text-[12px] text-[#64748B]">
                {{ techs ? 'Aún no hay técnicos registrados.' : 'Dato no disponible.' }}
              </p>
            }
          </div>

          <div [class]="card + ' flex flex-col gap-3 lg:col-span-3'">
            <div>
              <h2 class="text-[15px] font-bold">Atención inmediata</h2>
              <p class="text-[11px] text-[#64748B]">Lo que necesita acción ahora, sin importar el periodo</p>
            </div>
            @let alerts = state.alerts;
            @if (alerts && (alerts.tickets.length || alerts.down_equipment.length || alerts.schedules.length)) {
              <ul class="flex flex-col gap-2">
                @for (a of alerts.tickets; track a.id) {
                  <li>
                    <a routerLink="/tickets" [queryParams]="{ ticket: a.id }" [class]="rowClass + ' ' + focus">
                      <span class="material-symbols-outlined mt-0.5 text-[18px]" [class]="a.reason === 'sla_at_risk' ? 'text-[#A16207]' : 'text-[#B45309]'" aria-hidden="true">confirmation_number</span>
                      <div class="min-w-0 flex-1">
                        <p class="truncate text-[13px] font-semibold">{{ a.ticket_number }} · {{ a.title }}</p>
                        <p class="truncate text-[11px] text-[#64748B]">{{ a.asset_tag }} · {{ a.priority }} · {{ a.assigned ? 'asignado' : 'sin asignar' }}@if (a.sla_deadline) { · vence {{ date(a.sla_deadline) }} }</p>
                      </div>
                      <span class="shrink-0 rounded-full bg-[#FEF3C7] px-2 py-0.5 text-[10px] font-bold text-[#92400E]">{{ reason(a.reason) }}</span>
                    </a>
                  </li>
                }
                @for (e of alerts.down_equipment; track e.equipment_id) {
                  <li>
                    <a routerLink="/equipos" [class]="rowClass + ' ' + focus">
                      <span class="material-symbols-outlined mt-0.5 text-[18px] text-[#B45309]" aria-hidden="true">report</span>
                      <div class="min-w-0 flex-1">
                        <p class="truncate text-[13px] font-semibold">{{ e.asset_tag }} · {{ e.brand }} {{ e.model }}</p>
                        <p class="truncate text-[11px] text-[#64748B]">{{ e.status === 'lost' ? 'Extraviado' : 'En mantenimiento' }}</p>
                      </div>
                      <span class="shrink-0 rounded-full bg-[#FEF3C7] px-2 py-0.5 text-[10px] font-bold text-[#92400E]">Caído {{ downtime(e.down_hours) }}</span>
                    </a>
                  </li>
                }
                @for (s of alerts.schedules; track s.id) {
                  <li>
                    <a routerLink="/tickets" [class]="rowClass + ' ' + focus">
                      <span class="material-symbols-outlined mt-0.5 text-[18px] text-[#2563EB]" aria-hidden="true">event_busy</span>
                      <div class="min-w-0 flex-1">
                        <p class="truncate text-[13px] font-semibold">{{ s.title }}</p>
                        <p class="truncate text-[11px] text-[#64748B]">{{ s.asset_tag }} · preventivo</p>
                      </div>
                      <span class="shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold"
                        [class]="s.overdue ? 'bg-[#FEF3C7] text-[#92400E]' : 'bg-[#DBEAFE] text-[#1D4ED8]'">{{ s.overdue ? 'Vencido' : 'Vence' }} {{ date(s.next_due_at) }}</span>
                    </a>
                  </li>
                }
              </ul>
            } @else if (alerts) {
              <div class="flex flex-1 flex-col items-center justify-center gap-1 rounded-xl bg-[#F0FDF4] py-6 text-center">
                <span class="material-symbols-outlined text-[28px] text-[#10B981]" aria-hidden="true">check_circle</span>
                <p class="px-3 text-[12px] text-[#047857]">Todo al día. No hay incidencias prioritarias registradas.</p>
              </div>
            } @else {
              <p class="rounded-[14px] bg-[#F8FAFC] px-3 py-6 text-center text-[12px] text-[#64748B]">Alertas no disponibles.</p>
            }
          </div>
        </section>

        }

        <footer class="flex items-center justify-between gap-3 text-[11px] text-[#64748B]">
          <span class="flex items-center gap-2">
            <span class="material-symbols-outlined text-[18px]">shield</span>
            <strong class="text-[#475569]">Mantix</strong> · Tecnología que mantiene tu productividad
          </span>
          <span>v1.0.0</span>
        </footer>
      </div>
    }
  `,
  styles: [
    `
      /* El visual comparte el fondo del hero: sin caja, borde ni sombra propios,
         y un fundido en el borde izquierdo para que no se note el corte. */
      .hero-visual,
      .hero-gif {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
      }
      /* Capa holográfica: vidrio translúcido que flota sobre la animación. */
      .holo {
        background: rgba(255, 255, 255, 0.62);
        backdrop-filter: blur(10px);
        -webkit-backdrop-filter: blur(10px);
        border: 1px solid rgba(255, 255, 255, 0.55);
        box-shadow: 0 8px 24px rgba(62, 92, 118, 0.12);
      }
      .hero-gif {
        -webkit-mask-image: radial-gradient(ellipse 72% 72% at 55% 50%, #000 55%, transparent 100%);
        mask-image: radial-gradient(ellipse 72% 72% at 55% 50%, #000 55%, transparent 100%);
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class DashboardComponent implements OnInit {
  private readonly store = inject(DashboardStore);
  private readonly profileService = inject(LocalProfileService);
  private readonly permissions = inject(PermissionsService);

  /** El enlace al listado solo lo ve quien puede abrirlo. */
  canSeeTechnicians(): boolean {
    return this.permissions.has('tecnicos:ver');
  }

  readonly state$ = this.store.state$;
  readonly card = CARD;
  readonly focus = LINK_FOCUS;
  readonly rowClass = `flex items-start gap-3 rounded-xl bg-[#F8FAFC] p-2.5 !text-inherit transition-colors hover:bg-[#EFF6FF]`;
  readonly periods = PERIODS;
  readonly chartW = CHART_W;
  readonly chartH = CHART_H;
  readonly userName = signal('');
  /** Qué parte del dashboard corresponde a la persona (según sus permisos, no su nombre de rol). */
  readonly mode = signal<DashboardMode>('global');
  readonly statusLabel = (status: string): string => statusMeta(status).label;
  readonly statusDot = (status: string): string => statusMeta(status).dot;
  readonly priorityLabel = (priority: string): string => priorityMeta(priority).label;

  readonly pct = formatPct;
  readonly hours = formatHours;
  readonly central = formatCentral;
  readonly spread = formatSpread;
  readonly tone = changeTone;
  readonly reason = reasonLabel;
  readonly downtime = formatDowntime;
  readonly date = formatDate;

  async ngOnInit(): Promise<void> {
    await this.permissions.load();
    // Quien ve toda la operación, quien trabaja lo asignado, o quien solo ve lo que pidió.
    this.mode.set(
      this.permissions.has('dashboard:ver_todos')
        ? 'global'
        : this.permissions.has('tickets:ver_asignados')
          ? 'technician'
          : 'requester',
    );
    this.store.load(undefined, this.mode());
    this.userName.set((await this.profileService.getProfile()).full_name);
  }

  setPeriod(period: Period): void {
    this.store.load(period);
  }

  reload(): void {
    this.store.load();
  }

  periodCaption(period: Period): string {
    return PERIODS.find((p) => p.id === period)?.caption ?? '';
  }

  mttrCaption(firstAssignmentHours: number | null): string {
    return firstAssignmentHours === null
      ? 'Tiempo medio de resolución'
      : `Resolución · 1.ª asignación en ${formatHours(firstAssignmentHours)}`;
  }

  slaCaption(kpis: NonNullable<DashboardState['kpis']>): string {
    const sla = kpis.sla_compliance_pct;
    const base = `${sla.met} de ${sla.met + sla.missed} a tiempo`;
    return sla.excluded_no_sla ? `${base} · ${sla.excluded_no_sla} sin SLA excluidos` : base;
  }

  /** Serie del sparkline: un valor por punto de la tendencia (`null` = sin datos ese día). */
  series(trends: TrendsResponse | null, key: 'mttr_hours' | 'sla_compliance_pct'): (number | null)[] {
    return trends ? trends.points.map((point) => point[key]) : [];
  }

  share(value: number, max: number): number {
    return max > 0 ? Math.max((value / max) * 100, value > 0 ? 4 : 0) : 0;
  }


  /** Barras agrupadas (creados / resueltos) escaladas al máximo de la serie. */
  chart(trends: TrendsResponse | null): ChartBar[] {
    if (!trends || trends.points.every((p) => p.created === 0 && p.resolved === 0)) {
      return [];
    }
    const max = Math.max(...trends.points.flatMap((p) => [p.created, p.resolved]), 1);
    const slot = CHART_W / trends.points.length;
    const width = Math.min(slot * 0.4, 18);
    return trends.points.map((point, index) => ({
      x: index * slot + (slot - width * 2 - 1) / 2,
      width,
      createdH: this.barHeight(point.created, max),
      resolvedH: this.barHeight(point.resolved, max),
      label: bucketLabel(point.bucket, trends.granularity, index === 0),
      created: point.created,
      resolved: point.resolved,
      showLabel: trends.points.length <= 12 || (trends.points.length - 1 - index) % 3 === 0,
    }));
  }

  private barHeight(count: number, max: number): number {
    return count ? Math.max((count / max) * (CHART_H - 22), 3) : 0;
  }
}
