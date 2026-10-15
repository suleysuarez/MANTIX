import { AsyncPipe, DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Subject, debounceTime, distinctUntilChanged } from 'rxjs';

import {
  CalendarDay, addDays, dayKey, dayLabel, groupByDay, monthGrid, rangeTitle, startOfDay, weekDays, WEEKDAYS,
} from '../../core/calendar-utils';
import { Period } from '../../core/dashboard-kpis.service';
import { CalendarEvent } from '../../core/maintenance-overview.service';
import {
  LIST_PAGE_SIZE, MaintenanceHubState, MaintenanceHubStore,
} from '../../core/maintenance-hub.store';
import { LocalProfileService } from '../../core/local-profile.service';
import { saveBlob, reportFilename } from '../../core/download';
import { ToastService } from '../../core/toast.service';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { HubInsightsComponent } from './hub-insights.component';
import { PlanDetailPanelComponent } from './plan-detail-panel.component';
import { PlanFormModalComponent } from './plan-form-modal.component';
import { planStatus, plansToCsv } from './plan-csv';

const PERIODS: { id: Period; label: string }[] = [
  { id: '7d', label: '7 días' },
  { id: '30d', label: '30 días' },
  { id: '12m', label: '12 meses' },
];
const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface ${FOCUS}`;

/** Clases por tipo de evento: todas con contraste de texto AA sobre su fondo. */
const CHIP: Record<string, string> = {
  planned: 'bg-brand-accentLight text-brand-accentDeep',
  overdue: 'bg-error-container text-on-error-container',
  donePunctual: 'bg-primary-fixed text-on-primary-fixed-variant',
  doneLate: 'bg-secondary-fixed text-on-secondary-fixed',
};
const DOT: Record<string, string> = {
  planned: 'bg-brand-accentDeep',
  overdue: 'bg-error',
  donePunctual: 'bg-brand-slate',
  doneLate: 'bg-brand-mustard',
};

/** Mantenimiento preventivo: calendario con línea de tiempo y pulso a la derecha, y vista de lista. */
@Component({
  selector: 'app-maintenance-hub',
  standalone: true,
  imports: [AsyncPipe, DatePipe, HubInsightsComponent, PlanDetailPanelComponent, PlanFormModalComponent, ToastHostComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (vm$ | async; as vm) {
      <div class="space-y-4">
        <!-- Encabezado con ilustración -->
        <header class="relative overflow-hidden rounded-2xl bg-gradient-to-r from-brand-sidebar to-primary-container px-6 py-6 md:px-8">
          <div class="relative z-10 flex flex-col gap-4 md:max-w-[58%]">
            <span class="glass inline-flex w-fit items-center gap-2 rounded-full px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-brand-accentDeep">
              <span class="h-2 w-2 rounded-full bg-brand-mustard"></span> Mantenimiento preventivo
            </span>
            <h1 class="text-[26px] font-extrabold uppercase leading-tight tracking-tight text-white">
              Planifica antes de que <span class="text-brand-accentLight">falle</span>
            </h1>
            <p class="max-w-xl text-[14px] leading-relaxed text-brand-grey">
              Calendario de servicios, línea de tiempo de lo próximo y el pulso de cómo vas con tu plan.
            </p>
            <div class="flex flex-wrap items-center gap-3">
              @if (canManage()) {
                <button type="button" (click)="form.set('create')" class="glass-btn flex items-center gap-1.5 rounded-xl px-5 py-2.5 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white">
                  <span class="material-symbols-outlined text-[20px]" aria-hidden="true">add</span> Programar mantenimiento
                </button>
              }
              <div class="glass flex rounded-full p-0.5" role="group" aria-label="Periodo de las métricas">
                @for (p of periods; track p.id) {
                  <button type="button" (click)="store.setPeriod(p.id)" [attr.aria-pressed]="vm.period === p.id"
                    class="rounded-full px-3 py-1 text-[12px] font-semibold transition-colors active:scale-95"
                    [class]="focus + (vm.period === p.id ? ' bg-brand-sidebar !text-white' : ' bg-transparent !text-brand-accentDeep hover:bg-surface-container')">{{ p.label }}</button>
                }
              </div>
            </div>
          </div>
          <!-- PLACEHOLDER: se reemplaza por assets/images/mantenimiento-hero.svg (ver lista de imágenes) -->
          <div class="pointer-events-none absolute inset-y-3 right-4 hidden w-[34%] items-center justify-center rounded-2xl border-2 border-dashed border-white/40 text-center md:flex" data-placeholder="mantenimiento-hero.svg">
            <span class="px-4 text-[11px] font-semibold uppercase tracking-wider text-brand-grey">[Placeholder] ilustración<br />mantenimiento-hero.svg · 640×360</span>
          </div>
        </header>

        <!-- Barra de vista (cristal) -->
        <div class="glass flex flex-wrap items-center justify-between gap-3 rounded-2xl px-4 py-3" role="toolbar" aria-label="Opciones de vista">
          <div class="flex flex-wrap items-center gap-2">
            <div class="flex rounded-full bg-surface-container p-0.5" role="group" aria-label="Vista">
              @for (v of views; track v.id) {
                <button type="button" (click)="store.setView(v.id)" [attr.aria-pressed]="vm.view === v.id"
                  class="flex items-center gap-1 rounded-full px-3 py-1 text-[12px] font-semibold transition-colors"
                  [class]="focus + (vm.view === v.id ? ' bg-brand-sidebar !text-white' : ' bg-transparent !text-brand-accentDeep hover:bg-surface-container-high')">
                  <span class="material-symbols-outlined text-[16px]" aria-hidden="true">{{ v.icon }}</span>{{ v.label }}
                </button>
              }
            </div>
            @if (vm.view === 'calendar') {
              <div class="flex rounded-full bg-surface-container p-0.5" role="group" aria-label="Escala del calendario">
                @for (m of modes; track m.id) {
                  <button type="button" (click)="store.setMode(m.id)" [attr.aria-pressed]="vm.mode === m.id"
                    class="rounded-full px-3 py-1 text-[12px] font-semibold transition-colors"
                    [class]="focus + (vm.mode === m.id ? ' bg-brand-sidebar !text-white' : ' bg-transparent !text-brand-accentDeep hover:bg-surface-container-high')">{{ m.label }}</button>
                }
              </div>
            }
          </div>
          @if (vm.view === 'calendar') {
            <div class="flex items-center gap-1">
              <button type="button" (click)="store.navigate(-1)" aria-label="Anterior" [class]="navButton"><span class="material-symbols-outlined text-[20px]" aria-hidden="true">chevron_left</span></button>
              <button type="button" (click)="store.goToday()" [class]="navButton + ' px-3 text-[12px] font-bold'">Hoy</button>
              <button type="button" (click)="store.navigate(1)" aria-label="Siguiente" [class]="navButton"><span class="material-symbols-outlined text-[20px]" aria-hidden="true">chevron_right</span></button>
              <h2 class="ml-2 min-w-[9rem] text-[15px] font-bold capitalize text-on-surface" aria-live="polite">{{ title(vm) }}</h2>
            </div>
          } @else {
            <button type="button" (click)="exportCsv()" [disabled]="vm.listTotal === 0" [class]="navButton + ' gap-1.5 px-3 text-[12px] font-bold'">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">file_download</span> Exportar CSV
            </button>
          }
        </div>

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <!-- Principal -->
          <div class="min-w-0 space-y-3">
            @if (vm.view === 'calendar') {
              @if (vm.calendarError) {
                <p role="alert" class="flex flex-wrap items-center gap-3 rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">
                  {{ vm.calendarError }}
                  <button type="button" (click)="store.goToday()" class="bg-transparent p-0 font-bold underline !text-on-error-container">Reintentar</button>
                </p>
              }
              <div class="flex flex-wrap items-center gap-x-4 gap-y-1 px-1 text-[12px] text-on-surface-variant" aria-label="Leyenda">
                <span class="flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full" [class]="dot['planned']"></span>Programado</span>
                <span class="flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full" [class]="dot['overdue']"></span>Vencido</span>
                <span class="flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full" [class]="dot['donePunctual']"></span>Hecho a tiempo</span>
                <span class="flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full" [class]="dot['doneLate']"></span>Hecho con retraso</span>
              </div>

              <section class="overflow-hidden rounded-2xl border border-brand-grey bg-surface-container-lowest" [attr.aria-busy]="vm.calendarLoading" aria-label="Calendario de servicios">
                <div class="grid grid-cols-7 border-b border-brand-grey bg-surface-container-low text-center text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">
                  @for (d of weekdays; track d) { <div class="py-2">{{ d }}</div> }
                </div>
                @let byDay = eventsByDay(vm);
                <div class="grid grid-cols-7" [class.opacity-60]="vm.calendarLoading">
                  @for (day of days(vm); track day.key) {
                    @let items = byDay.get(day.key) ?? [];
                    <button type="button" (click)="store.selectDay(day.key)" [attr.aria-pressed]="vm.selectedDay === day.key"
                      [attr.aria-label]="dayLabel(day.date) + ': ' + items.length + ' servicios'"
                      [class]="focus + ' flex flex-col gap-1 border-b border-r border-brand-grey/60 bg-transparent p-1 text-left transition-colors hover:bg-surface-container-low ' + (vm.mode === 'month' ? 'min-h-[4.5rem] sm:min-h-[6.5rem] ' : 'min-h-[14rem] ') + (day.inMonth ? '' : 'opacity-50 ') + (vm.selectedDay === day.key ? 'bg-brand-accentLight/40 ' : '')">
                      <span class="flex h-6 w-6 items-center justify-center self-end rounded-full text-[12px] font-semibold sm:self-start"
                        [class]="day.today ? 'bg-brand-sidebar text-white' : 'text-on-surface'">{{ day.date.getDate() }}</span>
                      <span class="hidden flex-col gap-0.5 sm:flex">
                        @for (e of items.slice(0, vm.mode === 'month' ? 3 : 20); track $index) {
                          <span class="truncate rounded px-1.5 py-0.5 text-[11px] font-semibold" [class]="chip(e)">{{ e.asset_tag }} · {{ e.title }}</span>
                        }
                        @if (vm.mode === 'month' && items.length > 3) {
                          <span class="px-1 text-[11px] font-semibold text-on-surface-variant">+{{ items.length - 3 }} más</span>
                        }
                      </span>
                      <span class="flex flex-wrap justify-end gap-0.5 sm:hidden">
                        @for (e of items.slice(0, 4); track $index) { <span class="h-2 w-2 rounded-full" [class]="dotFor(e)"></span> }
                      </span>
                    </button>
                  }
                </div>
              </section>
              @if (vm.truncated) {
                <p class="px-1 text-[12px] text-on-surface-variant">Hay más servicios de los que se pueden mostrar; acota la vista a una semana.</p>
              }

              @if (vm.selectedDay; as key) {
                <section class="glass rounded-2xl p-4" aria-label="Servicios del día seleccionado">
                  <h3 class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">{{ selectedTitle(key) }}</h3>
                  <ul class="mt-2 space-y-2">
                    @for (e of byDay.get(key) ?? []; track $index) {
                      <li>
                        <button type="button" (click)="store.selectPlan(e.schedule_id)" [class]="focus + ' flex w-full items-center gap-3 rounded-xl bg-surface-container-low p-2.5 text-left hover:bg-surface-container'">
                          <span class="h-2.5 w-2.5 shrink-0 rounded-full" [class]="dotFor(e)"></span>
                          <span class="min-w-0 flex-1">
                            <span class="block truncate text-[13px] font-semibold text-on-surface">{{ e.title }}</span>
                            <span class="block truncate text-[12px] text-on-surface-variant">{{ e.asset_tag }} · {{ e.technician ?? 'Sin técnico' }}</span>
                          </span>
                          <span class="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="chip(e)">{{ kindLabel(e) }}</span>
                        </button>
                      </li>
                    } @empty {
                      <li class="text-[13px] text-on-surface-variant">No hay servicios este día.</li>
                    }
                  </ul>
                </section>
              }
            } @else {
              <!-- Vista de lista -->
              <form class="glass grid grid-cols-1 gap-3 rounded-2xl p-3 sm:grid-cols-[minmax(0,1fr)_12rem_10rem_auto]" role="search" aria-label="Filtros de los planes" (submit)="$event.preventDefault()">
                <div>
                  <label for="pl-search" class="sr-only">Buscar plan</label>
                  <input id="pl-search" type="search" [class]="field" placeholder="Buscar por título" maxlength="100" [value]="vm.filters.search" (input)="search$.next($any($event.target).value)" />
                </div>
                <div>
                  <label for="pl-tech" class="sr-only">Técnico</label>
                  <select id="pl-tech" [class]="field" (change)="store.setFilters({ technicianId: toNumber($any($event.target).value) })">
                    <option value="" [selected]="vm.filters.technicianId === null">Todos los técnicos</option>
                    @for (t of vm.technicians; track t.id) { <option [value]="t.id" [selected]="vm.filters.technicianId === t.id">{{ t.full_name }}</option> }
                  </select>
                </div>
                <div>
                  <label for="pl-status" class="sr-only">Estado</label>
                  <select id="pl-status" [class]="field" (change)="store.setFilters({ status: $any($event.target).value })">
                    <option value="" [selected]="vm.filters.status === ''">Todos</option>
                    <option value="overdue" [selected]="vm.filters.status === 'overdue'">Vencidos</option>
                    <option value="active" [selected]="vm.filters.status === 'active'">Activos</option>
                    <option value="inactive" [selected]="vm.filters.status === 'inactive'">Inactivos</option>
                  </select>
                </div>
                @if (hasFilters(vm)) {
                  <button type="button" (click)="store.clearFilters()" [class]="focus + ' rounded-lg bg-transparent px-3 py-2 text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container'">Limpiar</button>
                }
              </form>

              @if (vm.listError) {
                <p role="alert" class="rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">{{ vm.listError }}</p>
              }

              <section class="overflow-hidden rounded-2xl border border-brand-grey bg-surface-container-lowest" [attr.aria-busy]="vm.listLoading">
                @if (vm.list.length > 0) {
                  <div class="overflow-x-auto">
                    <table class="w-full min-w-[640px] border-collapse text-left text-[12px]">
                      <caption class="sr-only">Planes de mantenimiento preventivo</caption>
                      <thead>
                        <tr class="border-b border-brand-grey bg-surface-container-low text-[11px] uppercase tracking-wider text-on-surface-variant">
                          <th scope="col" class="px-3 py-2" [attr.aria-sort]="ariaSort(vm, 'title')">
                            <button type="button" (click)="sortBy(vm, 'title')" [class]="sortButton">Plan {{ arrow(vm, 'title') }}</button>
                          </th>
                          <th scope="col" class="px-3 py-2 font-bold">Técnico</th>
                          <th scope="col" class="px-3 py-2 text-right font-bold">Cada</th>
                          <th scope="col" class="px-3 py-2" [attr.aria-sort]="ariaSort(vm, 'next_due_at')">
                            <button type="button" (click)="sortBy(vm, 'next_due_at')" [class]="sortButton">Próximo servicio {{ arrow(vm, 'next_due_at') }}</button>
                          </th>
                          <th scope="col" class="px-3 py-2 text-right font-bold">Estimado</th>
                          <th scope="col" class="px-3 py-2 font-bold">Estado</th>
                        </tr>
                      </thead>
                      <tbody [class.opacity-60]="vm.listLoading">
                        @for (p of vm.list; track p.id) {
                          <tr class="cursor-pointer border-b border-brand-grey/60 transition-colors hover:bg-surface-container-low" (click)="store.selectPlan(p.id)">
                            <th scope="row" class="px-3 py-2 font-normal">
                              <button type="button" (click)="store.selectPlan(p.id); $event.stopPropagation()" [class]="focus + ' bg-transparent p-0 text-left'">
                                <span class="block font-semibold text-on-surface">{{ p.title }}</span>
                                <span class="block text-[11px] text-on-surface-variant">{{ p.equipment.asset_tag }} · {{ p.equipment.brand }} {{ p.equipment.model }}</span>
                              </button>
                            </th>
                            <td class="px-3 py-2 text-on-surface">{{ p.technician?.full_name ?? '—' }}</td>
                            <td class="px-3 py-2 text-right text-on-surface">{{ p.interval_days }} d</td>
                            <td class="px-3 py-2 text-on-surface">{{ p.next_due_at | date: 'dd/MM/yyyy HH:mm' }}</td>
                            <td class="px-3 py-2 text-right text-on-surface">{{ p.estimated_hours ? p.estimated_hours + ' h' : '—' }}</td>
                            <td class="px-3 py-2">
                              <span class="rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="statusChip(statusOf(p))">{{ statusOf(p) }}</span>
                            </td>
                          </tr>
                        }
                      </tbody>
                    </table>
                  </div>
                  <nav class="flex flex-wrap items-center justify-between gap-2 border-t border-brand-grey px-3 py-2 text-[12px] text-on-surface-variant" aria-label="Paginación">
                    <span>{{ rangeText(vm) }}</span>
                    <span class="flex items-center gap-1">
                      <button type="button" (click)="store.setListPage(vm.listPage - 1)" [disabled]="vm.listPage <= 1 || vm.listLoading" [class]="navButton + ' px-3 text-[12px] font-bold'">Anterior</button>
                      <span class="px-2 font-semibold text-on-surface">{{ vm.listPage }} / {{ pages(vm) }}</span>
                      <button type="button" (click)="store.setListPage(vm.listPage + 1)" [disabled]="vm.listPage >= pages(vm) || vm.listLoading" [class]="navButton + ' px-3 text-[12px] font-bold'">Siguiente</button>
                    </span>
                  </nav>
                } @else if (vm.listLoading) {
                  <div class="space-y-2 p-4" role="status" aria-label="Cargando planes">
                    @for (n of skeleton; track n) { <div class="h-10 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div> }
                  </div>
                } @else {
                  <div class="flex flex-col items-center gap-2 px-6 py-12 text-center">
                    <img src="assets/images/cola-vacia.svg" alt="" width="224" height="195" class="h-auto w-44 mix-blend-multiply" />
                    <h3 class="text-[15px] font-bold text-on-surface">{{ hasFilters(vm) ? 'Ningún plan coincide con los filtros' : 'Todavía no hay mantenimientos programados' }}</h3>
                    <p class="max-w-sm text-[13px] text-on-surface-variant">{{ hasFilters(vm) ? 'Prueba con otra búsqueda o limpia los filtros.' : 'Programa el primero para empezar a recibir recordatorios.' }}</p>
                    @if (!hasFilters(vm) && canManage()) {
                      <button type="button" (click)="form.set('create')" class="glass-btn mt-1 rounded-xl px-5 py-2 text-[13px] font-bold">Programar mantenimiento</button>
                    }
                  </div>
                }
              </section>
            }
          </div>

          <!-- Riel derecho -->
          <div class="space-y-4">
            <section class="glass rounded-2xl p-4" aria-label="Próximos 30 días">
              <h2 class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Próximos 30 días</h2>
              @if (vm.timeline === null) {
                <p class="mt-2 text-[12px] text-on-surface-variant">La línea de tiempo no está disponible.</p>
              } @else if (vm.timeline.length === 0) {
                <div class="mt-2 flex flex-col items-center gap-1 py-3 text-center">
                  <img src="assets/images/columna-vacia.svg" alt="" width="144" height="79" class="h-auto w-32 mix-blend-multiply" />
                  <p class="text-[12px] text-on-surface-variant">Nada programado en los próximos 30 días.</p>
                </div>
              } @else {
                <ol class="mt-3 max-h-[26rem] space-y-3 overflow-y-auto border-l-2 border-brand-accentSky pl-3">
                  @for (group of timeline(vm); track group.key) {
                    <li>
                      <p class="text-[11px] font-bold uppercase tracking-wider" [class]="group.overdue ? 'text-error' : 'text-on-surface-variant'">{{ group.label }}</p>
                      @for (e of group.events; track $index) {
                        <button type="button" (click)="store.selectPlan(e.schedule_id)"
                          [class]="focus + ' mt-1 flex w-full items-center gap-2 rounded-lg bg-transparent p-1.5 text-left hover:bg-surface-container'">
                          <span class="h-2 w-2 shrink-0 rounded-full" [class]="dotFor(e)"></span>
                          <span class="min-w-0">
                            <span class="block truncate text-[12px] font-semibold text-on-surface">{{ e.title }}</span>
                            <span class="block truncate text-[11px] text-on-surface-variant">{{ e.asset_tag }} · {{ e.technician ?? 'Sin técnico' }}</span>
                          </span>
                        </button>
                      }
                    </li>
                  }
                </ol>
              }
            </section>
            <app-hub-insights [overview]="vm.overview" [loading]="vm.overviewLoading" />
          </div>
        </div>
      </div>

      <!-- Acción flotante (móvil) -->
      @if (canManage()) {
        <button type="button" (click)="form.set('create')" aria-label="Programar mantenimiento"
          class="glass-btn fixed bottom-4 right-4 z-30 flex h-14 w-14 items-center justify-center rounded-full shadow-lg lg:hidden focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
          <span class="material-symbols-outlined text-[28px]" aria-hidden="true">add</span>
        </button>
      }

      @if (vm.selectedId !== null) {
        <div class="fixed inset-0 z-40 bg-brand-navy/40" (click)="store.selectPlan(null)" aria-hidden="true"></div>
        <div class="fixed inset-y-0 right-0 z-50 w-full max-w-md p-3">
          <app-plan-detail-panel [plan]="vm.plan" [history]="vm.history" [loading]="vm.detailLoading" [error]="vm.detailError"
            [busy]="vm.busy" [canManage]="canManage()" (closed)="store.selectPlan(null)" (edit)="form.set('edit')" />
        </div>
      }

      @if (form() === 'create') {
        <app-plan-form-modal [equipment]="vm.equipment" [technicians]="vm.technicians" [busy]="vm.busy" (closed)="form.set(null)" />
      } @else if (form() === 'edit' && vm.plan) {
        <app-plan-form-modal [plan]="vm.plan" [equipment]="vm.equipment" [technicians]="vm.technicians" [busy]="vm.busy" (closed)="form.set(null)" />
      }
      <app-toast-host />
    }
  `,
})
export class MaintenanceHubComponent implements OnInit {
  readonly store = inject(MaintenanceHubStore);
  private readonly profile = inject(LocalProfileService);
  private readonly toasts = inject(ToastService);
  private readonly destroyRef = inject(DestroyRef);

