import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import {
  DashboardMetrics,
  DashboardStore,
  DayBar,
  SeriesPeriod,
  buildSeries,
} from '../../core/dashboard.store';
import { formatDate } from '../../core/equipment-status';
import { LocalProfileService } from '../../core/local-profile.service';

const CARD =
  'rounded-[18px] bg-white p-3 shadow-[0_8px_25px_rgba(15,23,42,0.05)] transition-all duration-200 motion-reduce:transition-none';
const CARD_LINK = `${CARD} hover:-translate-y-[3px] hover:shadow-[0_12px_28px_rgba(37,99,235,0.12)] motion-reduce:hover:translate-y-0 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#2563EB]`;
const ICON = 'flex h-9 w-9 shrink-0 items-center justify-center rounded-full';
const DONUT_RADIUS = 52;
const DONUT_LENGTH = 2 * Math.PI * DONUT_RADIUS;

export interface DonutSegment {
  key: string;
  name: string;
  count: number;
  color: string;
  dash: string;
  offset: number;
}

const HEALTH_META = [
  { key: 'operational', name: 'Operativos', color: '#10B981' },
  { key: 'maintenance', name: 'En mantenimiento', color: '#F59E0B' },
  { key: 'offline', name: 'Fuera de servicio', color: '#EF4444' },
  { key: 'other', name: 'Otros estados', color: '#94A3B8' },
] as const;

const PERIODS: { id: SeriesPeriod; label: string; caption: string }[] = [
  { id: '7d', label: '7 días', caption: 'Solicitudes creadas en los últimos 7 días' },
  { id: '30d', label: '30 días', caption: 'Solicitudes creadas en los últimos 30 días' },
  { id: '12m', label: '12 meses', caption: 'Solicitudes creadas por mes en el último año' },
];

