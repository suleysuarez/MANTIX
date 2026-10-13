import { AsyncPipe, DatePipe } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  ElementRef,
  HostListener,
  OnInit,
  inject,
  signal,
  viewChild,
} from '@angular/core';
import { takeUntilDestroyed, toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router } from '@angular/router';
import { Subject, debounceTime, map } from 'rxjs';

import { Equipment } from '../../core/equipment.service';
import { LocalProfileService } from '../../core/local-profile.service';
import { MaintenanceListItem, PRIORITIES, REQUEST_STATUSES } from '../../core/maintenance.service';
import { TicketFilters, TicketOrder, TicketsState, TicketsStore, todayLocal } from '../../core/tickets.store';
import { TicketChipComponent } from './ticket-chip.component';
import { TicketDrawerComponent } from './ticket-drawer.component';
import {
  KANBAN_STATUSES,
  countByStatus,
  isUnassigned,
  needingAttention,
  priorityMeta,
  statusMeta,
  ticketsToCsv,
} from './ticket-ui';

const FIELD =
  'w-full rounded-lg border border-[#CED4DA] bg-[#F7FAFC] px-3 text-[13px] text-[#1E293B] placeholder:text-[#94A3B8] focus:border-[#457b9d] focus:outline-none';

interface MetricCard {
  label: string;
  hint: string;
  icon: string;
  status: string;
  tone: string;
}

const METRICS: readonly MetricCard[] = [
  { label: 'Total', hint: 'Todas las órdenes', icon: 'confirmation_number', status: '', tone: 'bg-[#EEF4FA] text-[#457b9d]' },
  { label: 'Enviados', hint: 'Pendientes de triaje', icon: 'mark_email_unread', status: 'submitted', tone: 'bg-[#DBEAFE] text-[#1E40AF]' },
  { label: 'En proceso', hint: 'Con el técnico', icon: 'engineering', status: 'in_progress', tone: 'bg-[#FEF3C7] text-[#92400E]' },
  { label: 'Resueltos', hint: 'Solución aplicada', icon: 'check_circle', status: 'resolved', tone: 'bg-[#D1FAE5] text-[#065F46]' },
  { label: 'Cerrados', hint: 'Cierre final', icon: 'task_alt', status: 'closed', tone: 'bg-[#E2E8F0] text-[#334155]' },
];

/** Estado de la pantalla ya preparado para la plantilla (contadores, kanban, equipos por id). */
interface TicketsView extends TicketsState {
  counts: Record<string, number | undefined>;
  attention: MaintenanceListItem[];
  equipmentById: Map<number, Equipment>;
  columns: { status: string; items: MaintenanceListItem[] }[];
  hasFilters: boolean;
}

