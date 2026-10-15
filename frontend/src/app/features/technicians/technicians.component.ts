import { AsyncPipe, CurrencyPipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  HostListener,
  OnInit,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed, toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router } from '@angular/router';
import { BehaviorSubject, combineLatest, map } from 'rxjs';

import { initials } from '../../core/equipment-status';
import { CustodianCandidate } from '../../core/equipment.service';
import { LocalProfileService } from '../../core/local-profile.service';
import { Technician } from '../../core/technicians.service';
import { TechniciansState, TechniciansStore } from '../../core/technicians.store';
import { CustodianPickerComponent } from '../equipos/custodian-picker.component';
import { TechnicianDrawerComponent, TechnicianEdit } from './technician-drawer.component';
import {
  ACTIVE_OPTIONS,
  AVAILABILITY_OPTIONS,
  EMPTY_TECHNICIAN_FILTERS,
  LOAD_OPTIONS,
  MAX_SPECIALIZATION,
  ORDER_OPTIONS,
  PAGE_SIZE,
  STATUS_STYLES,
  TechnicianFilters,
  TechnicianStatus,
  TechnicianSummary,
  allSpecialties,
  filterTechnicians,
  hasTechnicianFilters,
  isActiveAccount,
  specialties,
  summarize,
  technicianStatus,
  validateTechnicianInput,
} from './technician-ui';
import { PaginationComponent } from '../../shared/pagination.component';
import { ExportDrawerComponent } from '../export/export-drawer.component';
import { ExportFilterValues } from '../export/export-model';

const FIELD =
  'w-full rounded-lg border border-[#CED4DA] bg-[#F7FAFC] px-3 text-[13px] text-[#1E293B] placeholder:text-[#94A3B8] focus:border-[#457b9d] focus:outline-none';

/** Estado de la pantalla ya preparado para la plantilla (filtros, página y contadores aplicados). */
interface TechniciansView extends TechniciansState {
  filters: TechnicianFilters;
  filtered: Technician[];
  pageItems: Technician[];
  page: number;
  pages: number;
  summary: TechnicianSummary;
  specialties: string[];
  hasFilters: boolean;
}

