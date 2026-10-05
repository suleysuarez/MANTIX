import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { DashboardStore, DayBar, TypeCount } from '../../core/dashboard.store';
import { LocalProfileService } from '../../core/local-profile.service';

const CARD =
  'rounded-[18px] bg-white p-3 shadow-[0_8px_25px_rgba(15,23,42,0.05)] transition-transform duration-200 hover:-translate-y-[3px]';
const ICON = 'flex h-9 w-9 shrink-0 items-center justify-center rounded-full';
const PALETTE = ['#60A5FA', '#8B5CF6', '#2563EB', '#F59E0B', '#10B981', '#94A3B8'];
const DONUT_RADIUS = 52;
const DONUT_LENGTH = 2 * Math.PI * DONUT_RADIUS;

export interface DonutSegment {
  name: string;
  count: number;
  color: string;
  dash: string;
  offset: number;
}

/** Smart component: carga los indicadores desde el store y los presenta en el panel principal. */
@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [AsyncPipe, RouterLink],
  template: `
    @if (state$ | async; as state) {
      @let m = state.metrics;
      <div class="tw-reset flex w-full flex-col gap-3 font-sans text-[#1E293B]">
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
                  <span class="block text-[22px] font-bold leading-6">{{ m.operationalPct }}%</span>
                  <span class="block text-[10px] font-bold uppercase tracking-wider text-[#778DA9]">Equipos operativos</span>
                </div>
              </div>
              <span class="h-8 w-[2px] rounded-full bg-[#D4A017]"></span>
              <div class="flex items-center gap-3">
                <span class="material-symbols-outlined text-[26px]">settings</span>
                <div>
                  <span class="block text-[22px] font-bold leading-6">{{ m.resolutionPct }}%</span>
                  <span class="block text-[10px] font-bold uppercase tracking-wider text-[#778DA9]">Resolución</span>
                </div>
              </div>
            </div>
          </div>

          <div class="relative z-10 flex flex-col gap-3 lg:min-h-[190px] lg:justify-between">
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

            <div class="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:max-w-[50%]">
              <div class="flex flex-col gap-3 rounded-[12px] bg-white p-2.5 shadow-[0_8px_25px_rgba(15,23,42,0.06)]">
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
                <div>
                  <div class="mb-1 flex justify-between text-[11px] text-[#64748B]">
                    <span>Resueltos del mes</span><span class="font-bold text-[#1E293B]">{{ m.resolutionPct }}%</span>
                  </div>
                  <div class="h-1.5 w-full overflow-hidden rounded-full bg-[#E2E8F0]">
                    <div class="h-full rounded-full bg-[#2563EB] transition-all duration-700" [style.width.%]="m.resolutionPct"></div>
                  </div>
                </div>
              </div>

              <div class="flex flex-col gap-3 rounded-[12px] bg-white p-2.5 shadow-[0_8px_25px_rgba(15,23,42,0.06)]">
                <div class="flex items-center gap-3">
                  <span [class]="icon + ' bg-[#EDE9FE] text-[#7C3AED]'"><span class="material-symbols-outlined text-[20px]">calendar_month</span></span>
                  <div class="min-w-0">
                    <span class="block truncate text-[13px] font-semibold">Pendientes de asignación</span>
                    <div class="flex items-baseline gap-2">
                      <span class="text-[20px] font-bold leading-6">{{ m.pendingTickets }}</span>
                      <span class="text-[12px] text-[#64748B]">en cola de triaje</span>
                    </div>
                  </div>
                </div>
                <div>
                  <div class="mb-1 flex justify-between text-[11px] text-[#64748B]">
                    <span>Técnicos disponibles</span>
                    <span class="font-bold text-[#1E293B]">{{ m.techniciansAvailable }}/{{ m.techniciansTotal }}</span>
                  </div>
                  <div class="h-1.5 w-full overflow-hidden rounded-full bg-[#E2E8F0]">
                    <div class="h-full rounded-full bg-[#7C3AED] transition-all duration-700"
                      [style.width.%]="m.techniciansTotal ? (m.techniciansAvailable / m.techniciansTotal) * 100 : 0"></div>
                  </div>
                </div>
              </div>
            </div>
          </div>

        </section>

        <!-- KPIs -->
        <section class="grid grid-cols-1 gap-3 md:grid-cols-3">
          <div [class]="card + ' flex flex-col gap-2'">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3">
                <span [class]="icon + ' bg-[#DBEAFE] text-[#2563EB]'"><span class="material-symbols-outlined text-[20px]">desktop_windows</span></span>
                <span class="text-[12px] font-bold uppercase tracking-wider text-[#64748B]">Equipos totales</span>
              </div>
              <a routerLink="/equipos" aria-label="Ir a equipos" class="flex h-8 w-8 items-center justify-center rounded-full bg-[#F1F5F9] !text-[#64748B] hover:bg-[#E2E8F0]">
                <span class="material-symbols-outlined text-[18px]">arrow_forward</span>
              </a>
            </div>
            <div>
              <span class="text-[22px] font-bold leading-7">{{ m.equipmentTotal }}</span>
              <p class="text-[12px] text-[#64748B]">Activos registrados en el inventario</p>
            </div>
            <a routerLink="/equipos" class="flex h-8 items-center gap-2 rounded-xl bg-[#EFF6FF] px-4 text-[13px] font-medium !text-[#2563EB] hover:bg-[#DBEAFE]">
              Ver equipos registrados <span class="material-symbols-outlined text-[16px]">arrow_forward</span>
            </a>
          </div>

          <div [class]="card + ' flex flex-col gap-2'">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3">
                <span [class]="icon + ' bg-[#D1FAE5] text-[#10B981]'"><span class="material-symbols-outlined text-[20px]">calendar_month</span></span>
                <span class="text-[12px] font-bold uppercase tracking-wider text-[#64748B]">Mantenimientos del mes</span>
              </div>
              <a routerLink="/maintenance" aria-label="Ir a mantenimientos" class="flex h-8 w-8 items-center justify-center rounded-full bg-[#F1F5F9] !text-[#64748B] hover:bg-[#E2E8F0]">
                <span class="material-symbols-outlined text-[18px]">arrow_forward</span>
              </a>
            </div>
            <div>
              <span class="text-[22px] font-bold leading-7">{{ m.monthTickets }}</span>
              <p class="text-[12px] text-[#64748B]">{{ m.monthDone }} resueltos / {{ m.monthTickets - m.monthDone }} abiertos</p>
            </div>
            <div>
              <div class="flex h-2 w-full overflow-hidden rounded-full bg-[#E2E8F0]">
                <div class="h-full bg-[#10B981]" [style.width.%]="m.resolutionPct"></div>
                <div class="h-full bg-[#F59E0B]" [style.width.%]="m.monthTickets ? 100 - m.resolutionPct : 0"></div>
              </div>
              <div class="mt-2 text-[12px] text-[#64748B]">
                Tasa de resolución: <strong class="text-[#1E293B]">{{ m.resolutionPct }}%</strong>
              </div>
            </div>
          </div>

          <div [class]="card + ' flex flex-col gap-2'">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3">
                <span [class]="icon + ' bg-[#FEF3C7] text-[#F59E0B]'"><span class="material-symbols-outlined text-[20px]">build</span></span>
                <span class="text-[12px] font-bold uppercase tracking-wider text-[#64748B]">Técnicos activos</span>
              </div>
              <a routerLink="/technicians" aria-label="Ir a técnicos" class="flex h-8 w-8 items-center justify-center rounded-full bg-[#F1F5F9] !text-[#64748B] hover:bg-[#E2E8F0]">
                <span class="material-symbols-outlined text-[18px]">arrow_forward</span>
              </a>
            </div>
            <div>
              <span class="text-[22px] font-bold leading-7">{{ m.techniciansTotal }}</span>
              <p class="text-[12px] text-[#64748B]">{{ m.techniciansAvailable }} disponibles ahora</p>
            </div>
            <a routerLink="/technicians" class="flex h-8 items-center gap-2 rounded-xl bg-[#EFF6FF] px-4 text-[13px] font-medium !text-[#2563EB] hover:bg-[#DBEAFE]">
              Ver equipo <span class="material-symbols-outlined text-[16px]">arrow_forward</span>
            </a>
          </div>
        </section>

        <!-- Detalle -->
        <section class="grid grid-cols-1 gap-3 lg:grid-cols-3">
          <div [class]="card + ' flex flex-col gap-2'">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3">
                <span [class]="icon + ' rounded-xl bg-[#DBEAFE] text-[#2563EB]'"><span class="material-symbols-outlined text-[20px]">event_note</span></span>
                <div>
                  <h2 class="text-[15px] font-bold">Mantenimientos por semana</h2>
                  <p class="text-[11px] text-[#64748B]">Solicitudes creadas en los últimos 7 días</p>
                </div>
              </div>
              <a routerLink="/maintenance" aria-label="Ir a mantenimientos" class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#F1F5F9] !text-[#64748B] hover:bg-[#E2E8F0]">
                <span class="material-symbols-outlined text-[18px]">arrow_forward</span>
              </a>
            </div>
            <div class="flex h-16 items-end justify-between gap-2 px-1">
              @for (day of m.week; track $index) {
                <div class="flex h-full flex-1 flex-col items-center justify-end gap-2">
                  <span class="text-[11px] font-semibold" [class]="day.isPeak ? 'text-[#2563EB]' : 'text-[#64748B]'">{{ day.count }}</span>
                  <div class="w-full max-w-[26px] rounded-full transition-all"
                    [class]="day.isPeak ? 'bg-[#2563EB]' : 'bg-[#BFDBFE]'"
                    [style.height.%]="barHeight(day, m.week)"></div>
                  <span class="text-[11px]" [class]="day.isPeak ? 'font-bold text-[#2563EB]' : 'text-[#64748B]'">{{ day.label }}</span>
                </div>
              }
            </div>
            <div class="flex items-center justify-between border-t border-[#F1F5F9] pt-3 text-[11px] text-[#64748B]">
              <span>Pico destacado en azul</span>
              <span class="font-bold uppercase tracking-wider">Total: {{ m.weekTotal }} sol.</span>
            </div>
          </div>

          <div [class]="card + ' flex flex-col gap-2'">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3">
                <span [class]="icon + ' rounded-xl bg-[#DBEAFE] text-[#2563EB]'"><span class="material-symbols-outlined text-[20px]">monitor_heart</span></span>
                <div>
                  <h2 class="text-[15px] font-bold">Salud de equipos</h2>
                  <p class="text-[11px] text-[#64748B]">Inventario por categoría</p>
                </div>
              </div>
              <a routerLink="/equipos" aria-label="Ir a inventario" class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#F1F5F9] !text-[#64748B] hover:bg-[#E2E8F0]">
                <span class="material-symbols-outlined text-[18px]">arrow_forward</span>
              </a>
            </div>
            <div class="flex flex-1 items-center gap-5">
              <div class="relative h-[88px] w-[88px] shrink-0">
                <svg viewBox="0 0 130 130" class="h-full w-full -rotate-90" role="img" aria-label="Equipos por categoría">
                  <circle cx="65" cy="65" [attr.r]="radius" fill="none" stroke="#DBEAFE" stroke-width="14" />
                  @for (seg of donut(m.byType); track seg.name) {
                    <circle cx="65" cy="65" [attr.r]="radius" fill="none" [attr.stroke]="seg.color" stroke-width="14"
                      [attr.stroke-dasharray]="seg.dash" [attr.stroke-dashoffset]="seg.offset" />
                  }
                </svg>
                <div class="absolute inset-0 flex flex-col items-center justify-center">
                  <span class="text-[20px] font-bold leading-6">{{ m.equipmentTotal }}</span>
                  <span class="text-[11px] text-[#64748B]">equipos</span>
                </div>
              </div>
              <ul class="flex min-w-0 flex-1 flex-col gap-2 text-[12px]">
                @for (seg of donut(m.byType); track seg.name) {
                  <li class="flex items-center gap-2">
                    <span class="h-2 w-2 shrink-0 rounded-full" [style.background]="seg.color"></span>
                    <span class="min-w-0 flex-1 truncate text-[#64748B]">{{ seg.name }}</span>
                    <span class="font-semibold">{{ seg.count }}</span>
                  </li>
                } @empty {
                  <li class="text-[#64748B]">Sin equipos registrados</li>
                }
              </ul>
            </div>
          </div>

          <div [class]="card + ' flex flex-col gap-2'">
            <div class="flex items-start justify-between gap-3">
              <div class="flex items-center gap-3">
                <span [class]="icon + ' rounded-xl bg-[#DBEAFE] text-[#2563EB]'"><span class="material-symbols-outlined text-[20px]">groups</span></span>
                <div>
                  <h2 class="text-[15px] font-bold">Equipo técnico</h2>
                  <p class="text-[11px] text-[#64748B]">Disponibilidad actual</p>
                </div>
              </div>
              <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#FEF3C7] text-[#F59E0B]">
                <span class="material-symbols-outlined text-[18px]">emoji_events</span>
              </span>
            </div>
            <div class="flex max-h-[96px] flex-1 flex-col gap-2 overflow-y-auto rounded-[14px] bg-[#F8FAFC] p-3">
              @for (tech of m.technicians; track tech.id) {
                <div class="flex items-center gap-3 rounded-xl bg-white p-2.5">
                  <span class="flex h-9 w-9 items-center justify-center rounded-full bg-[#2563EB] text-[12px] font-bold text-white">T{{ tech.id }}</span>
                  <div class="min-w-0 flex-1">
                    <h3 class="truncate text-[13px] font-semibold">Técnico #{{ tech.id }}</h3>
                    <span class="text-[11px] text-[#64748B]">{{ tech.specialization || 'General' }}</span>
                  </div>
                  <span class="rounded-full px-2 py-0.5 text-[10px] font-bold"
                    [class]="tech.is_available ? 'bg-[#D1FAE5] text-[#047857]' : 'bg-[#FEF3C7] text-[#B45309]'">
                    {{ tech.is_available ? 'LIBRE' : 'OCUPADO' }}
                  </span>
                </div>
              } @empty {
                <div class="flex flex-1 flex-col items-center justify-center gap-2 py-1 text-center">
                  <span class="material-symbols-outlined text-[28px] text-[#94A3B8]">groups</span>
                  <p class="text-[12px] text-[#64748B]">Aún no hay técnicos registrados.</p>
                  <a routerLink="/technicians" class="inline-flex h-9 items-center gap-2 rounded-full bg-[#DBEAFE] px-4 text-[12px] font-medium !text-[#2563EB] hover:bg-[#BFDBFE]">
                    Gestionar técnicos <span class="material-symbols-outlined text-[16px]">arrow_forward</span>
                  </a>
                </div>
              }
            </div>
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
  readonly icon = ICON;
  readonly radius = DONUT_RADIUS;
  readonly userName = signal('');
  readonly showKpis = signal(false);

  async ngOnInit(): Promise<void> {
    this.store.load();
    this.userName.set((await this.profileService.getProfile()).full_name);
  }

  /** Altura relativa al día con más solicitudes; mínimo visible para los días en cero. */
  barHeight(day: DayBar, week: DayBar[]): number {
    const max = Math.max(...week.map((d) => d.count), 1);
    return Math.max((day.count / max) * 80, 4);
  }

  /** Arcos del donut: cada categoría ocupa su fracción de la circunferencia. */
  donut(byType: TypeCount[]): DonutSegment[] {
    const total = byType.reduce((sum, type) => sum + type.count, 0);
    let consumed = 0;
    return byType.map((type, index) => {
      const length = total ? (type.count / total) * DONUT_LENGTH : 0;
      const segment: DonutSegment = {
        name: type.name,
        count: type.count,
        color: PALETTE[index % PALETTE.length],
        dash: `${length} ${DONUT_LENGTH - length}`,
        offset: -consumed,
      };
      consumed += length;
      return segment;
    });
  }
}
