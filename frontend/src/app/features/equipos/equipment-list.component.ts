import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import { EquipmentDetailStore } from '../../core/equipment-detail.store';
import { Attachment, Equipment, ReportFormat } from '../../core/equipment.service';
import { EquipmentFilters, EquipmentStore, EquipmentView, SaveRequest } from '../../core/equipment.store';
import { PermissionsService } from '../../core/permissions.service';
import { SchedulePayload } from '../../core/schedules.service';
import { EquipmentDetailDrawerComponent } from './equipment-detail-drawer.component';
import { EquipmentFormModalComponent } from './equipment-form-modal.component';
import { EquipmentGridComponent } from './equipment-grid.component';
import { PaginationComponent } from '../../shared/pagination.component';
import { EquipmentSummaryCardsComponent } from './equipment-summary-cards.component';
import { EquipmentTableComponent } from './equipment-table.component';
import { EquipmentToolbarComponent } from './equipment-toolbar.component';

interface Abilities {
  manage: boolean;
  exportReports: boolean;
  attach: boolean;
  schedule: boolean;
  createTicket: boolean;
  readMaintenance: boolean;
}

const NO_ABILITIES: Abilities = {
  manage: false,
  exportReports: false,
  attach: false,
  schedule: false,
  createTicket: false,
  readMaintenance: false,
};

/**
 * Smart (container) component de la pantalla de equipos: conversa con los stores y
 * delega el dibujo en componentes tontos. La barra superior de la aplicación (campana
 * de notificaciones y menú de perfil) pertenece al shell y no se toca aquí.
 */