/** Smart component: tickets en tabla o kanban, filtros, alta y panel de detalle. */
@Component({
  selector: 'app-tickets',
  standalone: true,
  imports: [AsyncPipe, DatePipe, TicketChipComponent, TicketDrawerComponent],
  template: `
    @if (vm$ | async; as vm) {
      <div class="space-y-5">
        <header class="flex flex-col justify-between gap-4 md:flex-row md:items-center">
          <div>
            <h1 class="text-[26px] font-extrabold tracking-tight text-[#0b1f3a]">Gestión de tickets</h1>
            <p class="text-[14px] text-[#64748B]">Registra, asigna, diagnostica y supervisa las incidencias técnicas y órdenes de trabajo activas.</p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <button type="button" (click)="exportCsv(vm)" [disabled]="vm.items.length === 0" title="Exporta los tickets de la página actual"
              class="flex items-center gap-1.5 rounded-lg border border-[#CED4DA] bg-white px-3 py-2 text-[13px] font-medium !text-[#1E293B] transition-colors hover:bg-[#EEF4FA] disabled:opacity-50">
              <span class="material-symbols-outlined text-[18px] text-[#457b9d]">file_download</span> Exportar CSV
            </button>
            @if (canCreate()) {
              <button type="button" (click)="openCreate()"
                class="flex items-center gap-1.5 rounded-lg bg-[#0b1f3a] px-4 py-2.5 text-[13px] font-bold !text-[#D4A017] shadow-sm transition-colors hover:bg-[#3E5C76]">
                <span class="material-symbols-outlined text-[20px]">add</span> Nuevo ticket
              </button>
            }
          </div>
        </header>

        @if (vm.error) {
          <p class="rounded-lg bg-[#FEE2E2] px-4 py-3 text-[13px] text-[#991B1B]" role="alert">{{ vm.error }}</p>
        }

        <div class="grid grid-cols-2 gap-3 md:grid-cols-5">
          @for (card of metrics; track card.label) {
            <button type="button" (click)="filterStatus(card.status)"
              class="flex items-center justify-between rounded-xl border bg-white p-3 text-left transition-all hover:border-[#457b9d]"
              [class]="vm.filters.status === card.status ? 'border-[#457b9d] ring-1 ring-[#457b9d]/30' : 'border-[#E2E8F0]'">
              <div>
                <span class="block text-[11px] font-semibold uppercase tracking-wider text-[#64748B]">{{ card.label }}</span>
                <span class="block text-[26px] font-extrabold leading-tight text-[#0b1f3a]">{{ card.status ? (vm.counts[card.status] ?? 0) : vm.all.length }}</span>
                <span class="block text-[11px] text-[#64748B]">{{ card.hint }}</span>
              </div>
              <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg" [class]="card.tone">
                <span class="material-symbols-outlined text-[18px]">{{ card.icon }}</span>
              </span>
            </button>
          }
        </div>

        @if (vm.attention.length > 0) {
          <section class="overflow-hidden rounded-xl border border-[#E2E8F0] bg-[#F7FAFC]">
            <button type="button" (click)="attentionOpen.set(!attentionOpen())" [attr.aria-expanded]="attentionOpen()"
              class="flex w-full items-center justify-between bg-white px-4 py-2.5 text-left">
              <span class="flex items-center gap-2">
                <span class="h-2 w-2 animate-pulse rounded-full bg-[#DC2626]"></span>
                <span class="material-symbols-outlined text-[18px] text-[#DC2626]">error</span>
                <span class="text-[14px] font-bold">Requieren atención prioritaria</span>
                <span class="rounded-full bg-[#FEE2E2] px-2 py-0.5 text-[11px] font-bold text-[#991B1B]">{{ vm.attention.length }} críticos / altos</span>
              </span>
              <span class="material-symbols-outlined text-[18px] text-[#64748B] transition-transform" [class]="attentionOpen() ? 'rotate-180' : ''">expand_more</span>
            </button>
            @if (attentionOpen()) {
              <div class="grid grid-cols-1 gap-3 p-3 md:grid-cols-3">
                @for (item of vm.attention.slice(0, 6); track item.id) {
                  <article class="flex flex-col justify-between rounded-lg border border-[#E2E8F0] bg-white p-3">
                    <div>
                      <div class="mb-1 flex items-center justify-between">
                        <span class="font-mono text-[12px] font-bold text-[#3E5C76]">{{ item.ticket_number }}</span>
                        <app-ticket-chip kind="priority" [value]="item.priority" />
                      </div>
                      <p class="mb-1 line-clamp-1 text-[13px] font-bold">{{ item.title }}</p>
                      <p class="flex items-center gap-1 text-[11px] text-[#64748B]">
                        <span class="material-symbols-outlined text-[13px] text-[#457b9d]">devices</span>
                        <span class="truncate">{{ equipmentLabel(vm, item.equipment_id) }}</span>
                      </p>
                    </div>
                    <div class="mt-2.5 flex items-center justify-between border-t border-[#E9EEF5] pt-2">
                      @if (unassigned(item.status)) {
                        <span class="inline-flex items-center gap-1 rounded bg-[#FEF3C7] px-2 py-0.5 text-[11px] font-semibold text-[#92400E]">
                          <span class="material-symbols-outlined text-[13px]">person_off</span> Sin asignar
                        </span>
                      } @else {
                        <app-ticket-chip kind="status" [value]="item.status" />
                      }
                      <button type="button" (click)="openTicket(item.id)"
                        class="rounded-md bg-[#EEF4FA] px-2.5 py-1 text-[11px] font-bold !text-[#3E5C76] transition-colors hover:bg-[#ADD7F6]/50">Ver ticket</button>
                    </div>
                  </article>
                }
              </div>
            }
          </section>
        }

        <section class="space-y-3 rounded-xl border border-[#E2E8F0] bg-white p-4">
          <div class="grid grid-cols-1 items-end gap-2 md:grid-cols-12">
            <div class="relative md:col-span-3">
              <span class="material-symbols-outlined pointer-events-none absolute left-3 top-2.5 text-[20px] text-[#94A3B8]">search</span>
              <input #searchInput type="search" [value]="initialSearch" (input)="onSearch($any($event.target).value)" aria-label="Buscar tickets"
                placeholder="Buscar por número, título o descripción…" class="h-10 pl-10" [class]="field" maxlength="100" />
            </div>
            <select (change)="setFilter({ status: $any($event.target).value })" aria-label="Estado" class="h-10 md:col-span-2" [class]="field">
              <option value="">Estado: Todos</option>
              @for (option of statuses; track option) {
                <option [value]="option" [selected]="option === vm.filters.status">{{ statusLabel(option) }}</option>
              }
            </select>
            <select (change)="setFilter({ priority: $any($event.target).value })" aria-label="Prioridad" class="h-10 md:col-span-2" [class]="field">
              <option value="">Prioridad: Todas</option>
              @for (option of priorities; track option) {
                <option [value]="option" [selected]="option === vm.filters.priority">{{ priorityLabel(option) }}</option>
              }
            </select>
            <div class="md:col-span-4">
              <span class="mb-0.5 block text-[11px] font-semibold text-[#64748B]">Rango de fechas</span>
              <div class="flex items-center gap-1">
                <input type="date" [value]="vm.filters.dateFrom" [max]="vm.filters.dateTo || today" (change)="setFilter({ dateFrom: $any($event.target).value })" aria-label="Rango de fechas: desde" title="Desde" class="h-10 !px-2 text-[12px]" [class]="field" />
                <span class="text-[12px] text-[#94A3B8]">-</span>
                <input type="date" [value]="vm.filters.dateTo" [min]="vm.filters.dateFrom" [max]="today" (change)="setFilter({ dateTo: $any($event.target).value })" aria-label="Rango de fechas: hasta" title="Hasta" class="h-10 !px-2 text-[12px]" [class]="field" />
              </div>
            </div>
            <button type="button" (click)="clearFilters()" [disabled]="!vm.hasFilters" title="Limpiar todos los filtros" aria-label="Limpiar filtros"
              class="flex h-10 items-center justify-center rounded-lg border border-[#CED4DA] bg-[#F7FAFC] !text-[#64748B] transition-colors hover:bg-[#E9EEF5] disabled:opacity-40 md:col-span-1">
              <span class="material-symbols-outlined text-[18px]">filter_alt_off</span>
            </button>
          </div>
          @if (vm.filterError) {
            <p class="rounded-lg bg-[#FEE2E2] px-3 py-2 text-[12px] text-[#991B1B]" role="alert">{{ vm.filterError }}</p>
          }
          <div class="flex items-center justify-between border-t border-[#E9EEF5] pt-2 text-[12px] text-[#64748B]">
            <span class="flex items-center gap-2">
              <span class="h-2 w-2 rounded-full bg-[#457b9d]"></span>
              @if (vm.hasFilters) {
                <strong class="text-[#1E293B]">{{ vm.items.length }}{{ vm.hasNext ? '+' : '' }}</strong> {{ vm.items.length === 1 ? 'ticket coincide' : 'tickets coinciden' }} con los filtros aplicados
              } @else {
                <strong class="text-[#1E293B]">{{ vm.all.length }}</strong> {{ vm.all.length === 1 ? 'ticket' : 'tickets' }} en total
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
              <button type="button" (click)="view.set('table')" [attr.aria-pressed]="view() === 'table'"
                class="flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[13px] transition-all"
                [class]="view() === 'table' ? 'bg-white font-bold !text-[#0b1f3a] shadow-sm' : 'font-medium !text-[#64748B] hover:!text-[#0b1f3a]'">
                <span class="material-symbols-outlined text-[18px]">table_rows</span> Tabla
              </button>
              <button type="button" (click)="view.set('kanban')" [attr.aria-pressed]="view() === 'kanban'"
                class="flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[13px] transition-all"
                [class]="view() === 'kanban' ? 'bg-white font-bold !text-[#0b1f3a] shadow-sm' : 'font-medium !text-[#64748B] hover:!text-[#0b1f3a]'">
                <span class="material-symbols-outlined text-[18px]">view_kanban</span> Kanban
              </button>
            </div>
        </div>

        @if (vm.loading) {
          <p class="rounded-xl border border-[#E2E8F0] bg-white p-6 text-center text-[14px] text-[#64748B]">Cargando tickets…</p>
        } @else if (vm.items.length === 0) {
          <p class="rounded-xl border border-[#E2E8F0] bg-white p-8 text-center text-[14px] text-[#64748B]">
            {{ vm.hasFilters ? 'Ningún ticket coincide con los filtros actuales.' : 'Aún no hay tickets registrados.' }}
          </p>
        } @else if (view() === 'table') {
          <div class="overflow-hidden rounded-xl border border-[#E2E8F0] bg-white">
            <div class="overflow-x-auto">
              <table class="w-full border-collapse text-left">
                <thead>
                  <tr class="border-b border-[#E9EEF5] bg-[#EEF4FA]/70 text-[11px] font-bold uppercase tracking-wider text-[#64748B]">
                    <th class="w-28 px-4 py-3">Ticket</th>
                    <th class="min-w-[280px] px-4 py-3">Título y descripción</th>
                    <th class="min-w-[200px] px-4 py-3">Equipo</th>
                    <th class="px-3 py-3 text-center">Prioridad</th>
                    <th class="px-3 py-3 text-center">Estado</th>
                    <th class="px-4 py-3">Creado</th>
                    <th class="w-16 px-3 py-3 text-right">Ver</th>
                  </tr>
                </thead>
                <tbody>
                  @for (item of vm.items; track item.id) {
                    <tr tabindex="0" (click)="openTicket(item.id)" (keydown.enter)="openTicket(item.id)" class="cursor-pointer border-b border-[#E9EEF5]/70 transition-colors hover:bg-[#EEF4FA]/60">
                      <td class="whitespace-nowrap px-4 py-3">
                        <span class="rounded border border-[#CED4DA] bg-[#EEF4FA]/70 px-2 py-1 font-mono text-[12px] font-bold text-[#3E5C76]">{{ item.ticket_number }}</span>
                      </td>
                      <td class="px-4 py-3">
                        <p class="max-w-sm truncate text-[14px] font-bold">{{ item.title }}</p>
                        @if (unassigned(item.status)) {
                          <span class="mt-0.5 inline-flex items-center gap-1 text-[11px] font-semibold text-[#92400E]">
                            <span class="material-symbols-outlined text-[13px]">person_off</span> Sin asignar
                          </span>
                        }
                      </td>
                      <td class="whitespace-nowrap px-4 py-3">
                        <span class="inline-flex items-center gap-2 rounded-lg border border-[#CED4DA]/60 bg-[#EEF4FA]/60 px-2.5 py-1 text-[12px] font-medium">
                          <span class="material-symbols-outlined text-[16px] text-[#457b9d]">devices</span>
                          {{ equipmentLabel(vm, item.equipment_id) }}
                        </span>
                      </td>
                      <td class="whitespace-nowrap px-3 py-3 text-center"><app-ticket-chip kind="priority" [value]="item.priority" /></td>
                      <td class="whitespace-nowrap px-3 py-3 text-center"><app-ticket-chip kind="status" [value]="item.status" /></td>
                      <td class="whitespace-nowrap px-4 py-3 text-[12px] text-[#64748B]">{{ item.created_at | date: 'dd/MM/yyyy HH:mm' }}</td>
                      <td class="px-3 py-3 text-right">
                        <button type="button" (click)="openTicket(item.id); $event.stopPropagation()" [attr.aria-label]="'Ver ' + item.ticket_number"
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
        } @else {
          <div class="flex items-start gap-3 overflow-x-auto pb-2">
            @for (column of vm.columns; track column.status) {
              <section class="flex min-h-[320px] w-[270px] shrink-0 flex-col rounded-xl border border-[#E2E8F0] bg-[#EEF4FA]/60 p-3">
                <div class="flex items-center justify-between border-b border-[#E9EEF5] pb-3">
                  <span class="flex items-center gap-2 text-[14px] font-bold">
                    <span class="h-2.5 w-2.5 rounded-full" [class]="statusDot(column.status)"></span>{{ statusLabel(column.status) }}
                  </span>
                  <span class="rounded-full bg-white px-2 py-0.5 text-[12px] font-bold">{{ column.items.length }}</span>
                </div>
                <div class="flex-1 space-y-2 pt-2">
                  @for (item of column.items; track item.id) {
                    <article role="button" tabindex="0" (click)="openTicket(item.id)" (keydown.enter)="openTicket(item.id)" class="cursor-pointer space-y-2 rounded-xl border border-[#E2E8F0] bg-white p-3 transition-shadow hover:shadow-md">
                      <div class="flex items-center justify-between">
                        <span class="font-mono text-[12px] font-bold text-[#3E5C76]">{{ item.ticket_number }}</span>
                        <app-ticket-chip kind="priority" [value]="item.priority" />
                      </div>
                      <p class="line-clamp-2 text-[13px] font-bold">{{ item.title }}</p>
                      <p class="flex items-center gap-1 text-[11px] text-[#64748B]">
                        <span class="material-symbols-outlined text-[14px] text-[#457b9d]">devices</span>
                        <span class="truncate">{{ equipmentLabel(vm, item.equipment_id) }}</span>
                      </p>
                      <p class="border-t border-[#E9EEF5] pt-2 text-right text-[11px] text-[#94A3B8]">{{ item.created_at | date: 'dd/MM/yyyy' }}</p>
                    </article>
                  } @empty {
                    <p class="py-8 text-center text-[12px] italic text-[#94A3B8]">Sin tickets</p>
                  }
                </div>
              </section>
            }
          </div>
        }

        <nav class="flex items-center justify-end gap-3" aria-label="Páginas de tickets">
          <button type="button" (click)="page(vm.page - 1)" [disabled]="vm.page === 0 || vm.loading"
            class="flex h-8 items-center gap-1 rounded-lg border border-[#CED4DA] bg-white px-2.5 text-[13px] transition-colors hover:bg-[#E9EEF5] disabled:cursor-not-allowed disabled:opacity-50">
            <span class="material-symbols-outlined text-[18px]">chevron_left</span> Anterior
          </button>
          <span class="text-[13px] font-semibold">Página {{ vm.page + 1 }}</span>
          <button type="button" (click)="page(vm.page + 1)" [disabled]="!vm.hasNext || vm.loading"
            class="flex h-8 items-center gap-1 rounded-lg border border-[#CED4DA] bg-white px-2.5 text-[13px] transition-colors hover:bg-[#E9EEF5] disabled:cursor-not-allowed disabled:opacity-50">
            Siguiente <span class="material-symbols-outlined text-[18px]">chevron_right</span>
          </button>
        </nav>

        @if (createOpen()) {
          <div class="fixed inset-0 z-[60] flex items-center justify-center p-4">
            <div class="absolute inset-0 bg-[#0b1f3a]/50" (click)="closeCreate()" aria-hidden="true"></div>
            <form role="dialog" aria-modal="true" aria-label="Crear nuevo ticket" (submit)="submitCreate($event)"
              class="relative max-h-[92vh] w-full max-w-xl overflow-y-auto rounded-2xl border border-[#CED4DA] bg-white shadow-2xl">
              <div class="flex items-center justify-between bg-[#0b1f3a] px-6 py-4 text-white">
                <div class="flex items-center gap-3">
                  <span class="flex h-9 w-9 items-center justify-center rounded-lg bg-white/10 text-[#ADD7F6]"><span class="material-symbols-outlined text-[20px]">add_task</span></span>
                  <div>
                    <h2 class="text-[17px] font-bold">Crear nuevo ticket</h2>
                    <p class="text-[12px] text-[#CED4DA]">Formulario de incidencia</p>
                  </div>
                </div>
                <button type="button" (click)="closeCreate()" aria-label="Cerrar" class="flex h-8 w-8 items-center justify-center rounded-lg !text-[#CED4DA] hover:bg-white/15 hover:!text-white">
                  <span class="material-symbols-outlined">close</span>
                </button>
              </div>
              <div class="space-y-4 p-6">
                <label class="block text-[13px] font-semibold">Equipo tecnológico <span class="text-[#BA1A1A]">*</span>
                  <select name="equipment" required class="mt-1 h-11 font-normal" [class]="field">
                    <option value="" disabled selected>Selecciona un equipo del inventario…</option>
                    @for (item of vm.equipment; track item.id) {
                      <option [value]="item.id">{{ item.asset_tag }} · {{ item.brand }} {{ item.model }}</option>
                    }
                  </select>
                </label>
                <div>
                  <div class="flex items-center justify-between">
                    <label for="ticket-title" class="text-[13px] font-semibold">Título de la incidencia <span class="text-[#BA1A1A]">*</span></label>
                    <span class="text-[11px] text-[#94A3B8]">{{ titleLength() }} / 200</span>
                  </div>
                  <input id="ticket-title" name="title" required maxlength="200" (input)="titleLength.set($any($event.target).value.length)"
                    class="mt-1 h-11" [class]="field" placeholder="Ej: Ruido anormal en ventilador y reinicio térmico" />
                </div>
                <label class="block text-[13px] font-semibold">Descripción detallada <span class="text-[#BA1A1A]">*</span>
                  <textarea name="description" required rows="4" class="mt-1 py-2 font-normal" [class]="field"
                    placeholder="Describe los síntomas, eventos previos, mensajes en pantalla y condiciones de ocurrencia…"></textarea>
                </label>
                <label class="block text-[13px] font-semibold">Prioridad
                  <select name="priority" class="mt-1 h-11 font-normal" [class]="field">
                    @for (option of priorities; track option) {
                      <option [value]="option" [selected]="option === 'medium'">{{ priorityLabel(option) }}{{ option === 'medium' ? ' (predeterminada)' : '' }}</option>
                    }
                  </select>
                </label>
                @if (createError() || vm.error) {
                  <p class="rounded-lg bg-[#FEE2E2] px-3 py-2 text-[12px] text-[#991B1B]" role="alert">{{ createError() || vm.error }}</p>
                }
                <div class="flex items-center justify-end gap-2 border-t border-[#E9EEF5] pt-4">
                  <button type="button" (click)="closeCreate()" class="rounded-lg px-4 py-2.5 text-[13px] font-medium hover:bg-[#E9EEF5]">Cancelar</button>
                  <button type="submit" [disabled]="vm.saving"
                    class="rounded-lg bg-[#0b1f3a] px-5 py-2.5 text-[13px] font-bold !text-[#D4A017] shadow-sm hover:bg-[#3E5C76] disabled:opacity-50">
                    {{ vm.saving ? 'Guardando…' : 'Guardar y registrar ticket' }}
                  </button>
                </div>
              </div>
            </form>
          </div>
        }

        @if (selectedId(); as ticketId) {
          <app-ticket-drawer [ticketId]="ticketId" [canManage]="canManage()" (closed)="closeTicket()" (changed)="refresh()" />
        }
      </div>
    }
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class TicketsComponent implements OnInit {
  private readonly store = inject(TicketsStore);
  private readonly profile = inject(LocalProfileService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly search$ = new Subject<string>();

  readonly vm$ = this.store.state$.pipe(map((state) => this.toView(state)));
  readonly metrics = METRICS;
  readonly statuses = REQUEST_STATUSES;
  readonly priorities = PRIORITIES;
  readonly orders: { value: TicketOrder; label: string }[] = [
    { value: 'newest', label: 'Más recientes' },
    { value: 'oldest', label: 'Más antiguos' },
    { value: 'priority', label: 'Mayor prioridad' },
  ];
  readonly field = FIELD;
  readonly today = todayLocal();
  /** El campo de búsqueda no se enlaza al estado: reescribirlo mientras se teclea pisaría lo escrito. */
  readonly initialSearch = '';
  private readonly searchInput = viewChild<ElementRef<HTMLInputElement>>('searchInput');

  readonly view = signal<'table' | 'kanban'>('table');
  readonly attentionOpen = signal(true);
  readonly createOpen = signal(false);
  readonly titleLength = signal(0);
  readonly createError = signal('');
  readonly canCreate = signal(false);
  readonly canManage = signal(false);
  /** El ticket abierto vive en `?ticket=ID`, así el enlace al detalle se puede compartir. */
  readonly selectedId = toSignal(
    this.route.queryParamMap.pipe(map((params) => Number(params.get('ticket')) || null)),
    { initialValue: null },
  );

  unassigned = isUnassigned;
  statusLabel = (status: string): string => statusMeta(status).label;
  statusDot = (status: string): string => statusMeta(status).dot;
  priorityLabel = (priority: string): string => priorityMeta(priority).label;

  private lastEquipment: Equipment[] = [];
  private lastEquipmentMap = new Map<number, Equipment>();

  async ngOnInit(): Promise<void> {
    this.search$
      .pipe(debounceTime(300), takeUntilDestroyed(this.destroyRef))
      .subscribe((search) => this.store.setFilters({ search }));
    this.store.ticketCreated$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe((id) => {
      this.createOpen.set(false);
      this.openTicket(id);
    });
    this.store.load();
    this.canCreate.set(await this.profile.can('maintenance.create'));
    this.canManage.set(await this.profile.can('maintenance.manage'));
  }

  setFilter(changes: Partial<TicketFilters>): void {
    this.store.setFilters(changes);
  }

  filterStatus(status: string): void {
    this.store.setFilters({ status });
  }

  onSearch(value: string): void {
    this.search$.next(value);
  }

  clearFilters(): void {
    const input = this.searchInput();
    if (input) {
      input.nativeElement.value = '';
    }
    this.store.clearFilters();
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.createOpen.set(false);
  }

  page(page: number): void {
    this.store.setPage(page);
  }

  refresh(): void {
    this.store.refresh();
  }

  openTicket(id: number): void {
    void this.router.navigate([], { relativeTo: this.route, queryParams: { ticket: id }, queryParamsHandling: 'merge' });
  }

  closeTicket(): void {
    void this.router.navigate([], { relativeTo: this.route, queryParams: { ticket: null }, queryParamsHandling: 'merge' });
  }

  openCreate(): void {
    this.titleLength.set(0);
    this.createError.set('');
    this.createOpen.set(true);
  }

  closeCreate(): void {
    this.createOpen.set(false);
  }

  submitCreate(event: Event): void {
    event.preventDefault();
    const data = new FormData(event.target as HTMLFormElement);
    const equipmentId = Number(data.get('equipment'));
    const title = String(data.get('title') ?? '').trim();
    const description = String(data.get('description') ?? '').trim();
    if (!equipmentId) {
      this.createError.set('Selecciona el equipo afectado.');
      return;
    }
    if (!title) {
      this.createError.set('El título no puede estar vacío.');
      return;
    }
    if (title.length > 200) {
      this.createError.set('El título no puede superar los 200 caracteres.');
      return;
    }
    if (!description) {
      this.createError.set('La descripción no puede estar vacía.');
      return;
    }
    this.createError.set('');
    this.store.create({
      equipment_id: equipmentId,
      title,
      description,
      priority: String(data.get('priority') || 'medium'),
    });
  }

  equipmentLabel(vm: TicketsView, equipmentId: number): string {
    const equipment = vm.equipmentById.get(equipmentId);
    return equipment ? `${equipment.asset_tag} · ${equipment.brand} ${equipment.model}` : `Equipo #${equipmentId}`;
  }

  exportCsv(vm: TicketsView): void {
    const csv = ticketsToCsv(vm.items, (id) => this.equipmentLabel(vm, id));
    const url = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = `tickets-${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }

  private toView(state: TicketsState): TicketsView {
    if (state.equipment !== this.lastEquipment) {
      this.lastEquipment = state.equipment;
      this.lastEquipmentMap = new Map(state.equipment.map((item) => [item.id, item]));
    }
    const { search, status, priority, dateFrom, dateTo } = state.filters;
    return {
      ...state,
      counts: countByStatus(state.all),
      attention: needingAttention(state.all),
      equipmentById: this.lastEquipmentMap,
      columns: KANBAN_STATUSES.map((s) => ({ status: s, items: state.items.filter((item) => item.status === s) })),
      hasFilters: !!(search || status || priority || dateFrom || dateTo),
    };
  }
}
