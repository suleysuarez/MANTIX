import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { DashboardStore, DayBar } from '../../core/dashboard.store';
import { LocalProfileService } from '../../core/local-profile.service';

const CARD = 'rounded-[24px] bg-surface-container-lowest p-space-lg shadow-[0_4px_20px_-2px_rgba(43,66,87,0.05),0_2px_6px_-1px_rgba(43,66,87,0.03)]';

/** Smart component: carga los indicadores desde el store y los presenta en el panel principal. */
@Component({
  standalone: true,
  imports: [AsyncPipe, RouterLink],
  template: `
    @if (state$ | async; as state) {
      @let m = state.metrics;
      <div class="tw-reset flex w-full flex-col gap-space-lg px-space-xl pb-space-xl font-sans text-on-surface">
        <!-- Hero -->
        <section class="relative overflow-hidden rounded-[28px] bg-gradient-to-br from-tertiary-fixed to-tertiary-fixed-dim/60 p-space-lg shadow-[0_12px_36px_-6px_rgba(38,68,93,0.14)] lg:p-space-xl">
          <div class="pointer-events-none absolute -right-24 -top-24 h-96 w-96 rounded-full bg-white/30 blur-3xl"></div>
          <div class="pointer-events-none absolute bottom-0 left-1/3 h-48 w-80 rounded-full bg-secondary-container/15 blur-2xl"></div>
          <div class="relative z-10 grid grid-cols-1 items-center gap-space-lg lg:grid-cols-12">
            <div class="flex flex-col gap-space-md lg:col-span-7">
              <span class="inline-flex w-fit items-center gap-1.5 rounded-full bg-primary/10 px-3 py-1 font-label-caps text-label-caps uppercase tracking-wider text-primary">
                <span class="h-1.5 w-1.5 rounded-full bg-secondary"></span>
                {{ userName() ? 'Hola, ' + userName() : 'Plataforma central' }}
              </span>
              <div class="space-y-1">
                <h1 class="font-display-hero text-display-hero uppercase tracking-tight text-primary">Sistema inteligente de mantenimiento</h1>
                <p class="max-w-xl font-body-lg text-body-lg text-primary-container">
                  Gestión de incidentes y control en tiempo real del parque tecnológico empresarial.
                </p>
              </div>
              <div class="grid grid-cols-1 gap-space-md pt-2 sm:grid-cols-2">
                <div class="flex flex-col gap-3 rounded-[18px] bg-white/65 p-space-md shadow-[0_8px_24px_rgba(38,68,93,0.08)] backdrop-blur-md">
                  <div class="flex items-center justify-between">
                    <span class="font-headline-sm text-headline-sm text-primary">Mantenimientos activos</span>
                    @if (m.urgentTickets > 0) {
                      <span class="inline-flex items-center gap-1 rounded-full bg-secondary-container px-2 py-0.5 font-label-chip text-label-chip text-on-secondary-container">
                        {{ m.urgentTickets }} urgentes
                      </span>
                    }
                  </div>
                  <div class="flex items-baseline gap-2">
                    <span class="font-kpi-number text-kpi-number text-primary">{{ m.activeTickets }}</span>
                    <span class="font-body-sm text-body-sm text-on-surface-variant">en ejecución</span>
                  </div>
                  <div>
                    <div class="mb-1.5 flex justify-between font-label-chip text-label-chip text-on-surface-variant">
                      <span>Resueltos del mes</span><span class="font-bold text-secondary">{{ m.resolutionPct }}%</span>
                    </div>
                    <div class="h-2 w-full overflow-hidden rounded-full bg-surface-container-highest">
                      <div class="h-full rounded-full bg-secondary-container transition-all duration-700" [style.width.%]="m.resolutionPct"></div>
                    </div>
                  </div>
                </div>
                <div class="flex flex-col gap-3 rounded-[18px] bg-white/65 p-space-md shadow-[0_8px_24px_rgba(38,68,93,0.08)] backdrop-blur-md">
                  <span class="font-headline-sm text-headline-sm text-primary">Pendientes de asignación</span>
                  <div class="flex items-baseline gap-2">
                    <span class="font-kpi-number text-kpi-number text-primary">{{ m.pendingTickets }}</span>
                    <span class="font-body-sm text-body-sm text-on-surface-variant">en cola de triaje</span>
                  </div>
                  <div>
                    <div class="mb-1.5 flex justify-between font-label-chip text-label-chip text-on-surface-variant">
                      <span>Técnicos disponibles</span>
                      <span class="font-bold text-primary-container">{{ m.techniciansAvailable }}/{{ m.techniciansTotal }}</span>
                    </div>
                    <div class="h-2 w-full overflow-hidden rounded-full bg-surface-container-highest">
                      <div class="h-full rounded-full bg-primary-container transition-all duration-700"
                        [style.width.%]="m.techniciansTotal ? (m.techniciansAvailable / m.techniciansTotal) * 100 : 0"></div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="relative flex items-center justify-center lg:col-span-5">
              <div class="relative w-full overflow-hidden rounded-2xl bg-white/30 shadow-[0_16px_40px_rgba(38,68,93,0.18)]">
                <img src="assets/images/hero-datacenter.jpg" alt="Centro de datos modular" class="h-[290px] w-full object-cover object-center transition-transform duration-500 hover:scale-[1.02]" />
                <div class="pointer-events-none absolute inset-0 bg-gradient-to-t from-primary/30 via-transparent to-transparent"></div>
              </div>
              <div class="absolute -bottom-3 right-2 flex items-center gap-space-md rounded-[20px] bg-white/90 p-space-md shadow-[0_12px_28px_rgba(38,68,93,0.16)] backdrop-blur-xl sm:right-4">
                <div class="flex items-center gap-2.5 pr-space-sm">
                  <div class="flex h-9 w-9 items-center justify-center rounded-xl bg-tertiary-fixed text-primary">
                    <span class="material-symbols-outlined text-[20px]">dns</span>
                  </div>
                  <div>
                    <span class="font-headline-md text-headline-md text-primary">{{ m.operationalPct }}%</span>
                    <span class="block font-label-caps text-label-caps uppercase tracking-wider text-outline">Equipos operativos</span>
                  </div>
                </div>
                <div class="h-8 w-px bg-outline-variant/60"></div>
                <div class="flex items-center gap-2.5 pl-space-xs">
                  <div class="flex h-9 w-9 items-center justify-center rounded-xl bg-secondary-fixed text-secondary">
                    <span class="material-symbols-outlined text-[20px]">verified</span>
                  </div>
                  <div>
                    <span class="font-headline-md text-headline-md text-primary">{{ m.resolutionPct }}%</span>
                    <span class="block font-label-caps text-label-caps uppercase tracking-wider text-outline">Resolución</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <!-- KPIs -->
        <section class="grid grid-cols-1 gap-space-lg md:grid-cols-3">
          <div [class]="card + ' flex flex-col justify-between gap-space-md'">
            <div class="flex items-center justify-between">
              <span class="font-label-caps text-label-caps uppercase tracking-wider text-outline">Equipos totales</span>
              <div class="flex h-10 w-10 items-center justify-center rounded-full bg-tertiary-fixed/60 text-primary"><span class="material-symbols-outlined text-[22px]">hard_drive</span></div>
            </div>
            <div>
              <span class="font-kpi-number text-kpi-number text-primary">{{ m.equipmentTotal }}</span>
              <p class="mt-1 font-body-sm text-body-sm text-on-surface-variant">Activos registrados en el inventario</p>
            </div>
            <div class="flex items-center justify-between gap-2 rounded-xl bg-surface-container-low px-3 py-2 font-label-chip text-label-chip text-on-surface-variant">
              @for (type of m.byType; track type.name) {
                <span>{{ type.name }}: <strong class="text-primary">{{ type.count }}</strong></span>
              } @empty {
                <span>Sin equipos registrados</span>
              }
            </div>
          </div>

          <div [class]="card + ' flex flex-col justify-between gap-space-md'">
            <div class="flex items-center justify-between">
              <span class="font-label-caps text-label-caps uppercase tracking-wider text-outline">Mantenimientos del mes</span>
              <div class="flex h-10 w-10 items-center justify-center rounded-full bg-secondary-fixed/50 text-secondary"><span class="material-symbols-outlined text-[22px]">build</span></div>
            </div>
            <div>
              <span class="font-kpi-number text-kpi-number text-primary">{{ m.monthTickets }}</span>
              <p class="mt-1 font-body-sm text-body-sm text-on-surface-variant">{{ m.monthDone }} resueltos / {{ m.monthTickets - m.monthDone }} abiertos</p>
            </div>
            <div>
              <div class="flex h-2 w-full overflow-hidden rounded-full bg-surface-container-high">
                <div class="h-full bg-primary" [style.width.%]="m.resolutionPct"></div>
                <div class="h-full bg-secondary-container" [style.width.%]="m.monthTickets ? 100 - m.resolutionPct : 0"></div>
              </div>
              <div class="mt-1.5 font-body-sm text-body-sm text-on-surface-variant">
                Tasa de resolución: <strong class="text-primary">{{ m.resolutionPct }}%</strong>
              </div>
            </div>
          </div>

          <div [class]="card + ' flex flex-col justify-between gap-space-md'">
            <div class="flex items-center justify-between">
              <span class="font-label-caps text-label-caps uppercase tracking-wider text-outline">Técnicos activos</span>
              <div class="flex h-10 w-10 items-center justify-center rounded-full bg-primary-fixed text-primary"><span class="material-symbols-outlined text-[22px]">badge</span></div>
            </div>
            <div>
              <span class="font-kpi-number text-kpi-number text-primary">{{ m.techniciansTotal }}</span>
              <p class="mt-1 font-body-sm text-body-sm text-on-surface-variant">{{ m.techniciansAvailable }} disponibles ahora</p>
            </div>
            <div class="flex items-center gap-2 rounded-xl bg-surface-container-low px-3 py-2">
              <div class="flex -space-x-2">
                @for (tech of m.technicians; track tech.id) {
                  <span class="flex h-6 w-6 items-center justify-center rounded-full bg-primary-container text-[10px] font-bold text-white ring-2 ring-white">T{{ tech.id }}</span>
                }
              </div>
              <a routerLink="/technicians" class="ml-auto font-body-sm text-body-sm text-primary-container hover:underline">Ver equipo</a>
            </div>
          </div>
        </section>

        <!-- Detalle -->
        <section class="grid grid-cols-1 gap-space-lg lg:grid-cols-12">
          <div [class]="card + ' flex flex-col justify-between lg:col-span-5'">
            <div>
              <div class="pb-space-md">
                <h2 class="font-headline-md text-headline-md text-primary">Mantenimientos por semana</h2>
                <p class="font-body-sm text-body-sm text-on-surface-variant">Solicitudes creadas en los últimos 7 días</p>
              </div>
              <div class="relative flex h-48 items-end justify-between gap-2 px-2 pt-6">
                @for (day of m.week; track $index) {
                  <div class="group relative z-10 flex h-full flex-1 flex-col items-center justify-end gap-2">
                    <span class="font-label-chip text-[11px]" [class]="day.isPeak ? 'font-bold text-secondary' : 'text-primary opacity-0 group-hover:opacity-100'">{{ day.count }}</span>
                    <div class="w-full max-w-[28px] rounded-t-lg transition-all group-hover:brightness-110"
                      [class]="day.isPeak ? 'bg-secondary-container shadow-[0_4px_12px_rgba(254,190,70,0.35)]' : 'bg-primary-container'"
                      [style.height.%]="barHeight(day, m.week)"></div>
                    <span class="font-label-chip text-[11px]" [class]="day.isPeak ? 'font-bold text-secondary' : 'text-outline'">{{ day.label }}</span>
                  </div>
                }
              </div>
            </div>
            <div class="mt-4 flex items-center justify-between border-t border-surface-container-highest pt-4">
              <span class="font-label-chip text-label-chip text-on-surface-variant">Pico destacado en mostaza</span>
              <span class="font-label-caps text-label-caps text-outline">TOTAL: {{ m.weekTotal }} SOL.</span>
            </div>
          </div>

          <div [class]="card + ' flex flex-col justify-between lg:col-span-4'">
            <div>
              <div class="pb-space-sm">
                <h2 class="font-headline-md text-headline-md text-primary">Salud de equipos</h2>
                <p class="font-body-sm text-body-sm text-on-surface-variant">Inventario por categoría</p>
              </div>
              <div class="relative my-2 h-[260px] overflow-hidden rounded-2xl bg-gradient-to-br from-tertiary-fixed/40 to-surface-container-high">
                <img src="assets/images/health-island.jpg" alt="Isla tecnológica de infraestructura" class="h-full w-full object-cover transition-transform duration-500 hover:scale-105" />
                <div class="absolute left-3 top-3 flex items-center gap-2 rounded-xl border border-tertiary-fixed-dim bg-white/90 px-3 py-1.5 shadow-md backdrop-blur-md">
                  <span class="material-symbols-outlined text-[16px] text-primary">verified</span>
                  <div>
                    <div class="text-[11px] font-bold leading-tight text-primary">Operativos</div>
                    <span class="font-label-chip text-[10px] text-tertiary">{{ m.operationalPct }}% del parque</span>
                  </div>
                </div>
              </div>
              <div class="grid grid-cols-3 gap-2 pt-2 text-center">
                @for (type of m.byType; track type.name) {
                  <div class="rounded-xl bg-surface-container-low p-2">
                    <span class="block text-[14px] font-bold text-primary">{{ type.count }}</span>
                    <span class="text-[10px] text-outline">{{ type.name }}</span>
                  </div>
                }
              </div>
            </div>
            <a routerLink="/equipos" class="mt-3 flex h-11 items-center justify-center gap-2 rounded-xl bg-surface-container-low font-headline-sm text-headline-sm text-primary transition-all hover:bg-surface-container">
              Ver inventario <span class="material-symbols-outlined text-[18px]">arrow_forward</span>
            </a>
          </div>

          <div [class]="card + ' flex flex-col justify-between lg:col-span-3'">
            <div>
              <div class="flex items-center justify-between pb-space-sm">
                <div>
                  <h2 class="font-headline-md text-headline-md text-primary">Equipo técnico</h2>
                  <p class="font-body-sm text-body-sm text-on-surface-variant">Disponibilidad actual</p>
                </div>
                <span class="material-symbols-outlined text-[22px] text-secondary">military_tech</span>
              </div>
              <div class="space-y-3 pt-3">
                @for (tech of m.technicians; track tech.id) {
                  <div class="flex items-center gap-3 rounded-2xl bg-surface-container-low p-3">
                    <span class="flex h-10 w-10 items-center justify-center rounded-full bg-primary-container text-[13px] font-bold text-white">T{{ tech.id }}</span>
                    <div class="min-w-0 flex-1">
                      <h3 class="truncate font-headline-sm text-headline-sm text-primary">Técnico #{{ tech.id }}</h3>
                      <span class="font-body-sm text-body-sm text-on-surface-variant">{{ tech.specialization || 'General' }}</span>
                    </div>
                    <span class="rounded-full px-2 py-0.5 font-label-chip text-[10px]"
                      [class]="tech.is_available ? 'bg-tertiary-fixed text-tertiary' : 'bg-secondary-fixed text-secondary'">
                      {{ tech.is_available ? 'LIBRE' : 'OCUPADO' }}
                    </span>
                  </div>
                } @empty {
                  <p class="font-body-sm text-body-sm text-on-surface-variant">Aún no hay técnicos registrados.</p>
                }
              </div>
            </div>
            <a routerLink="/technicians" class="mt-3 flex h-11 items-center justify-center gap-2 rounded-xl bg-surface-container-low font-headline-sm text-headline-sm text-primary transition-all hover:bg-surface-container">
              Ver todos los técnicos <span class="material-symbols-outlined text-[18px]">arrow_forward</span>
            </a>
          </div>
        </section>
      </div>
    }
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class DashboardComponent implements OnInit {
  private readonly store = inject(DashboardStore);
  private readonly profileService = inject(LocalProfileService);

  readonly state$ = this.store.state$;
  readonly card = CARD;
  readonly userName = signal('');

  async ngOnInit(): Promise<void> {
    this.store.load();
    this.userName.set((await this.profileService.getProfile()).full_name);
  }

  /** Altura relativa al día con más solicitudes; mínimo visible para los días en cero. */
  barHeight(day: DayBar, week: DayBar[]): number {
    const max = Math.max(...week.map((d) => d.count), 1);
    return Math.max((day.count / max) * 80, 4);
  }
}