  readonly vm$ = this.store.state$;
  readonly periods = PERIODS;
  readonly views = [
    { id: 'calendar' as const, label: 'Calendario', icon: 'calendar_month' },
    { id: 'list' as const, label: 'Lista', icon: 'view_list' },
  ];
  readonly modes = [
    { id: 'month' as const, label: 'Mes' },
    { id: 'week' as const, label: 'Semana' },
  ];
  readonly weekdays = WEEKDAYS;
  readonly skeleton = [1, 2, 3, 4];
  readonly focus = FOCUS;
  readonly field = FIELD;
  readonly dot = DOT;
  readonly dayLabel = dayLabel;
  readonly search$ = new Subject<string>();
  readonly canManage = signal(false);
  readonly form = signal<'create' | 'edit' | null>(null);
  readonly navButton = `${FOCUS} flex h-8 min-w-8 items-center justify-center rounded-full bg-transparent !text-brand-accentDeep transition-colors hover:bg-surface-container-high disabled:opacity-40`;
  readonly sortButton = `${FOCUS} bg-transparent p-0 text-[11px] font-bold uppercase tracking-wider !text-on-surface-variant hover:!text-on-surface`;

  private lastEvents: CalendarEvent[] | null = null;
  private lastMap = new Map<string, CalendarEvent[]>();

