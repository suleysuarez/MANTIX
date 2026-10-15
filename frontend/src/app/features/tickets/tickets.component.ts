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
import { Observable, Subject, catchError, debounceTime, map, of, tap } from 'rxjs';

import { Equipment } from '../../core/equipment.service';
import { PermissionsService } from '../../core/permissions.service';
import { apiErrorMessage } from '../../core/api-errors';
import { MaintenanceListItem, PRIORITIES, REQUEST_STATUSES } from '../../core/maintenance.service';
import { QueueService } from '../../core/queue.service';
import { Technician, TechniciansService } from '../../core/technicians.service';
import { TicketTransitionService } from '../../core/ticket-transitions.service';
import { ToastService } from '../../core/toast.service';
import { TransitionData, WorkflowService, WorkflowState } from '../../core/workflow.service';
import { TicketFilters, TicketOrder, TicketsState, TicketsStore, todayLocal } from '../../core/tickets.store';
import { ChoiceOption, ExportDrawerComponent } from '../export/export-drawer.component';
import { EMPTY_EXPORT_FILTERS, ExportFilterValues } from '../export/export-model';
import { TicketChipComponent } from './ticket-chip.component';
import { TicketDrawerComponent } from './ticket-drawer.component';
import {
  countByStatus,
  isUnassigned,
  needingAttention,
  priorityMeta,
  statusMeta,
} from './ticket-ui';
import { PaginationComponent } from '../../shared/pagination.component';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { KanbanBoardComponent, KanbanCardDirective, KanbanColumn, KanbanMove, KanbanOutcome } from '../kanban/kanban-board.component';
import { Choice, TransitionDialogComponent } from '../kanban/transition-dialog.component';
import { TransitionFlow, allowedTargets, permissionBlock } from '../kanban/transition-flow';
import { DateRangeFilterComponent } from '../../shared/date-range-filter.component';

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
  hasFilters: boolean;
}