/** Smart component: carga los indicadores desde el store y los presenta en el panel principal. */
@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [AsyncPipe, RouterLink],
  template: `
    @if (state$ | async; as state) {
      @let m = state.metrics;
      <div class="tw-reset flex w-full flex-col gap-3 font-sans text-[#1E293B]" [attr.aria-busy]="state.loading">
        <!-- Hero: texto + visual sobre un único fondo -->
        <section class="hero relative overflow-hidden rounded-[18px] bg-[linear-gradient(135deg,#eef6ff_0%,#f8fbff_100%)] p-4 shadow-[0_8px_25px_rgba(15,23,42,0.05)] lg:p-5">
          <div class="pointer-events-none absolute -right-20 -top-24 h-80 w-80 rounded-full bg-[#2563EB]/[0.07]"></div>
          <div class="pointer-events-none absolute bottom-[-6rem] left-[38%] h-64 w-64 rotate-45 rounded-[40px] bg-[#3B82F6]/[0.06]"></div>
          <div class="pointer-events-none absolute left-[-3rem] top-1/2 h-40 w-40 rounded-full bg-[#2563EB]/[0.05]"></div>

          <div class="hero-visual absolute inset-y-2 right-2 hidden w-[42%] lg:block"
            (mouseenter)="showKpis.set(true)" (mouseleave)="showKpis.set(false)">
            <video
              class="hero-gif pointer-events-none h-full w-full object-contain object-right mix-blend-multiply"
              src="assets/videos/dashboard1.mp4"
              autoplay
              muted
              loop
              playsinline
              preload="auto"
              aria-hidden="true"></video>
            <div class="holo absolute inset-x-6 bottom-4 flex items-center justify-around gap-4 rounded-[18px] px-5 py-3 text-[#3E5C76] transition-all duration-300 ease-out"
              [class]="showKpis() ? 'translate-y-0 opacity-100' : 'pointer-events-none translate-y-2 opacity-0'">
              <div class="flex items-center gap-3">
                <span class="material-symbols-outlined text-[26px]">desktop_windows</span>
                <div>
                  <span class="block text-[22px] font-bold leading-6">{{ m.equipmentTotal ? m.operationalPct + '%' : '—' }}</span>
                  <span class="block text-[10px] font-bold uppercase tracking-wider text-[#778DA9]">Equipos operativos</span>
                </div>
              </div>
              <span class="h-8 w-[2px] rounded-full bg-[#D4A017]"></span>
              <div class="flex items-center gap-3">
                <span class="material-symbols-outlined text-[26px]">settings</span>
                <div>
                  <span class="block text-[22px] font-bold leading-6">{{ m.monthTickets ? m.resolutionPct + '%' : '—' }}</span>
                  <span class="block text-[10px] font-bold uppercase tracking-wider text-[#778DA9]">Resolución</span>
                </div>
              </div>
            </div>
          </div>

          <div class="relative z-10 flex flex-col gap-3 lg:min-h-[170px] lg:justify-between">
            <div class="flex flex-col gap-2 lg:max-w-[52%]">
              <span class="inline-flex w-fit items-center gap-2 rounded-full bg-white/80 px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-[#1E293B]">
                <span class="h-2 w-2 rounded-full bg-[#2563EB]"></span>
                {{ userName() ? 'Hola, ' + userName() : 'Plataforma central' }}
              </span>
              <h1 class="text-[22px] font-extrabold uppercase leading-[1.1] tracking-tight text-[#0b1f3a] md:text-[28px]">
                Sistema inteligente <br />de mantenimiento
              </h1>
              <p class="max-w-md text-[12px] leading-4 text-[#64748B]">
                Gestión de incidentes y control en tiempo real del parque tecnológico empresarial.
              </p>
            </div>

            <!-- Indicadores complementarios a las tarjetas KPI -->
            <div class="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:max-w-[50%]">
              <div class="flex flex-col gap-2 rounded-[12px] bg-white p-2.5 shadow-[0_8px_25px_rgba(15,23,42,0.06)]">
                <div class="flex items-center gap-3">
                  <span [class]="icon + ' bg-[#DBEAFE] text-[#2563EB]'"><span class="material-symbols-outlined text-[20px]">build</span></span>
                  <div class="min-w-0">
                    <div class="flex items-center gap-2">
                      <span class="truncate text-[13px] font-semibold">Mantenimientos activos</span>
                      @if (m.urgentTickets > 0) {
                        <span class="rounded-full bg-[#FEF3C7] px-2 py-0.5 text-[10px] font-bold text-[#B45309]">{{ m.urgentTickets }} urgentes</span>
                      }
                    </div>
                    <div class="flex items-baseline gap-2">
                      <span class="text-[20px] font-bold leading-6">{{ m.activeTickets }}</span>
                      <span class="text-[12px] text-[#64748B]">en ejecución</span>
                    </div>
                  </div>
                </div>
                <div class="h-1.5 w-full overflow-hidden rounded-full bg-[#E2E8F0]" role="img" [attr.aria-label]="'Resolución del mes ' + m.resolutionPct + '%'">
                  <div class="h-full rounded-full bg-[#2563EB] transition-all duration-700 motion-reduce:transition-none" [style.width.%]="m.resolutionPct"></div>
                </div>
              </div>

              <div class="flex flex-col gap-2 rounded-[12px] bg-white p-2.5 shadow-[0_8px_25px_rgba(15,23,42,0.06)]">
                <div class="flex items-center gap-3">
                  <span [class]="icon + ' bg-[#EDE9FE] text-[#7C3AED]'"><span class="material-symbols-outlined text-[20px]">event_upcoming</span></span>
                  <div class="min-w-0">
                    <span class="block truncate text-[13px] font-semibold">Próximo mantenimiento</span>
                    @if (m.upcoming[0]; as next) {
                      <span class="block truncate text-[20px] font-bold leading-6">{{ fmt(next.dueAt) }}</span>
                      <span class="block truncate text-[12px] text-[#64748B]">{{ next.equipment }}</span>
                    } @else {
                      <span class="block text-[20px] font-bold leading-6">—</span>
                      <span class="block text-[12px] text-[#64748B]">Sin planes programados</span>
                    }
                  </div>
                </div>
                <div class="flex justify-between text-[11px] text-[#64748B]">
                  <span>Técnicos disponibles</span>
                  <span class="font-bold text-[#1E293B]">{{ m.techniciansAvailable }}/{{ m.techniciansTotal }}</span>
                </div>
              </div>
            </div>
          </div>
        </section>

        <!-- KPIs -->
        <section class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3" aria-label="Indicadores clave">
          @for (kpi of kpis(m); track kpi.label) {
            <a [routerLink]="kpi.link" [class]="cardLink + ' group flex min-h-[116px] flex-col gap-2'" [attr.aria-label]="kpi.label + ': ' + kpi.value">
              <div class="flex items-start justify-between gap-3">
                <div class="flex items-center gap-3">
                  <span [class]="icon + ' ' + kpi.tone"><span class="material-symbols-outlined text-[20px]">{{ kpi.icon }}</span></span>
                  <span class="text-[12px] font-bold uppercase tracking-wider text-[#64748B]">{{ kpi.label }}</span>
                </div>
                <span class="material-symbols-outlined text-[18px] text-[#94A3B8] transition-transform group-hover:translate-x-0.5 motion-reduce:transition-none">arrow_forward</span>
              </div>
              <div class="flex items-end justify-between gap-2">
                <div>
                  <span class="text-[22px] font-bold leading-7">{{ kpi.value }}</span>
                  <p class="text-[12px] text-[#64748B]">{{ kpi.caption }}</p>
                </div>
                @if (kpi.badge; as badge) {
                  <span class="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="badge.cls">{{ badge.text }}</span>
                }
              </div>
            </a>
          }
        </section>

        <!-- Gráficos -->
        <section class="grid grid-cols-1 gap-3 lg:grid-cols-6">
          <div [class]="card + ' flex flex-col gap-3 lg:col-span-3'">
            <div class="flex flex-wrap items-start justify-between gap-2">
              <div class="flex items-center gap-3">
                <span [class]="icon + ' rounded-xl bg-[#DBEAFE] text-[#2563EB]'"><span class="material-symbols-outlined text-[20px]">event_note</span></span>
                <div>
                  <h2 class="text-[15px] font-bold">Mantenimientos por periodo</h2>
                  <p class="text-[11px] text-[#64748B]">{{ periodCaption() }}</p>
                </div>
              </div>
              <div class="flex rounded-full bg-[#F1F5F9] p-0.5" role="group" aria-label="Periodo del gráfico">
                @for (p of periods; track p.id) {
                  <button type="button" (click)="period.set(p.id)" [attr.aria-pressed]="period() === p.id"
                    class="rounded-full px-3 py-1 text-[11px] font-semibold transition-colors active:scale-95 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#2563EB]"
                    [class]="period() === p.id ? 'bg-white text-[#2563EB] shadow-sm' : 'text-[#64748B] hover:text-[#1E293B]'">
                    {{ p.label }}
                  </button>
                }
              </div>
            </div>

            @let bars = series(m);
            @if (total(bars) > 0) {
              <div class="flex h-36 items-end gap-1" role="img" [attr.aria-label]="periodCaption() + ': ' + total(bars) + ' en total'">
                @for (bar of bars; track $index) {
                  <div class="flex h-full min-w-0 flex-1 flex-col items-center justify-end gap-1" [attr.title]="bar.label + ': ' + bar.count">
                    <span class="text-[10px] font-semibold leading-3" [class]="bar.isPeak ? 'text-[#2563EB]' : 'text-[#64748B]'">
                      {{ showValue(bar, bars.length) ? bar.count : '' }}
                    </span>
                    <div class="w-full max-w-[28px] rounded-t-md transition-all duration-500 motion-reduce:transition-none"
                      [class]="bar.isPeak ? 'bg-[#2563EB]' : 'bg-[#BFDBFE]'"
                      [style.height.%]="barHeight(bar, bars)"></div>
                    <span class="h-3 text-[10px] leading-3" [class]="bar.isPeak ? 'font-bold text-[#2563EB]' : 'text-[#64748B]'">
                      {{ showLabel($index, bars.length) ? bar.label : '' }}
                    </span>
                  </div>
                }
              </div>
              <div class="flex items-center justify-between border-t border-[#F1F5F9] pt-2 text-[11px] text-[#64748B]">
                <span>Valor máximo destacado en azul</span>
                <span class="font-bold uppercase tracking-wider">Total: {{ total(bars) }} sol.</span>
              </div>
            } @else {
              <div class="flex h-36 flex-col items-center justify-center gap-1 rounded-[14px] bg-[#F8FAFC] text-center">
                <span class="material-symbols-outlined text-[28px] text-[#94A3B8]">bar_chart</span>
                <p class="text-[12px] text-[#64748B]">No hay solicitudes en este periodo.</p>
              </div>
            }
          </div>

          <div [class]="card + ' flex flex-col gap-3 lg:col-span-3'">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3">
                <span [class]="icon + ' rounded-xl bg-[#DBEAFE] text-[#2563EB]'"><span class="material-symbols-outlined text-[20px]">monitor_heart</span></span>
                <div>
                  <h2 class="text-[15px] font-bold">Salud de equipos</h2>
                  <p class="text-[11px] text-[#64748B]">Cada equipo en un único estado</p>
                </div>
              </div>
              <a routerLink="/equipos" aria-label="Ir a inventario" class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#F1F5F9] !text-[#64748B] transition-colors hover:bg-[#E2E8F0] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#2563EB]">
                <span class="material-symbols-outlined text-[18px]">arrow_forward</span>
              </a>
            </div>
            @let segments = donut(m);
            @if (m.equipmentTotal > 0) {
              <div class="flex flex-1 flex-wrap items-center gap-5">
                <div class="relative h-[120px] w-[120px] shrink-0">
                  <svg viewBox="0 0 130 130" class="h-full w-full -rotate-90" role="img" aria-label="Equipos por estado">
                    <circle cx="65" cy="65" [attr.r]="radius" fill="none" stroke="#E2E8F0" stroke-width="14" />
                    @for (seg of segments; track seg.key) {
                      <circle cx="65" cy="65" [attr.r]="radius" fill="none" [attr.stroke]="seg.color" stroke-width="14"
                        [attr.stroke-dasharray]="seg.dash" [attr.stroke-dashoffset]="seg.offset">
                        <title>{{ seg.name }}: {{ seg.count }}</title>
                      </circle>
                    }
                  </svg>
                  <div class="absolute inset-0 flex flex-col items-center justify-center">
                    <span class="text-[22px] font-bold leading-6">{{ m.equipmentTotal }}</span>
                    <span class="text-[11px] text-[#64748B]">equipos</span>
                  </div>
                </div>
                <ul class="flex min-w-0 flex-1 flex-col gap-1 text-[12px]">
                  @for (seg of segments; track seg.key) {
                    <li>
                      <a routerLink="/equipos" class="flex items-center gap-2 rounded-lg px-2 py-1 !text-inherit transition-colors hover:bg-[#F1F5F9] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#2563EB]">
                        <span class="h-2.5 w-2.5 shrink-0 rounded-full" [style.background]="seg.color"></span>
                        <span class="min-w-0 flex-1 truncate text-[#64748B]">{{ seg.name }}</span>
                        <span class="font-semibold">{{ seg.count }}</span>
                      </a>
                    </li>
                  }
                </ul>
              </div>
            } @else {
              <div class="flex flex-1 flex-col items-center justify-center gap-1 rounded-[14px] bg-[#F8FAFC] py-6 text-center">
                <span class="material-symbols-outlined text-[28px] text-[#94A3B8]">devices_other</span>
                <p class="text-[12px] text-[#64748B]">Sin equipos registrados.</p>
              </div>
            }
          </div>
        </section>

        <!-- Atención, mantenimientos y técnicos -->
        <section class="grid grid-cols-1 gap-3 lg:grid-cols-3">
          <div [class]="card + ' flex flex-col gap-2'">
            <div class="flex items-center gap-3">
              <span [class]="icon + ' rounded-xl bg-[#FEF3C7] text-[#F59E0B]'"><span class="material-symbols-outlined text-[20px]">priority_high</span></span>
              <div>
                <h2 class="text-[15px] font-bold">Atención prioritaria</h2>
                <p class="text-[11px] text-[#64748B]">Lo que requiere acción</p>
              </div>
            </div>
            <ul class="flex flex-col gap-2">
              @for (item of m.attention; track $index) {
                <li>
                  <a [routerLink]="item.link" class="flex items-start gap-3 rounded-xl bg-[#F8FAFC] p-2.5 !text-inherit transition-colors hover:bg-[#EFF6FF] focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#2563EB]">
                    <span class="mt-1 h-2 w-2 shrink-0 rounded-full" [class]="item.critical ? 'bg-[#EF4444]' : 'bg-[#F59E0B]'"></span>
                    <div class="min-w-0 flex-1">
                      <p class="truncate text-[13px] font-semibold">{{ item.title }}</p>
                      <p class="truncate text-[11px] text-[#64748B]">{{ item.equipment }}</p>
                      <p class="text-[11px] text-[#64748B]">{{ item.detail }}@if (item.date) { · {{ fmt(item.date) }} }</p>
                    </div>
                  </a>
                </li>
              } @empty {
                <li class="flex flex-col items-center gap-1 rounded-xl bg-[#F0FDF4] py-5 text-center">
                  <span class="material-symbols-outlined text-[28px] text-[#10B981]">check_circle</span>
                  <p class="px-3 text-[12px] text-[#047857]">Todo al día. No hay incidencias prioritarias registradas.</p>
                </li>
              }
            </ul>
          </div>

          <div [class]="card + ' flex flex-col gap-2'">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3">
                <span [class]="icon + ' rounded-xl bg-[#DBEAFE] text-[#2563EB]'"><span class="material-symbols-outlined text-[20px]">event_upcoming</span></span>
                <div>
                  <h2 class="text-[15px] font-bold">Próximos mantenimientos</h2>
                  <p class="text-[11px] text-[#64748B]">Planes preventivos programados</p>
                </div>
              </div>
              <a routerLink="/maintenance" class="shrink-0 text-[12px] font-medium !text-[#2563EB] hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#2563EB]">Ver todos</a>
            </div>
            <ul class="flex flex-col gap-2">
              @for (item of m.upcoming; track item.id) {
                <li class="flex items-center gap-3 rounded-xl bg-[#F8FAFC] p-2.5">
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-[13px] font-semibold">{{ item.title }}</p>
                    <p class="truncate text-[11px] text-[#64748B]">{{ item.equipment }}</p>
                    <p class="truncate text-[11px] text-[#64748B]">{{ item.technician ?? 'Sin técnico asignado' }}</p>
                  </div>
                  <span class="shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold"
                    [class]="item.overdue ? 'bg-[#FEE2E2] text-[#B91C1C]' : 'bg-[#DBEAFE] text-[#1D4ED8]'">
                    {{ item.overdue ? 'Vencido' : 'Programado' }} · {{ fmt(item.dueAt) }}
                  </span>
                </li>
              } @empty {
                <li class="flex flex-col items-center gap-2 rounded-xl bg-[#F8FAFC] py-5 text-center">
                  <span class="material-symbols-outlined text-[28px] text-[#94A3B8]">event_available</span>
                  <p class="px-3 text-[12px] text-[#64748B]">No hay mantenimientos programados.</p>
                  <a routerLink="/equipos" class="inline-flex h-8 items-center gap-2 rounded-full bg-[#DBEAFE] px-4 text-[12px] font-medium !text-[#2563EB] hover:bg-[#BFDBFE]">
                    Programar desde un equipo
                  </a>
                </li>
              }
            </ul>
          </div>

          <div [class]="card + ' flex flex-col gap-2'">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3">
                <span [class]="icon + ' rounded-xl bg-[#DBEAFE] text-[#2563EB]'"><span class="material-symbols-outlined text-[20px]">groups</span></span>
                <div>
                  <h2 class="text-[15px] font-bold">Equipo técnico</h2>
                  <p class="text-[11px] text-[#64748B]">Disponibilidad y carga</p>
                </div>
              </div>
              <a routerLink="/technicians" class="shrink-0 text-[12px] font-medium !text-[#2563EB] hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#2563EB]">Ver todos</a>
            </div>
            <ul class="flex flex-col gap-2">
              @for (tech of m.technicianRows; track tech.id) {
                <li class="flex items-center gap-3 rounded-xl bg-[#F8FAFC] p-2.5">
                  <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#2563EB] text-[12px] font-bold text-white" aria-hidden="true">{{ initialsOf(tech.name) }}</span>
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-[13px] font-semibold">{{ tech.name }}</p>
                    <p class="truncate text-[11px] text-[#64748B]">{{ tech.specialization || 'General' }}</p>
                    @if (tech.openTickets !== null) {
                      <div class="mt-1 flex items-center gap-2">
                        <div class="h-1 flex-1 overflow-hidden rounded-full bg-[#E2E8F0]">
                          <div class="h-full rounded-full bg-[#2563EB]" [style.width.%]="loadPct(tech.openTickets, m)"></div>
                        </div>
                        <span class="text-[10px] text-[#64748B]">{{ tech.openTickets }} abiertos</span>
                      </div>
                    }
                  </div>
                  <span class="shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold"
                    [class]="tech.isAvailable ? 'bg-[#D1FAE5] text-[#047857]' : 'bg-[#FEF3C7] text-[#B45309]'">
                    {{ tech.isAvailable ? 'LIBRE' : 'OCUPADO' }}
                  </span>
                </li>
              } @empty {
                <li class="flex flex-col items-center gap-2 rounded-xl bg-[#F8FAFC] py-5 text-center">
                  <span class="material-symbols-outlined text-[28px] text-[#94A3B8]">groups</span>
                  <p class="text-[12px] text-[#64748B]">Aún no hay técnicos registrados.</p>
                  <a routerLink="/technicians" class="inline-flex h-8 items-center gap-2 rounded-full bg-[#DBEAFE] px-4 text-[12px] font-medium !text-[#2563EB] hover:bg-[#BFDBFE]">
                    Gestionar técnicos
                  </a>
                </li>
              }
            </ul>
          </div>
        </section>

        <footer class="flex items-center justify-between gap-3 text-[11px] text-[#94A3B8]">
          <span class="flex items-center gap-2">
            <span class="material-symbols-outlined text-[18px]">shield</span>
            <strong class="text-[#64748B]">Mantix</strong> · Tecnología que mantiene tu productividad
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
        background: rgba(255, 255, 255, 0.08);
        backdrop-filter: blur(10px);
        -webkit-backdrop-filter: blur(10px);
        border: 1px solid rgba(255, 255, 255, 0.15);
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

  readonly state$ = this.store.state$;
  readonly card = CARD;
  readonly cardLink = CARD_LINK;
  readonly icon = ICON;
  readonly radius = DONUT_RADIUS;
  readonly periods = PERIODS;
  readonly userName = signal('');
  readonly showKpis = signal(false);
  readonly period = signal<SeriesPeriod>('7d');

  readonly fmt = formatDate;

  async ngOnInit(): Promise<void> {
    this.store.load();
    this.userName.set((await this.profileService.getProfile()).full_name);
  }

  periodCaption(): string {
    return PERIODS.find((p) => p.id === this.period())?.caption ?? '';
  }

  series(m: DashboardMetrics): DayBar[] {
    return buildSeries(m.tickets, this.period());
  }

  total(bars: DayBar[]): number {
    return bars.reduce((sum, bar) => sum + bar.count, 0);
  }

  /** Altura relativa a la barra más alta; mínimo visible para los valores en cero. */
  barHeight(bar: DayBar, bars: DayBar[]): number {
    const max = Math.max(...bars.map((b) => b.count), 1);
    return Math.max((bar.count / max) * 80, 3);
  }

  /** Con 30 barras solo se rotula el valor máximo y cada 5.º día, para que siga legible. */
  showValue(bar: DayBar, size: number): boolean {
    return size <= 12 || bar.isPeak;
  }

  showLabel(index: number, size: number): boolean {
    return size <= 12 || index % 5 === 0 || index === size - 1;
  }

  initialsOf(name: string): string {
    return name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0].toUpperCase())
      .join('');
  }

  /** Carga relativa al técnico con más tickets abiertos. */
  loadPct(open: number, m: DashboardMetrics): number {
    const max = Math.max(...m.technicianRows.map((t) => t.openTickets ?? 0), 1);
    return Math.max((open / max) * 100, open > 0 ? 6 : 0);
  }

  /** Arcos del donut: categorías excluyentes; las vacías no se dibujan. */
  donut(m: DashboardMetrics): DonutSegment[] {
    const items = HEALTH_META.map((meta) => ({ ...meta, count: m.health[meta.key] })).filter((i) => i.count > 0);
    const total = items.reduce((sum, item) => sum + item.count, 0);
    let consumed = 0;
    return items.map((item) => {
      const length = total ? (item.count / total) * DONUT_LENGTH : 0;
      const segment: DonutSegment = {
        key: item.key,
        name: item.name,
        count: item.count,
        color: item.color,
        dash: `${length} ${DONUT_LENGTH - length}`,
        offset: -consumed,
      };
      consumed += length;
      return segment;
    });
  }

  kpis(m: DashboardMetrics): Kpi[] {
    const trend = m.monthTrendPct;
    return [
      {
        label: 'Equipos totales', icon: 'desktop_windows', tone: 'bg-[#DBEAFE] text-[#2563EB]',
        value: String(m.equipmentTotal), caption: `${m.operationalPct}% operativos`, link: '/equipos', badge: null,
      },
      {
        label: 'Mantenimientos del mes', icon: 'calendar_month', tone: 'bg-[#D1FAE5] text-[#10B981]',
        value: String(m.monthTickets), caption: `${m.monthDone} resueltos / ${m.monthTickets - m.monthDone} abiertos`,
        link: '/maintenance',
        badge: trend === null ? null : {
          text: `${trend > 0 ? '+' : ''}${trend}% vs mes anterior`,
          cls: trend > 0 ? 'bg-[#FEF3C7] text-[#B45309]' : 'bg-[#D1FAE5] text-[#047857]',
        },
      },
      {
        label: 'Técnicos activos', icon: 'build', tone: 'bg-[#DBEAFE] text-[#2563EB]',
        value: String(m.techniciansTotal), caption: `${m.techniciansAvailable} disponibles ahora`, link: '/technicians', badge: null,
      },
      {
        label: 'Fuera de servicio', icon: 'report', tone: m.health.offline ? 'bg-[#FEE2E2] text-[#EF4444]' : 'bg-[#D1FAE5] text-[#10B981]',
        value: String(m.health.offline), caption: m.health.offline ? 'Extraviados, retirados o de baja' : 'Ningún equipo fuera de servicio',
        link: '/equipos', badge: null,
      },
      {
        label: 'Mantenimientos vencidos', icon: 'event_busy', tone: m.overdueSchedules ? 'bg-[#FEF3C7] text-[#F59E0B]' : 'bg-[#D1FAE5] text-[#10B981]',
        value: String(m.overdueSchedules), caption: m.overdueSchedules ? 'Planes preventivos atrasados' : 'Planes preventivos al día',
        link: '/maintenance', badge: null,
      },
      {
        label: 'Solicitudes pendientes', icon: 'pending_actions', tone: 'bg-[#EDE9FE] text-[#7C3AED]',
        value: String(m.pendingTickets), caption: 'En cola de triaje y asignación', link: '/tickets', badge: null,
      },
    ];
  }
}

interface Kpi {
  label: string;
  icon: string;
  tone: string;
  value: string;
  caption: string;
  link: string;
  badge: { text: string; cls: string } | null;
}