  async ngOnInit(): Promise<void> {
    this.search$
      .pipe(debounceTime(300), distinctUntilChanged(), takeUntilDestroyed(this.destroyRef))
      .subscribe((search) => this.store.setFilters({ search }));
    this.store.load();
    this.canManage.set(await this.profile.can('schedules.manage'));
  }

  title(vm: MaintenanceHubState): string {
    return rangeTitle(vm.anchor, vm.mode);
  }

  days(vm: MaintenanceHubState): CalendarDay[] {
    return vm.mode === 'month' ? monthGrid(vm.anchor) : weekDays(vm.anchor);
  }

  /** Eventos por día local; se recalcula solo cuando llega otra lista. */
  eventsByDay(vm: MaintenanceHubState): Map<string, CalendarEvent[]> {
    if (vm.events !== this.lastEvents) {
      this.lastEvents = vm.events;
      this.lastMap = groupByDay(vm.events);
    }
    return this.lastMap;
  }

  chipKey(e: CalendarEvent): string {
    return e.kind === 'done' ? (e.on_time ? 'donePunctual' : 'doneLate') : e.kind;
  }

  chip(e: CalendarEvent): string {
    return CHIP[this.chipKey(e)];
  }

  dotFor(e: CalendarEvent): string {
    return DOT[this.chipKey(e)];
  }