/** Smart component: tickets en tabla o kanban, filtros, alta y panel de detalle. */
@Component({
  selector: 'app-tickets',
  standalone: true,
  imports: [AsyncPipe, DatePipe, TicketChipComponent, TicketDrawerComponent, ExportDrawerComponent, PaginationComponent, DateRangeFilterComponent, KanbanBoardComponent, KanbanCardDirective, TransitionDialogComponent, ToastHostComponent],
  template: `
    @if (vm$ | async; as vm) {
      <div class="space-y-5">
        <header class="flex flex-col justify-between gap-5 rounded-2xl bg-gradient-to-r from-[#0b1f3a] to-[#14365f] px-6 py-6 md:flex-row md:items-center md:px-8">
          <div class="flex items-center gap-5">
            <span class="hidden h-16 w-16 shrink-0 items-center justify-center self-center rounded-2xl border border-white/30 bg-white/10 text-[#ADD7F6] sm:flex">
              <span class="material-symbols-outlined block text-center !text-[34px] !leading-none">confirmation_number</span>
            </span>
            <div>
              <h1 class="text-[26px] font-extrabold uppercase tracking-tight text-white">Gestión de <span class="text-[#4DB8F0]">Tickets</span></h1>
              <p class="mt-1 max-w-xl text-[14px] leading-relaxed text-[#CBD5E1]">Registra, asigna, diagnostica y supervisa las incidencias técnicas y órdenes de trabajo activas.</p>
            </div>
          </div>
          <div class="flex flex-wrap items-center gap-3">
            @if (canCreate()) {
              <button type="button" (click)="openCreate()"
                class="flex items-center gap-1.5 rounded-lg border border-white/50 bg-white/25 shadow-[inset_0_1px_0_rgba(255,255,255,0.35)] backdrop-blur-md px-5 py-2.5 text-[13px] font-bold !text-[#FFB703] transition-colors hover:bg-white/35">
                <span class="material-symbols-outlined text-[20px]">add</span> Nuevo ticket
              </button>
            }
            <button type="button" (click)="exportOpen.set(true)" title="Exporta a PDF o Excel con los filtros que quieras"
              class="flex items-center gap-1.5 rounded-lg border border-white/50 bg-white/25 shadow-[inset_0_1px_0_rgba(255,255,255,0.35)] backdrop-blur-md px-5 py-2.5 text-[13px] font-bold !text-white transition-colors hover:bg-white/35">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">file_download</span> Exportar
            </button>
          </div>
        </header>

        @if (exportOpen()) {
          <app-export-drawer report="tickets" title="tickets" [initial]="exportInitial(vm)"
            [filterKinds]="['statuses', 'priorities', 'technicians', 'categories']"
            [statusOptions]="statusChoices" [priorityOptions]="priorityChoices" (closed)="exportOpen.set(false)" />
        }

        @if (vm.error) {
          <p class="rounded-lg bg-[#FEE2E2] px-4 py-3 text-[13px] text-[#991B1B]" role="alert">{{ vm.error }}</p>
        }

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5">
          @for (card of metrics; track card.label) {
            <button type="button" (click)="filterStatus(card.status)"
              class="flex min-h-[104px] items-center gap-4 rounded-2xl border bg-white px-5 py-4 text-left shadow-sm transition-all hover:border-[#457b9d] hover:shadow-md"
              [class]="vm.filters.status === card.status ? 'border-[#457b9d] ring-1 ring-[#457b9d]/30' : 'border-[#E2E8F0]'">
              <span class="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl" [class]="card.tone">
                <span class="material-symbols-outlined text-[24px]">{{ card.icon }}</span>
              </span>
              <div class="min-w-0">
                <span class="block text-[12px] font-bold uppercase tracking-wider text-[#64748B]">{{ card.label }}</span>
                <span class="block text-[30px] font-extrabold leading-tight text-[#0b1f3a]">{{ card.status ? (vm.counts[card.status] ?? 0) : vm.all.length }}</span>
                <span class="block truncate text-[12px] text-[#64748B]">{{ card.hint }}</span>
              </div>
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

        <section class="space-y-3 rounded-2xl border border-[#E2E8F0] bg-white p-5 shadow-sm">
          <div class="grid grid-cols-1 items-center gap-3 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_auto]">
            <div class="relative">
              <span class="material-symbols-outlined pointer-events-none absolute left-3 top-2.5 text-[20px] text-[#94A3B8]">search</span>
              <input #searchInput type="search" [value]="initialSearch" (input)="onSearch($any($event.target).value)" aria-label="Buscar tickets"
                placeholder="Buscar por número, título o descripción…" class="h-10 pl-10" [class]="field" maxlength="100" />
            </div>
            <select (change)="setFilter({ status: $any($event.target).value })" aria-label="Estado" class="h-10" [class]="field">
              <option value="">Estado: Todos</option>
              @for (option of statuses; track option) {
                <option [value]="option" [selected]="option === vm.filters.status">{{ statusLabel(option) }}</option>
              }
            </select>
            <select (change)="setFilter({ priority: $any($event.target).value })" aria-label="Prioridad" class="h-10" [class]="field">
              <option value="">Prioridad: Todas</option>
              @for (option of priorities; track option) {
                <option [value]="option" [selected]="option === vm.filters.priority">{{ priorityLabel(option) }}</option>
              }
            </select>
            <button type="button" (click)="clearFilters()" [disabled]="!vm.hasFilters" title="Limpiar todos los filtros" aria-label="Limpiar filtros"
              class="flex h-10 w-10 items-center justify-center justify-self-end rounded-lg border border-[#CED4DA] bg-[#F7FAFC] !text-[#64748B] transition-colors hover:bg-[#E9EEF5] disabled:opacity-40 sm:col-span-2 lg:col-span-1">
              <span class="material-symbols-outlined text-[18px]">filter_alt_off</span>
            </button>
          </div>
          <app-date-range-filter [inline]="true" label="Fecha de creación" [from]="vm.filters.dateFrom" [to]="vm.filters.dateTo"
            (rangeChange)="setFilter({ dateFrom: $event.from, dateTo: $event.to })" />
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

        <div class="min-w-0 space-y-4">
        <div class="flex items-center justify-between gap-3">
            <div>
              <h2 class="text-[17px] font-bold text-[#0b1f3a]">Tickets recientes</h2>
              <p class="text-[12px] text-[#64748B]">Últimos tickets registrados en el sistema</p>
            </div>
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
          <div class="flex flex-col items-center justify-center gap-2 rounded-2xl border border-[#E2E8F0] bg-white px-6 py-16 text-center shadow-sm">
            @if (vm.hasFilters) {
              <span class="mb-2 flex h-20 w-20 items-center justify-center rounded-full bg-[#EEF4FA] text-[#457b9d]">
                <span class="material-symbols-outlined text-[44px]">search_off</span>
              </span>
            } @else {
              <svg class="mb-2 h-24 w-24" viewBox="0 0 96 96" fill="none" aria-hidden="true">
                <path d="M24 20h28l16 16v34a6 6 0 0 1-6 6H24a6 6 0 0 1-6-6V26a6 6 0 0 1 6-6Z" fill="#fff" stroke="#5C6B7F" stroke-width="3.5" stroke-linejoin="round"/>
                <path d="M52 20v11a5 5 0 0 0 5 5h11" stroke="#5C6B7F" stroke-width="3.5" stroke-linejoin="round" stroke-linecap="round"/>
                <path d="M28 46h24M28 56h24M28 66h14" stroke="#3B82F6" stroke-width="3.5" stroke-linecap="round"/>
                <path d="M74 6v14M67 13h14" stroke="#2F6FED" stroke-width="3.5" stroke-linecap="round"/>
                <circle cx="68" cy="72" r="14" fill="#2F6FED" stroke="#fff" stroke-width="3"/>
                <path d="M68 65v14M61 72h14" stroke="#fff" stroke-width="3.5" stroke-linecap="round"/>
              </svg>
            }
            <p class="text-[16px] font-bold text-[#0b1f3a]">
              {{ vm.hasFilters ? 'Ningún ticket coincide con los filtros actuales.' : 'Aún no hay tickets registrados.' }}
            </p>
            <p class="max-w-sm text-[13px] text-[#64748B]">
              {{ vm.hasFilters ? 'Prueba a cambiar o limpiar los filtros para ver más resultados.' : 'Los tickets aparecerán aquí una vez que se creen en el sistema.' }}
            </p>
          </div>
        } @else if (view() === 'table') {
          <div class="overflow-hidden rounded-xl border border-[#E2E8F0] bg-white">
            <div class="overflow-x-auto">
              <table class="w-full border-collapse text-left">
                <thead>
                  <tr class="border-b border-[#E9EEF5] bg-[#EEF4FA]/70 text-[11px] font-bold uppercase tracking-wider text-[#64748B]">
                    <th class="px-4 py-3">Ticket</th>
                    <th class="w-[34%] px-4 py-3">Título</th>
                    <th class="w-[22%] px-4 py-3">Equipo</th>
                    <th class="px-3 py-3 text-center">Prioridad</th>
                    <th class="px-3 py-3 text-center">Estado</th>
                    <th class="px-4 py-3">Creado</th>
                    <th class="px-3 py-3 text-right"><span class="sr-only">Ver</span></th>
                  </tr>
                </thead>
                <tbody>
                  @for (item of vm.items; track item.id) {
                    <tr tabindex="0" (click)="openTicket(item.id)" (keydown.enter)="openTicket(item.id)" class="cursor-pointer border-b border-[#E9EEF5]/70 transition-colors hover:bg-[#EEF4FA]/60">
                      <td class="whitespace-nowrap px-4 py-3">
                        <span class="rounded border border-[#CED4DA] bg-[#EEF4FA]/70 px-2 py-1 font-mono text-[12px] font-bold text-[#3E5C76]">{{ item.ticket_number }}</span>
                      </td>
                      <td class="px-4 py-3">
                        <p class="line-clamp-2 break-words text-[14px] font-bold" [attr.title]="item.title">{{ item.title }}</p>
                        @if (unassigned(item.status)) {
                          <span class="mt-0.5 inline-flex items-center gap-1 text-[11px] font-semibold text-[#92400E]">
                            <span class="material-symbols-outlined text-[13px]">person_off</span> Sin asignar
                          </span>
                        }
                      </td>
                      <td class="px-4 py-3">
                        <span class="inline-flex max-w-full items-center gap-2 rounded-lg border border-[#CED4DA]/60 bg-[#EEF4FA]/60 px-2.5 py-1 text-[12px] font-medium" [attr.title]="equipmentLabel(vm, item.equipment_id)">
                          <span class="material-symbols-outlined text-[16px] text-[#457b9d]">devices</span>
                          <span class="line-clamp-2 break-words">{{ equipmentLabel(vm, item.equipment_id) }}</span>
                        </span>
                      </td>
                      <td class="whitespace-nowrap px-3 py-3 text-center"><app-ticket-chip kind="priority" [value]="item.priority" /></td>
                      <td class="whitespace-nowrap px-3 py-3 text-center"><app-ticket-chip kind="status" [value]="item.status" /></td>
                      <td class="px-4 py-3 text-[12px] text-[#64748B]">{{ item.created_at | date: 'dd/MM/yyyy HH:mm' }}</td>
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
          <app-kanban-board ariaLabel="Tablero de tickets" [columns]="boardColumns(vm)" [key]="ticketKey" [label]="ticketLabel"
            [validTargets]="validTargets" [handler]="moveTicket" [invalidMessage]="invalidMove" emptyText="Sin tickets" [minColumnWidth]="150">
            <ng-template appKanbanCard let-item>
              <article role="button" tabindex="0" (click)="openTicket(item.id)" (keydown.enter)="openTicket(item.id)"
                class="cursor-pointer space-y-2 rounded-xl border border-[#E2E8F0] bg-white p-3 pr-9 shadow-sm transition-all hover:border-[#457b9d] hover:shadow-md">
                <div class="flex flex-wrap items-center justify-between gap-1">
                  <span class="font-mono text-[12px] font-bold text-[#3E5C76]">{{ item.ticket_number }}</span>
                  <app-ticket-chip kind="priority" [value]="item.priority" />
                </div>
                <p class="line-clamp-2 break-words text-[13px] font-bold" [attr.title]="item.title">{{ item.title }}</p>
                <p class="flex items-start gap-1 text-[11px] text-[#64748B]">
                  <span class="material-symbols-outlined text-[14px] text-[#457b9d]" aria-hidden="true">devices</span>
                  <span class="line-clamp-2 break-words">{{ equipmentLabel(vm, item.equipment_id) }}</span>
                </p>
                <p class="border-t border-[#E9EEF5] pt-2 text-right text-[11px] text-[#64748B]">{{ item.created_at | date: 'dd/MM/yyyy' }}</p>
              </article>
            </ng-template>
          </app-kanban-board>
        }

        <app-pagination noun="tickets" [page]="vm.page + 1" [pageSize]="vm.pageSize" [hasNext]="vm.hasNext" [loading]="vm.loading" (pageChange)="page($event - 1)" />
        </div>

        <aside class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <section class="rounded-2xl border border-[#E2E8F0] bg-white p-5 shadow-sm">
            <h3 class="flex items-center gap-2 text-[14px] font-bold text-[#0b1f3a]">
              <span class="material-symbols-outlined text-[18px] text-[#457b9d]">bar_chart</span> Resumen de tickets
            </h3>
            <div class="mt-4 flex items-center gap-5">
              <div class="relative h-[112px] w-[112px] shrink-0 rounded-full" [style.background]="donut(vm)">
                <div class="absolute inset-[14px] flex flex-col items-center justify-center rounded-full bg-white">
                  <span class="text-[22px] font-extrabold leading-none text-[#0b1f3a]">{{ vm.all.length }}</span>
                  <span class="mt-0.5 text-[11px] text-[#64748B]">Total</span>
                </div>
              </div>
              <ul class="flex-1 space-y-2 text-[12px]">
                @for (segment of segments; track segment.status) {
                  <li class="flex items-center justify-between gap-2">
                    <span class="flex items-center gap-2 text-[#334155]">
                      <span class="h-2.5 w-2.5 rounded-full" [style.background]="segment.color"></span>{{ segment.label }}
                    </span>
                    <span class="font-semibold text-[#0b1f3a]">{{ vm.counts[segment.status] ?? 0 }}</span>
                  </li>
                }
              </ul>
            </div>
          </section>

          <section class="rounded-2xl border border-[#E2E8F0] bg-white p-5 shadow-sm">
            <h3 class="flex items-center gap-2 text-[14px] font-bold text-[#0b1f3a]">
              <span class="material-symbols-outlined text-[18px] text-[#457b9d]">history</span> Actividad reciente
            </h3>
            @if (recent(vm).length === 0) {
              <div class="flex flex-col items-center gap-2 py-6 text-center">
                <span class="flex h-12 w-12 items-center justify-center rounded-full bg-[#EEF4FA] text-[#457b9d]">
                  <span class="material-symbols-outlined text-[24px]">description</span>
                </span>
                <p class="text-[12px] font-semibold text-[#334155]">No hay actividad reciente</p>
                <p class="max-w-[220px] text-[12px] text-[#64748B]">La actividad aparecerá aquí cuando se generen nuevos tickets.</p>
              </div>
            } @else {
              <ul class="mt-3 space-y-3">
                @for (item of recent(vm); track item.id) {
                  <li class="flex items-start gap-3">
                    <span class="mt-1 h-2 w-2 shrink-0 rounded-full bg-[#457b9d]"></span>
                    <button type="button" (click)="openTicket(item.id)" class="min-w-0 text-left">
                      <span class="block truncate text-[12px] font-semibold text-[#1E293B]">{{ item.ticket_number }} · {{ item.title }}</span>
                      <span class="block text-[11px] text-[#64748B]">{{ item.created_at | date: 'dd/MM/yyyy HH:mm' }}</span>
                    </button>
                  </li>
                }
              </ul>
            }
          </section>
        </aside>

        @if (flow.dialog(); as d) {
          <app-transition-dialog [title]="d.title" [subtitle]="d.subtitle" [confirmLabel]="d.confirm" [requires]="d.requires"
            [categories]="categoryChoices()" [priorities]="priorityChoices" [technicians]="technicians()" [initial]="d.initial" [busy]="flow.busy()"
            (confirmed)="d.answer($event)" (cancelled)="d.answer(null)" />
        }
        <app-toast-host />

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
                    <option value="" disabled [selected]="!preselectedEquipmentId">Selecciona un equipo del inventario…</option>
                    @for (item of vm.equipment; track item.id) {
                      <option [value]="item.id" [selected]="item.id === preselectedEquipmentId">{{ item.asset_tag }} · {{ item.brand }} {{ item.model }}</option>
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
                    class="rounded-lg bg-[#0b1f3a] px-5 py-2.5 text-[14px] font-extrabold tracking-wide !text-[#FFB703] shadow-sm hover:bg-[#14365f] disabled:opacity-50">
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
  private readonly permissions = inject(PermissionsService);
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

  /** Enlaces de otras pantallas: `?status=` filtra la lista y `?equipmentId=` abre «Nuevo ticket» con ese equipo. */
  private readonly query = this.route.snapshot.queryParamMap;
  readonly preselectedEquipmentId = Number(this.query.get('equipmentId')) || null;

  readonly view = signal<'table' | 'kanban'>('table');
  readonly attentionOpen = signal(true);
  readonly createOpen = signal(false);
  readonly exportOpen = signal(false);
  readonly statusChoices: ChoiceOption[] = REQUEST_STATUSES.map((value) => ({ value, label: statusMeta(value).label }));
  readonly priorityChoices: ChoiceOption[] = PRIORITIES.map((value) => ({ value, label: priorityMeta(value).label }));
  readonly titleLength = signal(0);
  readonly createError = signal('');
  readonly canCreate = signal(false);
  readonly canManage = signal(false);
  /** El ticket abierto vive en `?ticket=ID`, así el enlace al detalle se puede compartir. */
  readonly selectedId = toSignal(
    this.route.queryParamMap.pipe(map((params) => Number(params.get('ticket')) || null)),
    { initialValue: null },
  );

  private readonly workflowApi = inject(WorkflowService);
  private readonly transitions = inject(TicketTransitionService);
  private readonly techniciansApi = inject(TechniciansService);
  private readonly queueApi = inject(QueueService);
  private readonly toasts = inject(ToastService);

  /** Los estados y sus pasos válidos, tal como los define el servidor. */
  readonly workflow = signal<WorkflowState[]>([]);
  readonly technicians = signal<Technician[]>([]);
  readonly categoryChoices = signal<Choice[]>([]);
  /** Diálogo de los pasos que piden datos (el mismo flujo que en Solicitudes pendientes). */
  readonly flow = new TransitionFlow();
  private columnsCache: { items: MaintenanceListItem[]; workflow: WorkflowState[]; columns: KanbanColumn<MaintenanceListItem>[] } | null = null;

  readonly ticketKey = (item: MaintenanceListItem): number => item.id;
  readonly ticketLabel = (item: MaintenanceListItem): string => item.ticket_number;

  /** Columnas del tablero: una por estado del servidor, con los tickets de la página. Se reutiliza el arreglo si nada cambió. */
  boardColumns(vm: TicketsView): KanbanColumn<MaintenanceListItem>[] {
    const workflow = this.workflow();
    if (this.columnsCache?.items === vm.items && this.columnsCache.workflow === workflow) {
      return this.columnsCache.columns;
    }
    const columns = workflow.map((state) => ({
      id: state.status,
      title: statusMeta(state.status).label,
      dot: statusMeta(state.status).dot,
      items: vm.items.filter((item) => item.status === state.status),
    }));
    this.columnsCache = { items: vm.items, workflow, columns };
    return columns;
  }

  readonly validTargets = (item: MaintenanceListItem, from: string): string[] => allowedTargets(item, from, this.workflow());

  readonly invalidMove = (move: KanbanMove<MaintenanceListItem>, allowed: string[]): string => {
    const blocked = permissionBlock(move.item, move.to, this.workflow(), (status) => statusMeta(status).label);
    if (blocked) {
      return blocked;
    }
    const label = (status: string): string => `«${statusMeta(status).label}»`;
    const next = allowed.length ? ` Desde ahí solo puede ir a ${allowed.map(label).join(', ')}.` : ' Ese estado es final.';
    return `No se puede pasar ${move.item.ticket_number} de ${label(move.from)} a ${label(move.to)}.${next}`;
  };

  /** Paso pedido desde el tablero: si el estado destino exige datos se piden antes; el servidor valida y, si rechaza, la tarjeta vuelve. */
  readonly moveTicket = (move: KanbanMove<MaintenanceListItem>): Observable<KanbanOutcome> => {
    const requires = this.workflow().find((state) => state.status === move.to)?.requires ?? [];
    return this.flow.run(
      {
        to: move.to,
        requires,
        subtitle: `${move.item.ticket_number} pasará a «${statusMeta(move.to).label}».`,
        initial: { category: move.item.category ?? '', priority: move.item.priority },
      },
      (data) => this.execute(move, data),
    );
  };

  private execute(move: KanbanMove<MaintenanceListItem>, data: TransitionData): Observable<KanbanOutcome> {
    return this.transitions.move(move.item.id, move.from, move.to, data).pipe(
      tap(() => {
        this.toasts.success(`${move.item.ticket_number} pasó a «${statusMeta(move.to).label}».`);
        this.store.refresh();
      }),
      map((): KanbanOutcome => ({ ok: true })),
      catchError((error) => of<KanbanOutcome>({ ok: false, message: apiErrorMessage(error, 'No se pudo cambiar el estado del ticket.') })),
    );
  }

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
    this.workflowApi.states().subscribe({ next: (states) => this.workflow.set(states), error: () => this.workflow.set([]) });
    this.techniciansApi.list().subscribe({ next: (list) => this.technicians.set(list), error: () => this.technicians.set([]) });
    this.queueApi.categories().subscribe({ next: (list) => this.categoryChoices.set(list.map((c) => ({ value: c.code, label: c.name }))), error: () => this.categoryChoices.set([]) });
    const status = this.query.get('status') ?? '';
    if (this.statuses.some((item) => item === status)) {
      this.store.setFilters({ status });
    }
    this.canCreate.set(await this.permissions.can('solicitudes:crear'));
    if (this.preselectedEquipmentId && this.canCreate()) {
      this.createOpen.set(true);
    }
    this.canManage.set(await this.permissions.can('tickets:cambiar_estado'));
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

  readonly segments = [
    { status: 'submitted', label: 'Enviados', color: '#3B82F6' },
    { status: 'in_progress', label: 'En proceso', color: '#84A03A' },
    { status: 'resolved', label: 'Resueltos', color: '#22C55E' },
    { status: 'closed', label: 'Cerrados', color: '#8B5CF6' },
  ];

  donut(vm: TicketsView): string {
    const total = this.segments.reduce((sum, s) => sum + (vm.counts[s.status] ?? 0), 0);
    if (total === 0) {
      return '#E2E8F0';
    }
    let start = 0;
    const stops = this.segments
      .filter((s) => (vm.counts[s.status] ?? 0) > 0)
      .map((s) => {
        const end = start + ((vm.counts[s.status] ?? 0) / total) * 100;
        const stop = `${s.color} ${start}% ${end}%`;
        start = end;
        return stop;
      });
    return `conic-gradient(${stops.join(', ')})`;
  }

  recent(vm: TicketsView): MaintenanceListItem[] {
    return [...vm.all].sort((a, b) => b.created_at.localeCompare(a.created_at)).slice(0, 5);
  }

  equipmentLabel(vm: TicketsView, equipmentId: number): string {
    const equipment = vm.equipmentById.get(equipmentId);
    return equipment ? `${equipment.asset_tag} · ${equipment.brand} ${equipment.model}` : `Equipo #${equipmentId}`;
  }

  /** Los filtros de la pantalla son el punto de partida del panel de exportación. */
  exportInitial(vm: TicketsView): ExportFilterValues {
    const { status, priority, dateFrom, dateTo } = vm.filters;
    return {
      ...EMPTY_EXPORT_FILTERS,
      statuses: status ? [status] : [],
      priorities: priority ? [priority] : [],
      dateFrom,
      dateTo,
    };
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
      hasFilters: !!(search || status || priority || dateFrom || dateTo),
    };
  }
}