@Component({
  selector: 'app-equipment-list',
  standalone: true,
  imports: [
    AsyncPipe,
    EquipmentDetailDrawerComponent,
    EquipmentFormModalComponent,
    EquipmentGridComponent,
    PaginationComponent,
    EquipmentSummaryCardsComponent,
    EquipmentTableComponent,
    EquipmentToolbarComponent,
  ],
  template: `
    @if (state$ | async; as state) {
      <div class="space-y-6 py-2">
        <header class="flex flex-col justify-between gap-5 rounded-2xl bg-gradient-to-r from-[#0b1f3a] to-[#14365f] px-6 py-6 md:flex-row md:items-center md:px-8">
          <div class="flex items-center gap-5">
            <span class="hidden h-16 w-16 shrink-0 items-center justify-center self-center rounded-2xl border border-white/30 bg-white/10 text-[#ADD7F6] sm:flex">
              <span class="material-symbols-outlined block text-center !text-[34px] !leading-none">devices</span>
            </span>
            <div>
              <h1 class="text-[26px] font-extrabold uppercase leading-tight tracking-tight text-white">Gestión de <span class="text-[#4DB8F0]">Equipos</span></h1>
              <p class="mt-1 max-w-2xl text-[14px] leading-relaxed text-[#CBD5E1]">
                Administra los equipos tecnológicos, consulta sus especificaciones y realiza seguimiento a su ciclo de vida y mantenimiento.
              </p>
            </div>
          </div>
          <div class="flex items-center gap-3">
            @if (abilities().manage) {
              <button type="button" (click)="openCreate()"
                class="flex items-center gap-1.5 rounded-lg border border-white/50 bg-white/25 shadow-[inset_0_1px_0_rgba(255,255,255,0.35)] backdrop-blur-md px-5 py-2.5 text-[13px] font-bold !text-[#FFB703] transition-all hover:bg-white/35 active:scale-95">
                <span class="material-symbols-outlined text-[20px]">add</span>
                <span>Nuevo equipo</span>
              </button>
            }
          </div>
        </header>

        @if (state.error) {
          <p role="alert" class="rounded-xl !border !border-rose-200 bg-rose-50 px-4 py-3 text-sm font-medium text-rose-700">{{ state.error }}</p>
        }
        @if (state.notice && !formOpen()) {
          <p role="status" class="flex items-center justify-between rounded-xl !border !border-amber-200 bg-amber-50 px-4 py-3 text-sm font-medium text-amber-800">
            {{ state.notice }}
            <button type="button" (click)="dismissNotice()" aria-label="Cerrar aviso" class="bg-transparent !text-amber-700 hover:text-amber-900">
              <span class="material-symbols-outlined text-[18px]">close</span>
            </button>
          </p>
        }

        <app-equipment-summary-cards [summary]="state.summary" [statusFilter]="state.filters.status" (filterChange)="setFilters({ status: $event })" />

        <app-equipment-toolbar
          [filters]="state.filters"
          [sort]="state.sort"
          [view]="state.view"
          [types]="state.types"
          [canExport]="abilities().exportReports"
          [exporting]="state.exporting"
          (filtersChange)="setFilters($event)"
          (sortChange)="setSort($event)"
          (viewChange)="setView($event)"
          (filtersReset)="reset()"
          (exportRequested)="export($event)" />

        <section class="flex flex-col overflow-hidden rounded-2xl !border !border-slate-200/90 bg-white shadow-[0_4px_20px_-2px_rgba(13,31,56,0.03)]" aria-label="Listado de equipos">
          @if (state.view === 'table') {
            <app-equipment-table [equipment]="state.items" [loading]="state.loading" [filtered]="isFiltered(state.filters)"
              [canManage]="abilities().manage" (view)="view($event)" (edit)="openEdit($event)" />
          } @else {
            <app-equipment-grid [equipment]="state.items" [loading]="state.loading" [filtered]="isFiltered(state.filters)"
              [canManage]="abilities().manage" (view)="view($event)" (edit)="openEdit($event)" />
          }
          <app-pagination noun="equipos" [filtered]="isFiltered(state.filters)" [page]="state.page" [pageSize]="state.pageSize" [total]="state.total" [loading]="state.loading" (pageChange)="setPage($event)" />
        </section>

        <footer class="flex items-center justify-between !border-t !border-slate-200/80 pb-2 pt-4 text-[11px] text-slate-400">
          <span class="flex items-center gap-2">
            <span class="h-2 w-2 rounded-full !border !border-sky-400" aria-hidden="true"></span>
            <span><strong>Mantix</strong> · Tecnología que mantiene tu productividad</span>
          </span>
        </footer>
      </div>

      @if (formOpen()) {
        <app-equipment-form-modal
          [equipment]="editing()"
          [types]="state.types"
          [locations]="state.locations"
          [saving]="state.saving"
          [error]="state.saveError"
          (closed)="closeForm()"
          (submitted)="save($event)" />
      }

      @if (detail$ | async; as detail) {
        @if (detail.equipment) {
          <app-equipment-detail-drawer
            [state]="detail"
            [locations]="state.locations"
            [canManage]="abilities().manage"
            [canAttach]="abilities().manage && abilities().attach"
            [canSchedule]="abilities().schedule"
            [canCreateTicket]="abilities().createTicket"
            [canReadMaintenance]="abilities().readMaintenance"
            (closed)="closeDetail()"
            (relocated)="relocate($event)"
            (reassigned)="reassign($event)"
            (uploaded)="upload($event)"
            (download)="download($event)"
            (scheduled)="schedule($event)" />
        }
      }
    }
  `,
  host: { class: 'block' },
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentListComponent implements OnInit {
  private readonly store = inject(EquipmentStore);
  private readonly detailStore = inject(EquipmentDetailStore);
  private readonly permissions = inject(PermissionsService);
  private readonly destroyRef = inject(DestroyRef);

  readonly state$ = this.store.state$;
  readonly detail$ = this.detailStore.state$;

  readonly abilities = signal<Abilities>(NO_ABILITIES);
  readonly formOpen = signal(false);
  readonly editing = signal<Equipment | null>(null);

  async ngOnInit(): Promise<void> {
    this.store.saved$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe(() => this.closeForm());
    this.detailStore.changed$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe(() => this.store.refresh());
    this.store.load();
    const can = (code: string) => this.permissions.can(code).catch(() => false);
    const [manage, exportReports, attach, schedule, createTicket, readMaintenance] = await Promise.all([
      can('equipos:editar'),
      can('reportes:exportar'),
      can('equipos:adjuntar'),
      can('mantenimiento:crear'),
      can('solicitudes:crear'),
      can('tickets:ver'),
    ]);
    this.abilities.set({ manage, exportReports, attach, schedule, createTicket, readMaintenance });
  }

  isFiltered(filters: EquipmentFilters): boolean {
    return !!(filters.search || filters.status || filters.typeId || filters.locationId);
  }

  setFilters(partial: Partial<EquipmentFilters>): void {
    this.store.setFilters(partial);
  }

  reset(): void {
    this.store.resetFilters();
  }

  setSort(sort: string): void {
    this.store.setSort(sort);
  }

  setView(view: EquipmentView): void {
    this.store.setView(view);
  }

  setPage(page: number): void {
    this.store.setPage(page);
  }

  export(format: ReportFormat): void {
    this.store.export(format);
  }

  dismissNotice(): void {
    this.store.clearNotice();
  }

  openCreate(): void {
    this.store.clearNotice();
    this.editing.set(null);
    this.formOpen.set(true);
  }

  openEdit(item: Equipment): void {
    this.store.clearNotice();
    this.editing.set(item);
    this.formOpen.set(true);
  }

  closeForm(): void {
    this.formOpen.set(false);
    this.editing.set(null);
  }

  save(request: SaveRequest): void {
    this.store.save(request);
  }

  view(item: Equipment): void {
    this.detailStore.open(item, { readMaintenance: this.abilities().readMaintenance });
  }

  closeDetail(): void {
    this.detailStore.close();
  }

  relocate(locationId: number): void {
    this.detailStore.relocate(locationId);
  }

  reassign(userId: number): void {
    this.detailStore.reassign(userId);
  }

  upload(files: File[]): void {
    this.detailStore.upload(files);
  }

  download(attachment: Attachment): void {
    this.detailStore.download(attachment);
  }

  schedule(payload: SchedulePayload): void {
    this.detailStore.schedule(payload);
  }
}