  kindLabel(e: CalendarEvent): string {
    return e.kind === 'overdue' ? 'Vencido' : e.kind === 'planned' ? 'Programado' : e.on_time ? 'A tiempo' : 'Con retraso';
  }

  selectedTitle(key: string): string {
    const [year, month, day] = key.split('-').map(Number);
    return dayLabel(new Date(year, month - 1, day));
  }

  /** Línea de tiempo: vencidos primero, luego por día con «Hoy» y «Mañana». */
  timeline(vm: MaintenanceHubState): { key: string; label: string; overdue: boolean; events: CalendarEvent[] }[] {
    const today = startOfDay(new Date());
    const groups = new Map<string, { key: string; label: string; overdue: boolean; events: CalendarEvent[] }>();
    for (const event of vm.timeline ?? []) {
      const day = startOfDay(new Date(event.at));
      const overdue = event.kind === 'overdue';
      const key = overdue ? 'overdue' : dayKey(day);
      const label = overdue
        ? 'Vencidos'
        : dayKey(day) === dayKey(today)
          ? 'Hoy'
          : dayKey(day) === dayKey(addDays(today, 1))
            ? 'Mañana'
            : dayLabel(day);
      const group = groups.get(key) ?? { key, label, overdue, events: [] };
      group.events.push(event);
      groups.set(key, group);
    }
    return [...groups.values()].sort((a, b) => (a.overdue ? -1 : b.overdue ? 1 : a.key.localeCompare(b.key)));
  }