/** Smart component: personal técnico en tarjetas o tabla, filtros, alta y ficha de detalle. */
@Component({
  selector: 'app-technicians',
  standalone: true,
  imports: [AsyncPipe, CurrencyPipe, CustodianPickerComponent, TechnicianDrawerComponent, PaginationComponent, ExportDrawerComponent],
  template: `
    @if (vm$ | async; as vm) {
      <div class="space-y-5">
        <header class="flex flex-col justify-between gap-5 rounded-2xl bg-gradient-to-r from-[#0b1f3a] to-[#14365f] px-6 py-6 md:flex-row md:items-center md:px-8">
          <div class="flex items-center gap-5">
            <span class="hidden h-16 w-16 shrink-0 items-center justify-center self-center rounded-2xl border border-white/30 bg-white/10 text-[#ADD7F6] sm:flex">
              <span class="material-symbols-outlined block text-center !text-[34px] !leading-none">engineering</span>
            </span>
            <div>
              <h1 class="text-[26px] font-extrabold uppercase tracking-tight text-white">Personal <span class="text-[#4DB8F0]">técnico</span> y especialistas</h1>
              <p class="mt-1 max-w-2xl text-[14px] leading-relaxed text-[#CBD5E1]">
                Supervisa al equipo técnico: disponibilidad, especialidades y carga de tickets.
              </p>
            </div>
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <button type="button" (click)="exportOpen.set(true)" [disabled]="vm.technicians.length === 0" title="Exporta los técnicos a PDF o Excel"
              class="flex items-center gap-1.5 rounded-lg border border-white/50 bg-white/25 shadow-[inset_0_1px_0_rgba(255,255,255,0.35)] backdrop-blur-md px-5 py-2.5 text-[13px] font-medium !text-white transition-colors hover:bg-white/35 disabled:cursor-not-allowed disabled:opacity-60">
              <span class="material-symbols-outlined text-[18px]">download</span> Exportar
            </button>
            @if (canManage()) {
              <button type="button" (click)="openCreate()"
                class="flex items-center gap-1.5 rounded-lg border border-white/50 bg-white/25 shadow-[inset_0_1px_0_rgba(255,255,255,0.35)] backdrop-blur-md px-5 py-2.5 text-[13px] font-bold !text-[#FFB703] transition-colors hover:bg-white/35">
                <span class="material-symbols-outlined text-[20px]">person_add</span> Registrar técnico
              </button>
            }
          </div>
        </header>

        @if (vm.error) {
          <p class="rounded-lg bg-[#FEE2E2] px-4 py-3 text-[13px] text-[#991B1B]" role="alert">{{ vm.error }}</p>
        }
        @if (vm.notice && !createOpen() && !selectedId()) {
          <p class="flex items-center justify-between gap-2 rounded-lg bg-[#D1FAE5] px-4 py-3 text-[13px] font-medium text-[#065F46]" role="status">
            <span class="flex items-center gap-2"><span class="material-symbols-outlined text-[18px]">check_circle</span>{{ vm.notice }}</span>
            <button type="button" (click)="dismissNotice()" aria-label="Cerrar aviso" class="flex !text-[#065F46] hover:opacity-70">
              <span class="material-symbols-outlined text-[18px]">close</span>
            </button>
          </p>
        }

        <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
          <button type="button" (click)="setFilter({ status: '' })" class="flex items-center justify-between rounded-xl border bg-white p-3 text-left transition-all hover:border-[#457b9d]"
            [class]="!vm.filters.status ? 'border-[#457b9d] ring-1 ring-[#457b9d]/30' : 'border-[#E2E8F0]'">
            <span>
              <span class="block text-[11px] font-semibold uppercase tracking-wider text-[#64748B]">Total técnicos</span>
              <span class="block text-[26px] font-extrabold leading-tight text-[#0b1f3a]">{{ vm.summary.total }}</span>
              <span class="block text-[11px] text-[#64748B]">Perfiles registrados</span>
            </span>
            <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[#EEF4FA] text-[#457b9d]"><span class="material-symbols-outlined text-[18px]">engineering</span></span>
          </button>
          <button type="button" (click)="setFilter({ status: 'free' })" class="flex items-center justify-between rounded-xl border bg-white p-3 text-left transition-all hover:border-[#457b9d]"
            [class]="vm.filters.status === 'free' ? 'border-[#457b9d] ring-1 ring-[#457b9d]/30' : 'border-[#E2E8F0]'">
            <span>
              <span class="block text-[11px] font-semibold uppercase tracking-wider text-[#64748B]">Disponibles</span>
              <span class="block text-[26px] font-extrabold leading-tight text-[#0b1f3a]">{{ vm.summary.available - vm.summary.busy }}</span>
              <span class="block text-[11px] text-[#64748B]">Sin tickets abiertos</span>
            </span>
            <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[#D1FAE5] text-[#065F46]"><span class="material-symbols-outlined text-[18px]">check_circle</span></span>
          </button>
          <button type="button" (click)="setFilter({ status: 'busy' })" class="flex items-center justify-between rounded-xl border bg-white p-3 text-left transition-all hover:border-[#457b9d]"
            [class]="vm.filters.status === 'busy' ? 'border-[#457b9d] ring-1 ring-[#457b9d]/30' : 'border-[#E2E8F0]'">
            <span>
              <span class="block text-[11px] font-semibold uppercase tracking-wider text-[#64748B]">Con tickets activos</span>
              <span class="block text-[26px] font-extrabold leading-tight text-[#0b1f3a]">{{ vm.summary.busy }}</span>
              <span class="block text-[11px] text-[#64748B]">{{ vm.hasWorkload ? vm.summary.openTickets + ' tickets abiertos' : 'Carga no disponible' }}</span>
            </span>
            <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[#FEF3C7] text-[#92400E]"><span class="material-symbols-outlined text-[18px]">construction</span></span>
          </button>
          <button type="button" (click)="setFilter({ status: 'unavailable' })" class="flex items-center justify-between rounded-xl border bg-white p-3 text-left transition-all hover:border-[#457b9d]"
            [class]="vm.filters.status === 'unavailable' ? 'border-[#457b9d] ring-1 ring-[#457b9d]/30' : 'border-[#E2E8F0]'">
            <span>
              <span class="block text-[11px] font-semibold uppercase tracking-wider text-[#64748B]">No disponibles</span>
              <span class="block text-[26px] font-extrabold leading-tight text-[#0b1f3a]">{{ vm.summary.unavailable }}</span>
              <span class="block text-[11px] text-[#64748B]">Fuera de asignación</span>
            </span>
            <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[#E2E8F0] text-[#475569]"><span class="material-symbols-outlined text-[18px]">do_not_disturb_on</span></span>
          </button>
          <div class="flex items-center justify-between rounded-xl border border-[#E2E8F0] bg-white p-3">
            <span>
              <span class="block text-[11px] font-semibold uppercase tracking-wider text-[#64748B]">Resueltos</span>
              <span class="block text-[26px] font-extrabold leading-tight text-[#0b1f3a]">{{ vm.hasWorkload ? vm.summary.resolved : '—' }}</span>
              <span class="block text-[11px] text-[#64748B]">Últimos {{ vm.windowDays }} días</span>
            </span>
            <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[#DBEAFE] text-[#1E40AF]"><span class="material-symbols-outlined text-[18px]">task_alt</span></span>
          </div>
        </div>

        <section class="space-y-3 rounded-xl border border-[#E2E8F0] bg-white p-4">
          <div class="grid grid-cols-1 items-center gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_repeat(4,minmax(0,1fr))_auto]">
            <div class="relative">
              <span class="material-symbols-outlined pointer-events-none absolute left-3 top-2.5 text-[20px] text-[#94A3B8]">search</span>
              <input type="search" [value]="vm.filters.search" (input)="setFilter({ search: $any($event.target).value })" aria-label="Buscar técnicos"
                placeholder="Buscar por nombre, especialidad, código o correo…" class="h-10 pl-10" [class]="field" maxlength="100" />
            </div>
            <select (change)="setFilter({ active: $any($event.target).value })" aria-label="Estado de la cuenta" class="h-10" [class]="field">
              <option value="" [selected]="!vm.filters.active">Estado: Todos</option>
              @for (option of activeOptions; track option.value) {
                <option [value]="option.value" [selected]="option.value === vm.filters.active">{{ option.label }}</option>
              }
            </select>
            <select (change)="setFilter({ specialty: $any($event.target).value })" aria-label="Especialidad" class="h-10" [class]="field">
              <option value="" [selected]="!vm.filters.specialty">Especialidad: Todas</option>
              @for (option of vm.specialties; track option) {
                <option [value]="option" [selected]="option === vm.filters.specialty">{{ option }}</option>
              }
            </select>
            <select (change)="setFilter({ availability: $any($event.target).value })" aria-label="Disponibilidad" class="h-10" [class]="field">
              <option value="" [selected]="!vm.filters.availability">Disponibilidad: Todas</option>
              @for (option of availabilityOptions; track option.value) {
                <option [value]="option.value" [selected]="option.value === vm.filters.availability">{{ option.label }}</option>
              }
            </select>
            <select (change)="setFilter({ load: $any($event.target).value })" aria-label="Carga de tickets" class="h-10" [class]="field">
              <option value="" [selected]="!vm.filters.load">Carga: Todas</option>
              @for (option of loadOptions; track option.value) {
                <option [value]="option.value" [selected]="option.value === vm.filters.load">{{ option.label }}</option>
              }
            </select>
            <button type="button" (click)="clearFilters()" [disabled]="!vm.hasFilters" title="Limpiar todos los filtros" aria-label="Limpiar filtros"
              class="flex h-10 w-10 items-center justify-center justify-self-end rounded-lg border border-[#CED4DA] bg-[#F7FAFC] !text-[#64748B] transition-colors hover:bg-[#E9EEF5] disabled:opacity-40 sm:col-span-2 lg:col-span-1">
              <span class="material-symbols-outlined text-[18px]">filter_alt_off</span>
            </button>
          </div>
          <div class="flex items-center justify-between border-t border-[#E9EEF5] pt-2 text-[12px] text-[#64748B]" role="status">
            <span class="flex items-center gap-2">
              <span class="h-2 w-2 rounded-full bg-[#457b9d]"></span>
              @if (vm.hasFilters) {
                <span><strong class="text-[#1E293B]">{{ vm.filtered.length }}</strong> de {{ vm.technicians.length }} {{ vm.technicians.length === 1 ? 'técnico coincide' : 'técnicos coinciden' }} con los filtros aplicados</span>
              } @else {
                <span><strong class="text-[#1E293B]">{{ vm.technicians.length }}</strong> {{ vm.technicians.length === 1 ? 'técnico registrado' : 'técnicos registrados' }}</span>
              }
            </span>
            <label class="flex items-center gap-2">
              <span class="font-semibold uppercase text-[#94A3B8]">Ordenar por:</span>
              <select (change)="setFilter({ order: $any($event.target).value })" aria-label="Orden"
                class="cursor-pointer border-none bg-transparent py-0 text-[12px] font-semibold text-[#1E293B] focus:outline-none">
                @for (option of orders; track option.value) {
                  <option [value]="option.value" [selected]="option.value === vm.filters.order">{{ option.label }}</option>
                }
              </select>
            </label>
          </div>
        </section>

        <div class="flex justify-end">
          <div class="flex items-center rounded-xl border border-[#CED4DA] bg-[#EEF4FA] p-1" role="group" aria-label="Vista">
            <button type="button" (click)="view.set('cards')" [attr.aria-pressed]="view() === 'cards'"
              class="flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[13px] transition-all"
              [class]="view() === 'cards' ? 'bg-white font-bold !text-[#0b1f3a] shadow-sm' : 'font-medium !text-[#64748B] hover:!text-[#0b1f3a]'">
              <span class="material-symbols-outlined text-[18px]">grid_view</span> Tarjetas
            </button>
            <button type="button" (click)="view.set('table')" [attr.aria-pressed]="view() === 'table'"
              class="flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[13px] transition-all"
              [class]="view() === 'table' ? 'bg-white font-bold !text-[#0b1f3a] shadow-sm' : 'font-medium !text-[#64748B] hover:!text-[#0b1f3a]'">
              <span class="material-symbols-outlined text-[18px]">table_rows</span> Tabla
            </button>
          </div>
        </div>

        @if (vm.loading) {
          <p class="rounded-xl border border-[#E2E8F0] bg-white p-6 text-center text-[14px] text-[#64748B]">Cargando técnicos…</p>
        } @else if (vm.filtered.length === 0) {
          <div class="rounded-xl border border-[#E2E8F0] bg-white p-8 text-center text-[14px] text-[#64748B]">
            <p>{{ vm.hasFilters ? 'Ningún técnico coincide con los filtros actuales.' : 'Aún no hay perfiles de técnico registrados.' }}</p>
            @if (vm.hasFilters) {
              <button type="button" (click)="clearFilters()" class="mt-2 text-[13px] font-semibold !text-[#457b9d] hover:underline">Limpiar filtros</button>
            } @else if (canManage()) {
              <button type="button" (click)="openCreate()" class="mt-2 text-[13px] font-semibold !text-[#457b9d] hover:underline">Registrar el primero</button>
            }
          </div>
        } @else if (view() === 'cards') {
          <div class="grid grid-cols-1 gap-4 lg:grid-cols-2 2xl:grid-cols-3">
            @for (item of vm.pageItems; track item.id) {
              <article class="flex flex-col gap-5 rounded-2xl border border-brand-accentLight/70 bg-surface-container-lowest p-5 shadow-[0_8px_24px_rgba(62,92,118,0.08)] transition-shadow hover:shadow-[0_10px_28px_rgba(62,92,118,0.14)]">
                <div class="flex items-start gap-4">
                  <span class="flex h-[72px] w-[72px] shrink-0 items-center justify-center rounded-2xl bg-brand-accentLight text-[26px] font-extrabold text-brand-accentDeep" aria-hidden="true">{{ initialsOf(item.full_name) }}</span>
                  <div class="min-w-0 flex-1 space-y-2">
                    <div class="flex flex-wrap items-center gap-x-2">
                      <h2 class="min-w-0 break-words text-[20px] font-extrabold leading-tight text-brand-sidebar">{{ item.full_name }}</h2>
                      @if (item.employee_code) {
                        <span class="rounded bg-surface-container px-1.5 py-0.5 font-mono text-[11px] font-bold text-on-surface-variant">{{ item.employee_code }}</span>
                      }
                    </div>
                    @if (canManage()) {
                      <button type="button" (click)="toggleAvailability(item); $event.stopPropagation()" [attr.aria-label]="toggleLabel(item)" [attr.title]="toggleLabel(item)" [disabled]="vm.saving"
                        class="inline-flex items-center gap-2 rounded-full px-3 py-1 text-[13px] font-bold transition-[filter] hover:brightness-95 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep disabled:opacity-60" [class]="styleOf(vm, item).chip">
                        <span class="h-2.5 w-2.5 rounded-full" [class]="styleOf(vm, item).dot"></span>{{ statusText(vm, item) }}<span class="material-symbols-outlined text-[16px]" aria-hidden="true">sync_alt</span>
                      </button>
                    } @else {
                      <span class="inline-flex items-center gap-2 rounded-full px-3 py-1 text-[13px] font-bold" [class]="styleOf(vm, item).chip">
                        <span class="h-2.5 w-2.5 rounded-full" [class]="styleOf(vm, item).dot"></span>{{ statusText(vm, item) }}
                      </span>
                    }
                  </div>
                </div>

                <div class="space-y-3">
                  <div class="flex flex-wrap gap-2">
                    @for (tag of tagsOf(item).slice(0, 4); track tag) {
                      <span class="inline-flex max-w-full items-center gap-1.5 rounded-lg bg-brand-accentLight/50 px-2.5 py-1 text-[13px] font-semibold text-brand-accentDeep">
                        <span class="material-symbols-outlined text-[16px]" aria-hidden="true">settings</span><span class="min-w-0 break-words">{{ capitalize(tag) }}</span>
                      </span>
                    } @empty {
                      <span class="text-[13px] text-on-surface-variant">Sin especialización registrada</span>
                    }
                  </div>
                  <p class="flex items-center gap-2 text-[13px] text-on-surface-variant">
                    <span class="material-symbols-outlined text-[20px] text-brand-accentDeep" aria-hidden="true">mail</span>
                    <a [href]="'mailto:' + item.email" class="min-w-0 break-all !text-on-surface-variant hover:underline">{{ item.email }}</a>
                  </p>
                </div>

                <div class="space-y-4 border-t border-brand-accentLight/70 pt-5">
                  <div class="grid grid-cols-2 divide-x divide-brand-grey/60">
                    <div class="flex min-w-0 items-center justify-center gap-3 pr-3">
                      <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-brand-accentLight/50 text-brand-accentDeep" aria-hidden="true"><span class="material-symbols-outlined text-[24px]">folder_open</span></span>
                      <dl class="m-0 min-w-0">
                        <dd class="m-0 text-[22px] font-extrabold leading-6 text-brand-sidebar">{{ vm.hasWorkload ? (vm.workload[item.id]?.open_tickets ?? 0) : '—' }}</dd>
                        <dt class="m-0 text-[11px] font-bold uppercase tracking-wide text-on-surface-variant">Abiertos</dt>
                      </dl>
                    </div>
                    <div class="flex min-w-0 items-center justify-center gap-3 pl-3">
                      <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-brand-accentLight/50 text-brand-accentDeep" aria-hidden="true"><span class="material-symbols-outlined text-[24px]">task_alt</span></span>
                      <dl class="m-0 min-w-0">
                        <dd class="m-0 text-[22px] font-extrabold leading-6 text-brand-sidebar">{{ vm.hasWorkload ? (vm.workload[item.id]?.resolved_in_window ?? 0) : '—' }}</dd>
                        <dt class="m-0 text-[11px] font-bold uppercase tracking-wide text-on-surface-variant">Resueltos</dt>
                      </dl>
                    </div>
                  </div>
                  <div class="flex items-center justify-between gap-3 rounded-xl border border-brand-mustard/40 bg-secondary-fixed/50 px-4 py-3">
                    <div class="flex items-center gap-3">
                      <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-secondary-fixed text-on-secondary-fixed" aria-hidden="true"><span class="material-symbols-outlined text-[24px]">paid</span></span>
                      <span class="text-[11px] font-bold uppercase tracking-wide text-on-secondary-fixed">Tarifa por hora</span>
                    </div>
                    <dl class="m-0"><dd class="m-0 whitespace-nowrap text-[22px] font-extrabold leading-6 text-brand-sidebar">{{ item.hourly_rate ? (item.hourly_rate | currency) : '—' }}</dd></dl>
                  </div>
                </div>

                <button type="button" (click)="openTechnician(item.id)"
                  class="flex w-full items-center justify-between rounded-xl border border-brand-accentLight bg-brand-accentLight/40 px-4 py-3 text-[15px] font-bold !text-brand-sidebar transition-colors hover:bg-brand-accentLight/70 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
                  <span class="w-5" aria-hidden="true"></span>
                  <span class="flex items-center gap-2"><span class="material-symbols-outlined text-[22px]" aria-hidden="true">visibility</span> Ver ficha técnica</span>
                  <span class="material-symbols-outlined w-5 text-[20px] text-brand-slate" aria-hidden="true">chevron_right</span>
                </button>
              </article>
            }
          </div>
        } @else {
          <div class="overflow-hidden rounded-xl border border-[#E2E8F0] bg-white">
            <div class="overflow-x-auto">
              <table class="w-full border-collapse text-center">
                <thead>
                  <tr class="text-[11px] font-bold uppercase tracking-wider">
                    <th scope="col" class="bg-brand-accentDeep px-4 py-3 text-left !text-white">Técnico</th>
                    <th scope="col" class="bg-brand-grey px-3 py-3 !text-brand-navy">Código</th>
                    <th scope="col" class="bg-brand-accentLight px-3 py-3 !text-brand-navy">Estado</th>
                    <th scope="col" class="bg-brand-accentSky px-4 py-3 text-left !text-brand-navy">Especialidad</th>
                    <th scope="col" class="bg-brand-slate px-3 py-3 !text-brand-navy">Disponibilidad</th>
                    <th scope="col" class="bg-brand-mustard px-3 py-3 !text-brand-navy">Abiertos</th>
                    <th scope="col" class="bg-brand-accentLight px-3 py-3 !text-brand-navy">Resueltos</th>
                    <th scope="col" class="bg-brand-accentSky px-3 py-3 !text-brand-navy">Tarifa/h</th>
                    <th scope="col" class="bg-brand-grey px-3 py-3 !text-brand-navy"><span class="sr-only">Ver</span><span aria-hidden="true">Ver</span></th>
                  </tr>
                </thead>
                <tbody>
                  @for (item of vm.pageItems; track item.id) {
                    <tr tabindex="0" (click)="openTechnician(item.id)" (keydown.enter)="openTechnician(item.id)"
                      class="cursor-pointer border-b border-[#E9EEF5]/70 transition-colors hover:bg-[#EEF4FA]/60">
                      <td class="px-4 py-3 text-left">
                        <div class="flex items-center gap-3">
                          <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[#ADD7F6] text-[12px] font-bold text-[#3E5C76]">{{ initialsOf(item.full_name) }}</span>
                          <span class="min-w-0"><span class="block break-words text-[14px] font-bold">{{ item.full_name }}</span><span class="block break-all text-[12px] text-[#64748B]">{{ item.email }}</span></span>
                        </div>
                      </td>
                      <td class="whitespace-nowrap px-3 py-3 font-mono text-[12px] text-[#64748B]">{{ item.employee_code || '—' }}</td>
                      <td class="whitespace-nowrap px-3 py-3">
                        <span class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-bold"
                          [class]="isActive(item) ? 'bg-[#D1FAE5] text-[#065F46]' : 'bg-[#E2E8F0] text-[#475569]'">{{ isActive(item) ? 'Activo' : 'Inactivo' }}</span>
                      </td>
                      <td class="px-4 py-3 text-left text-[13px] text-[#1E293B]">{{ item.specialization || '—' }}</td>
                      <td class="px-3 py-3">
                        @if (canManage()) {
                          <button type="button" (click)="toggleAvailability(item); $event.stopPropagation()" [attr.aria-label]="toggleLabel(item)" [attr.title]="toggleLabel(item)" [disabled]="vm.saving"
                            class="inline-flex items-center gap-2 rounded-full px-2.5 py-1 text-[12px] font-bold transition-[filter] hover:brightness-95 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep disabled:opacity-60" [class]="styleOf(vm, item).chip">
                            <span class="h-1.5 w-1.5 rounded-full" [class]="styleOf(vm, item).dot"></span>{{ statusText(vm, item) }}<span class="material-symbols-outlined text-[16px]" aria-hidden="true">sync_alt</span>
                          </button>
                        } @else {
                          <span class="inline-flex items-center gap-2 rounded-full px-2.5 py-1 text-[12px] font-bold" [class]="styleOf(vm, item).chip">
                            <span class="h-1.5 w-1.5 rounded-full" [class]="styleOf(vm, item).dot"></span>{{ statusText(vm, item) }}
                          </span>
                        }
                      </td>
                      <td class="px-3 py-3 text-[13px] font-bold">{{ vm.hasWorkload ? (vm.workload[item.id]?.open_tickets ?? 0) : '—' }}</td>
                      <td class="px-3 py-3 text-[13px] font-bold">{{ vm.hasWorkload ? (vm.workload[item.id]?.resolved_in_window ?? 0) : '—' }}</td>
                      <td class="whitespace-nowrap px-3 py-3 font-mono text-[12px]">{{ item.hourly_rate ? (item.hourly_rate | currency) : '—' }}</td>
                      <td class="px-3 py-3">
                        <button type="button" (click)="openTechnician(item.id); $event.stopPropagation()" [attr.aria-label]="'Ver ficha de ' + item.full_name"
                          class="rounded-lg p-1.5 !text-[#64748B] transition-colors hover:bg-[#E9EEF5] hover:!text-[#0b1f3a]">
                          <span class="material-symbols-outlined text-[18px]">visibility</span>
                        </button>
                      </td>
                    </tr>
                  }
                </tbody>
              </table>
            </div>
          </div>
        }

        @if (vm.pages > 1) {
          <app-pagination noun="técnicos" [page]="vm.page" [pageSize]="pageSize" [total]="vm.filtered.length" (pageChange)="setPage($event)" />
        }

        @if (createOpen()) {
          <div class="fixed inset-0 z-[60] flex items-center justify-center p-4">
            <div class="absolute inset-0 bg-[#0b1f3a]/50" (click)="closeCreate()" aria-hidden="true"></div>
            <form role="dialog" aria-modal="true" aria-label="Registrar técnico" (submit)="submitCreate($event)"
              class="relative max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-[#CED4DA] bg-white shadow-2xl">
              <div class="flex items-center justify-between bg-[#0b1f3a] px-6 py-4 text-white">
                <div class="flex items-center gap-3">
                  <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-white/10 text-[#ADD7F6]"><span class="material-symbols-outlined text-[20px]">person_add</span></span>
                  <div>
                    <h2 class="text-[17px] font-bold">Registrar técnico</h2>
                    <p class="text-[12px] text-[#CED4DA]">Abre un perfil técnico a un usuario existente</p>
                  </div>
                </div>
                <button type="button" (click)="closeCreate()" aria-label="Cerrar" class="flex h-8 w-8 items-center justify-center rounded-lg !text-[#CED4DA] hover:bg-white/15 hover:!text-white">
                  <span class="material-symbols-outlined">close</span>
                </button>
              </div>
              <div class="space-y-4 p-6">
                <div>
                  <span class="mb-1 block text-[13px] font-semibold">Usuario <span class="text-[#BA1A1A]">*</span></span>
                  <app-custodian-picker placeholder="Buscar usuario por nombre o correo…" (picked)="candidate.set($event)" />
                  <p class="mt-1 text-[11px] text-[#94A3B8]">Solo aparecen usuarios activos. Un usuario puede tener un único perfil de técnico.</p>
                </div>
                <label class="block text-[13px] font-semibold">Especialización
                  <input name="specialization" [attr.maxlength]="maxSpecialization" class="mt-1 h-11 font-normal" [class]="field" placeholder="Ej: Hardware, Redes (separa varias con comas)" />
                </label>
                <label class="block text-[13px] font-semibold">Tarifa por hora
                  <input name="rate" type="number" min="0" max="99999999.99" step="0.01" class="mt-1 h-11 font-mono font-normal" [class]="field" />
                </label>
                @if (createError() || vm.error) {
                  <p class="rounded-lg bg-[#FEE2E2] px-3 py-2 text-[12px] text-[#991B1B]" role="alert">{{ createError() || vm.error }}</p>
                }
                <div class="flex items-center justify-end gap-2 border-t border-[#E9EEF5] pt-4">
                  <button type="button" (click)="closeCreate()" class="rounded-lg px-4 py-2.5 text-[13px] font-medium !text-[#1E293B] hover:bg-[#E9EEF5]">Cancelar</button>
                  <button type="submit" [disabled]="vm.saving"
                    class="rounded-lg bg-[#0b1f3a] px-5 py-2.5 text-[13px] font-bold !text-[#D4A017] shadow-sm hover:bg-[#3E5C76] disabled:opacity-50">
                    {{ vm.saving ? 'Guardando…' : 'Registrar técnico' }}
                  </button>
                </div>
              </div>
            </form>
          </div>
        }

        @if (exportOpen()) {
          <app-export-drawer report="technicians" title="técnicos" [initial]="exportInitial(vm)" [filterKinds]="['roster']"
            [showPeriod]="false" [specialtyOptions]="vm.specialties" (closed)="exportOpen.set(false)" />
        }

        @if (selectedTechnician(vm); as selected) {
          <app-technician-drawer
            [technician]="selected"
            [load]="vm.workload[selected.id]"
            [hasWorkload]="vm.hasWorkload"
            [windowDays]="vm.windowDays"
            [canManage]="canManage()"
            [saving]="vm.saving"
            [error]="vm.error"
            [notice]="vm.notice"
            (closed)="closeTechnician()"
            (availabilityChange)="setAvailability(selected, $event)"
            (edited)="edit(selected, $event)" />
        }
      </div>
    }
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class TechniciansComponent implements OnInit {
  private readonly store = inject(TechniciansStore);
  private readonly profile = inject(LocalProfileService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly filters$ = new BehaviorSubject<TechnicianFilters>(EMPTY_TECHNICIAN_FILTERS);
  private readonly page$ = new BehaviorSubject(1);

  readonly vm$ = combineLatest([this.store.state$, this.filters$, this.page$]).pipe(
    map(([state, filters, page]) => this.toView(state, filters, page)),
  );
  readonly statuses: TechnicianStatus[] = ['free', 'busy', 'unavailable'];
  readonly orders = ORDER_OPTIONS;
  readonly activeOptions = ACTIVE_OPTIONS;
  readonly availabilityOptions = AVAILABILITY_OPTIONS;
  readonly loadOptions = LOAD_OPTIONS;
  readonly isActive = isActiveAccount;
  readonly field = FIELD;
  readonly pageSize = PAGE_SIZE;
  readonly maxSpecialization = MAX_SPECIALIZATION;
  readonly initialsOf = initials;

  readonly view = signal<'cards' | 'table'>('cards');
  readonly createOpen = signal(false);
  readonly exportOpen = signal(false);
  readonly createError = signal('');
  readonly candidate = signal<CustodianCandidate | null>(null);
  readonly canManage = signal(false);
  /** El técnico abierto vive en `?technician=ID`, así el enlace a su ficha se puede compartir. */
  readonly selectedId = toSignal(
    this.route.queryParamMap.pipe(map((params) => Number(params.get('technician')) || null)),
    { initialValue: null },
  );

  statusLabel = (status: TechnicianStatus): string => STATUS_STYLES[status].label;
  tagsOf = specialties;

  async ngOnInit(): Promise<void> {
    this.store.saved$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe((saved) => {
      if (this.createOpen()) {
        this.createOpen.set(false);
        this.openTechnician(saved.id);
      }
    });
    this.store.load();
    this.canManage.set(await this.profile.can('tecnicos:editar').catch(() => false));
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.createOpen.set(false);
  }

  setFilter(changes: Partial<TechnicianFilters>): void {
    this.filters$.next({ ...this.filters$.value, ...changes });
    this.page$.next(1);
  }

  clearFilters(): void {
    this.filters$.next(EMPTY_TECHNICIAN_FILTERS);
    this.page$.next(1);
  }

  setPage(page: number): void {
    this.page$.next(page);
  }

  styleOf(vm: TechniciansView, item: Technician) {
    return STATUS_STYLES[technicianStatus(item, vm.workload)];
  }

  statusText(vm: TechniciansView, item: Technician): string {
    const status = technicianStatus(item, vm.workload);
    if (status === 'busy') {
      const open = vm.workload[item.id]?.open_tickets ?? 0;
      return `${open} ${open === 1 ? 'ticket activo' : 'tickets activos'}`;
    }
    return STATUS_STYLES[status].label;
  }

  selectedTechnician(vm: TechniciansView): Technician | null {
    const id = this.selectedId();
    return id ? (vm.technicians.find((item) => item.id === id) ?? null) : null;
  }

  openTechnician(id: number): void {
    this.store.clearMessages();
    void this.router.navigate([], { relativeTo: this.route, queryParams: { technician: id }, queryParamsHandling: 'merge' });
  }

  closeTechnician(): void {
    this.store.clearMessages();
    void this.router.navigate([], { relativeTo: this.route, queryParams: { technician: null }, queryParamsHandling: 'merge' });
  }

  /** Un clic en la disponibilidad la invierte: «No disponible» pasa a disponible y viceversa (el servidor valida el permiso). */
  toggleAvailability(technician: Technician): void {
    this.store.setAvailability(technician, !technician.is_available);
  }

  toggleLabel(technician: Technician): string {
    return technician.is_available ? `Marcar a ${technician.full_name} como no disponible` : `Marcar a ${technician.full_name} como disponible`;
  }

  /** «hardware» -> «Hardware»: solo la primera letra, sin tocar el resto. */
  capitalize(text: string): string {
    return text.charAt(0).toUpperCase() + text.slice(1);
  }

  setAvailability(technician: Technician, isAvailable: boolean): void {
    this.store.setAvailability(technician, isAvailable);
  }

  edit(technician: Technician, edit: TechnicianEdit): void {
    this.store.update(technician.id, edit.payload, edit.notice);
  }

  dismissNotice(): void {
    this.store.clearMessages();
  }

  openCreate(): void {
    this.store.clearMessages();
    this.candidate.set(null);
    this.createError.set('');
    this.createOpen.set(true);
  }

  closeCreate(): void {
    this.createOpen.set(false);
  }

  submitCreate(event: Event): void {
    event.preventDefault();
    const data = new FormData(event.target as HTMLFormElement);
    const specialization = String(data.get('specialization') ?? '').trim();
    const rate = String(data.get('rate') ?? '').trim();
    const user = this.candidate();
    const error = validateTechnicianInput({ userId: user?.id, specialization, rate }, true);
    this.createError.set(error);
    if (error || !user) {
      return;
    }
    this.store.create({
      user_id: user.id,
      specialization: specialization || null,
      hourly_rate: rate ? Number(rate) : null,
    });
  }

  /** El panel de exportación parte de los filtros de la pantalla (las tarjetas de resumen se traducen a disponibilidad y carga). */
  exportInitial(vm: TechniciansView): ExportFilterValues {
    const { filters } = vm;
    const fromCard = {
      free: { availability: 'available', load: 'none' },
      busy: { availability: 'available', load: '' },
      unavailable: { availability: 'unavailable', load: '' },
    } as const;
    const card = filters.status ? fromCard[filters.status] : null;
    return {
      statuses: [], priorities: [], categories: [], technicianIds: [], dateFrom: '', dateTo: '',
      search: filters.search,
      specialty: filters.specialty,
      active: filters.active,
      availability: filters.availability || card?.availability || '',
      load: filters.load || card?.load || '',
    };
  }

  private toView(state: TechniciansState, filters: TechnicianFilters, requestedPage: number): TechniciansView {
    const filtered = filterTechnicians(state.technicians, state.workload, filters);
    const pages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
    const page = Math.min(Math.max(1, requestedPage), pages);
    return {
      ...state,
      filters,
      filtered,
      pageItems: filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE),
      page,
      pages,
      summary: summarize(state.technicians, state.workload),
      specialties: allSpecialties(state.technicians),
      hasFilters: hasTechnicianFilters(filters),
    };
  }
}