  // -- lista --------------------------------------------------------------------------------
  statusOf = planStatus;

  statusChip(status: string): string {
    return status === 'Vencido'
      ? 'bg-error-container text-on-error-container'
      : status === 'Inactivo'
        ? 'bg-surface-container text-on-surface-variant'
        : 'bg-brand-accentLight/60 text-brand-accentDeep';
  }

  hasFilters(vm: MaintenanceHubState): boolean {
    const f = vm.filters;
    return !!(f.search.trim() || f.technicianId !== null || f.status);
  }

  toNumber(value: string): number | null {
    return value ? Number(value) : null;
  }

  pages(vm: MaintenanceHubState): number {
    return Math.max(Math.ceil(vm.listTotal / LIST_PAGE_SIZE), 1);
  }

  rangeText(vm: MaintenanceHubState): string {
    const from = (vm.listPage - 1) * LIST_PAGE_SIZE + 1;
    return `${from}–${from + vm.list.length - 1} de ${vm.listTotal}`;
  }

  sortBy(vm: MaintenanceHubState, field: string): void {
    const current = vm.filters.sort;
    this.store.setFilters({ sort: current === field ? `-${field}` : field });
  }

  arrow(vm: MaintenanceHubState, field: string): string {
    return vm.filters.sort === field ? '▲' : vm.filters.sort === `-${field}` ? '▼' : '';
  }

  ariaSort(vm: MaintenanceHubState, field: string): 'ascending' | 'descending' | 'none' {
    return vm.filters.sort === field ? 'ascending' : vm.filters.sort === `-${field}` ? 'descending' : 'none';
  }

  exportCsv(): void {
    this.store.exportAll().subscribe({
      next: (plans) => saveBlob(new Blob(['﻿' + plansToCsv(plans)], { type: 'text/csv;charset=utf-8' }), reportFilename('mantenimientos', 'csv')),
      error: () => this.toasts.error('No se pudo exportar la lista. Inténtalo de nuevo.'),
    });
  }
}
