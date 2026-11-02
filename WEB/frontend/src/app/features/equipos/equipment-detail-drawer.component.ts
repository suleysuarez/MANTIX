import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  EventEmitter,
  HostListener,
  Input,
  Output,
  ViewChild,
  signal,
} from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { RouterLink } from '@angular/router';

import { DetailState } from '../../core/equipment-detail.store';
import {
  categoryIcon,
  formatDate,
  initials,
  statusBadgeClasses,
  statusDotClasses,
  statusInfo,
  ticketStatusLabel,
  workTypeLabel,
} from '../../core/equipment-status';
import { Attachment, CustodianCandidate, LocationItem } from '../../core/equipment.service';
import { SchedulePayload } from '../../core/schedules.service';
import { CustodianPickerComponent } from './custodian-picker.component';

/** Texto del estado de la garantía respecto a `today` (inyectable para poder probarlo). */
export function warrantyLabel(end: string | null, today = new Date()): { text: string; expired: boolean } | null {
  if (!end) {
    return null;
  }
  const todayText = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
  const expired = end < todayText;
  return { text: `${expired ? 'Vencida el' : 'Vigente hasta'} ${formatDate(end)}`, expired };
}

/** Dumb component: panel lateral con la ficha, el historial y los adjuntos de un equipo. */
@Component({
  selector: 'app-equipment-detail-drawer',
  standalone: true,
  imports: [ReactiveFormsModule, RouterLink, CustodianPickerComponent],
  template: `
    @if (state.equipment; as item) {
      <div class="fixed inset-0 z-50 overflow-hidden" role="dialog" aria-modal="true" aria-labelledby="equipment-drawer-title">
        <div class="fixed inset-0 bg-slate-900/50 backdrop-blur-sm" (click)="closed.emit()" aria-hidden="true"></div>
        <div class="fixed inset-y-0 right-0 flex max-w-full pl-10">
          <div #panel tabindex="-1" class="flex w-screen max-w-md flex-col !border-l !border-slate-200 bg-white shadow-2xl focus:outline-none">
            <header class="!border-b !border-slate-200 bg-slate-50 p-6">
              <div class="mb-3 flex items-center justify-between">
                <span class="rounded bg-sky-100 px-2.5 py-1 font-mono text-xs font-bold text-sky-800">{{ item.asset_tag }}</span>
                <button type="button" (click)="closed.emit()" aria-label="Cerrar detalle"
                  class="bg-transparent flex h-8 w-8 items-center justify-center rounded-lg !text-slate-400 hover:bg-slate-200/60 hover:text-slate-600">
                  <span class="material-symbols-outlined text-[20px]">close</span>
                </button>
              </div>
              <h2 id="equipment-drawer-title" class="flex items-center gap-2 text-xl font-bold text-slate-900">
                <span class="material-symbols-outlined text-[24px] text-sky-700">{{ icon(item.equipment_type.code) }}</span>
                {{ item.brand }} {{ item.model }}
              </h2>
              <div class="mt-1 flex items-center gap-2">
                <span class="text-xs font-medium text-slate-500">{{ item.equipment_type.name }}</span>
                <span class="text-slate-300">•</span>
                <span class="inline-flex items-center gap-1.5 rounded-full !border px-2 py-0.5 text-[10px] font-semibold" [class]="badge(item.status)">
                  <span class="h-1.5 w-1.5 rounded-full" [class]="dot(item.status)"></span>{{ label(item.status) }}
                </span>
              </div>
            </header>

            <div class="flex-1 space-y-6 overflow-y-auto p-6 text-xs">
              @if (state.error) {
                <p role="alert" class="rounded-xl !border !border-rose-200 bg-rose-50 px-3 py-2 font-medium text-rose-700">{{ state.error }}</p>
              }
              @if (state.notice) {
                <p role="status" class="rounded-xl !border !border-emerald-200 bg-emerald-50 px-3 py-2 font-medium text-emerald-700">{{ state.notice }}</p>
              }

              <section class="space-y-3 rounded-2xl !border !border-slate-200/70 bg-slate-50 p-4">
                <h3 class="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-slate-900">
                  <span class="material-symbols-outlined text-[16px] text-sky-600">info</span>Ficha técnica
                </h3>
                <dl class="grid grid-cols-2 gap-x-3 gap-y-3 text-slate-600">
                  <div>
                    <dt class="block text-[10px] font-bold uppercase text-slate-400">Número de serie</dt>
                    <dd class="ml-0 font-mono font-medium text-slate-800">{{ item.serial_number || 'Sin registrar' }}</dd>
                  </div>
                  <div>
                    <dt class="block text-[10px] font-bold uppercase text-slate-400">Ubicación</dt>
                    <dd class="ml-0 flex items-center gap-1 font-medium text-slate-800">
                      {{ item.current_location?.name || 'Sin ubicación' }}
                      @if (canManage) {
                        <button type="button" (click)="relocating.set(!relocating())" class="bg-transparent !text-[11px] !font-semibold !text-sky-600 hover:underline">
                          {{ relocating() ? 'Cancelar' : 'Cambiar' }}
                        </button>
                      }
                    </dd>
                  </div>
                  @if (relocating()) {
                    <div class="col-span-2 flex items-center gap-2">
                      <select aria-label="Nueva ubicación" (change)="destination.set($any($event.target).value)"
                        class="flex-1 rounded-xl !border !border-slate-200 bg-white p-2 text-xs focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-500/20">
                        <option value="">Elegir ubicación…</option>
                        @for (location of locations; track location.id) {
                          <option [value]="location.id" [selected]="location.id === item.current_location?.id">{{ location.name }}</option>
                        }
                      </select>
                      <button type="button" [disabled]="state.busy || !destination()" (click)="relocate()"
                        class="rounded-xl bg-brand-sidebar px-3 py-2 !text-xs !font-bold !text-white disabled:opacity-50">Guardar</button>
                    </div>
                  }
                  <div class="col-span-2">
                    <dt class="block text-[10px] font-bold uppercase text-slate-400">Especificaciones</dt>
                    <dd class="ml-0 font-medium text-slate-800">{{ item.description || 'Sin descripción' }}</dd>
                  </div>
                  <div>
                    <dt class="block text-[10px] font-bold uppercase text-slate-400">Adquisición</dt>
                    <dd class="ml-0 font-medium text-slate-800">
                      {{ date(item.purchase_date) }}
                      @if (item.purchase_cost) { <span class="text-slate-400">· {{ item.purchase_cost }}</span> }
                    </dd>
                  </div>
                  <div>
                    <dt class="block text-[10px] font-bold uppercase text-slate-400">Garantía</dt>
                    <dd class="ml-0 font-medium" [class]="warranty(item.warranty_end_date)?.expired ? 'text-rose-600' : 'text-slate-800'">
                      {{ warranty(item.warranty_end_date)?.text || 'Sin garantía registrada' }}
                    </dd>
                  </div>
                </dl>
              </section>

              <section class="flex items-center justify-between rounded-2xl !border !border-slate-200/80 p-4" aria-label="Custodio">
                <div class="flex min-w-0 items-center gap-3">
                  <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-slate-200 text-xs font-bold text-slate-700">
                    {{ item.current_custodian ? initialsOf(item.current_custodian.full_name) : '–' }}
                  </span>
                  <div class="min-w-0">
                    <span class="block text-[10px] font-bold uppercase text-slate-400">Custodio asignado</span>
                    <span class="block truncate font-semibold text-slate-900">{{ item.current_custodian?.full_name || 'Sin custodio asignado' }}</span>
                    @if (item.current_custodian) {
                      <span class="block truncate text-[11px] text-slate-500">{{ item.current_custodian.email }}</span>
                    }
                  </div>
                </div>
                @if (canManage) {
                  <button type="button" (click)="reassigning.set(!reassigning())"
                    class="bg-transparent rounded-lg px-2.5 py-1 !text-[11px] !font-semibold !text-sky-600 transition-colors hover:bg-sky-50">
                    {{ reassigning() ? 'Cancelar' : item.current_custodian ? 'Reasignar' : 'Asignar' }}
                  </button>
                }
              </section>
              @if (reassigning()) {
                <div class="-mt-3 space-y-2">
                  <app-custodian-picker (picked)="candidate.set($event)" />
                  <button type="button" [disabled]="state.busy || !candidate()" (click)="reassign()"
                    class="rounded-xl bg-brand-sidebar px-3 py-2 !text-xs !font-bold !text-white disabled:opacity-50">Confirmar asignación</button>
                </div>
              }

              <section>
                <h3 class="mb-3 text-xs font-bold uppercase tracking-wider text-slate-900">
                  Historial ({{ state.tickets.length + 1 }} {{ state.tickets.length === 0 ? 'evento' : 'eventos' }})
                </h3>
                @if (item.last_maintenance; as last) {
                  <p class="mb-3 rounded-xl bg-sky-50 px-3 py-2 text-[11px] text-sky-800">
                    Último trabajo: <strong>{{ workType(last.work_type) }}</strong> el {{ date(last.performed_at) }} por {{ last.technician_name }} · {{ last.result }}
                  </p>
                }
                @if (state.loading) {
                  <div class="h-16 animate-pulse rounded-xl bg-slate-100" aria-hidden="true"></div>
                } @else {
                  <ol class="ml-2 space-y-4 !border-l-2 !border-slate-200 pl-3">
                    @for (ticket of state.tickets; track ticket.id; let first = $first) {
                      <li class="relative">
                        <span class="absolute -left-[19px] top-1 h-3 w-3 rounded-full ring-4 ring-white" [class]="first ? 'bg-sky-500' : 'bg-slate-300'"></span>
                        <span class="block text-[10px] font-bold text-slate-400">{{ date(ticket.created_at) }} · {{ ticketStatus(ticket.status) }}</span>
                        <a routerLink="/tickets" [queryParams]="{ ticket: ticket.id }" class="mt-0.5 block font-semibold text-slate-800 hover:text-sky-700">{{ ticket.title }}</a>
                        <span class="text-[11px] text-slate-500">{{ ticket.ticket_number }}</span>
                      </li>
                    }
                    <li class="relative">
                      <span class="absolute -left-[19px] top-1 h-3 w-3 rounded-full bg-emerald-500 ring-4 ring-white"></span>
                      <span class="block text-[10px] font-bold text-slate-400">{{ date(item.created_at) }} · Creación</span>
                      <span class="mt-0.5 block font-semibold text-slate-800">Equipo registrado en el inventario</span>
                      <span class="text-[11px] text-slate-500">{{ item.asset_tag }}</span>
                    </li>
                  </ol>
                  @if (state.tickets.length === 0) {
                    <p class="mt-3 text-slate-400">{{ canReadMaintenance ? 'Este equipo aún no tiene tickets.' : 'No tienes permiso para ver los tickets de este equipo.' }}</p>
                  }
                }
              </section>

              @if (canReadMaintenance && state.schedules.length > 0) {
                <section>
                  <h3 class="mb-2 text-xs font-bold uppercase tracking-wider text-slate-900">Próximos mantenimientos</h3>
                  <ul class="m-0 list-none p-0 space-y-2">
                    @for (plan of state.schedules; track plan.id) {
                      <li class="flex items-center justify-between rounded-xl !border !border-slate-200/70 bg-slate-50/50 p-3">
                        <span>
                          <span class="block font-semibold text-slate-800">{{ plan.title }}</span>
                          <span class="text-[11px] text-slate-500">Cada {{ plan.interval_days }} días · {{ plan.technician?.full_name || 'Sin técnico fijo' }}</span>
                        </span>
                        <span class="rounded-full bg-amber-50 px-2 py-0.5 text-[11px] font-semibold text-amber-700">{{ date(plan.next_due_at) }}</span>
                      </li>
                    }
                  </ul>
                </section>
              }

              <section>
                <div class="mb-2 flex items-center justify-between">
                  <h3 class="text-xs font-bold uppercase tracking-wider text-slate-900">Adjuntos ({{ state.attachments.length }})</h3>
                  @if (canAttach) {
                    <input #upload type="file" multiple class="hidden" accept=".pdf,.png,.jpg,.jpeg,.txt"
                      (change)="uploaded.emit(toArray(upload.files)); upload.value = ''" />
                    <button type="button" (click)="upload.click()" [disabled]="state.busy"
                      class="bg-transparent flex items-center gap-1 !text-[11px] !font-semibold !text-sky-600 hover:underline disabled:opacity-50">
                      <span class="material-symbols-outlined text-[16px]">attach_file</span>Adjuntar
                    </button>
                  }
                </div>
                @if (state.attachments.length === 0) {
                  <p class="text-slate-400">Sin archivos adjuntos.</p>
                } @else {
                  <ul class="m-0 list-none p-0 space-y-1.5">
                    @for (file of state.attachments; track file.id) {
                      <li>
                        <button type="button" (click)="download.emit(file)"
                          class="flex w-full items-center justify-between rounded-lg !border !border-slate-200 bg-white px-3 py-2 text-left hover:bg-slate-50">
                          <span class="truncate font-medium text-slate-700">{{ file.file_name }}</span>
                          <span class="ml-3 flex shrink-0 items-center gap-1 text-slate-400">
                            {{ size(file) }}<span class="material-symbols-outlined text-[16px]">download</span>
                          </span>
                        </button>
                      </li>
                    }
                  </ul>
                }
              </section>
            </div>

            @if (scheduling()) {
              <form [formGroup]="plan" (ngSubmit)="submitPlan()" class="space-y-3 !border-t !border-slate-200 bg-white p-4 text-xs" novalidate>
                <h3 class="font-bold uppercase tracking-wider text-slate-900">Programar mantenimiento preventivo</h3>
                <input formControlName="title" aria-label="Título del plan" placeholder="Título"
                  class="w-full rounded-xl !border !border-slate-200 p-2.5 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-500/20" />
                <div class="grid grid-cols-3 gap-2">
                  <label class="grid gap-1 font-semibold text-slate-600">Primera fecha
                    <input type="date" formControlName="first_due" class="rounded-xl !border !border-slate-200 p-2 font-normal" /></label>
                  <label class="grid gap-1 font-semibold text-slate-600">Cada (días)
                    <input type="number" min="1" max="3650" formControlName="interval_days" class="rounded-xl !border !border-slate-200 p-2 font-normal" /></label>
                  <label class="grid gap-1 font-semibold text-slate-600">Avisar (días antes)
                    <input type="number" min="0" max="365" formControlName="remind_days_before" class="rounded-xl !border !border-slate-200 p-2 font-normal" /></label>
                </div>
                @if (plan.invalid && plan.touched) {
                  <p role="alert" class="font-medium text-rose-600">Completa título y fecha; el aviso no puede exceder el intervalo.</p>
                }
                <button type="submit" [disabled]="state.busy"
                  class="rounded-xl bg-brand-sidebar px-4 py-2 !text-xs !font-bold !text-white disabled:opacity-50">Programar</button>
              </form>
            }

            @if (canSchedule || canCreateTicket) {
              <footer class="grid grid-cols-2 gap-3 !border-t !border-slate-200 bg-slate-50 p-4">
                @if (canSchedule) {
                  <button type="button" (click)="scheduling.set(!scheduling())" [attr.aria-expanded]="scheduling()"
                    class="flex items-center justify-center gap-1.5 rounded-xl !border !border-slate-200 bg-white px-3 py-2.5 !text-xs !font-bold !text-slate-700 shadow-sm transition-colors hover:bg-slate-100"
                    [class.col-span-2]="!canCreateTicket">
                    <span class="material-symbols-outlined text-[18px] text-brand-mustard">event_repeat</span>Programar mantenimiento
                  </button>
                }
                @if (canCreateTicket) {
                  <a routerLink="/tickets" [queryParams]="{ equipmentId: item.id }"
                    class="flex items-center justify-center gap-1.5 rounded-xl bg-brand-sidebar px-3 py-2.5 text-xs font-bold !text-white shadow-sm transition-colors hover:bg-slate-900"
                    [class.col-span-2]="!canSchedule">
                    <span class="material-symbols-outlined text-[18px] text-brand-accentSky">confirmation_number</span>Crear ticket
                  </a>
                }
              </footer>
            }
          </div>
        </div>
      </div>
    }
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentDetailDrawerComponent implements AfterViewInit {
  @Input({ required: true }) state!: DetailState;
  @Input() locations: readonly LocationItem[] = [];
  @Input() canManage = false;
  @Input() canAttach = false;
  @Input() canSchedule = false;
  @Input() canCreateTicket = false;
  @Input() canReadMaintenance = false;

  @Output() readonly closed = new EventEmitter<void>();
  @Output() readonly relocated = new EventEmitter<number>();
  @Output() readonly reassigned = new EventEmitter<number>();
  @Output() readonly uploaded = new EventEmitter<File[]>();
  @Output() readonly download = new EventEmitter<Attachment>();
  @Output() readonly scheduled = new EventEmitter<SchedulePayload>();

  @ViewChild('panel') private panel?: ElementRef<HTMLElement>;

  readonly relocating = signal(false);
  readonly reassigning = signal(false);
  readonly scheduling = signal(false);
  readonly candidate = signal<CustodianCandidate | null>(null);
  /** Ubicación elegida en el selector del panel (cadena vacía = ninguna). */
  readonly destination = signal('');

  readonly plan = new FormGroup({
    title: new FormControl('Mantenimiento preventivo', { nonNullable: true, validators: [Validators.required, Validators.maxLength(200)] }),
    first_due: new FormControl('', { nonNullable: true, validators: [Validators.required] }),
    interval_days: new FormControl(90, { nonNullable: true, validators: [Validators.required, Validators.min(1), Validators.max(3650)] }),
    remind_days_before: new FormControl(3, { nonNullable: true, validators: [Validators.required, Validators.min(0), Validators.max(365)] }),
  });

  ngAfterViewInit(): void {
    this.panel?.nativeElement.focus();
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closed.emit();
  }

  icon(code: string): string {
    return categoryIcon(code);
  }

  label(status: string): string {
    return statusInfo(status).label;
  }

  badge(status: string): string {
    return statusBadgeClasses(status);
  }

  dot(status: string): string {
    return statusDotClasses(status);
  }

  date(value: string | null): string {
    return formatDate(value);
  }

  initialsOf(name: string): string {
    return initials(name);
  }

  workType(value: string): string {
    return workTypeLabel(value);
  }

  ticketStatus(value: string): string {
    return ticketStatusLabel(value);
  }

  warranty(end: string | null) {
    return warrantyLabel(end);
  }

  size(file: Attachment): string {
    return file.file_size >= 1024 * 1024
      ? `${(file.file_size / (1024 * 1024)).toFixed(1)} MB`
      : `${Math.max(1, Math.round(file.file_size / 1024))} KB`;
  }

  toArray(list: FileList | null): File[] {
    return list ? Array.from(list) : [];
  }

  relocate(): void {
    const value = this.destination();
    if (value) {
      this.relocated.emit(Number(value));
      this.relocating.set(false);
      this.destination.set('');
    }
  }

  reassign(): void {
    const user = this.candidate();
    if (user) {
      this.reassigned.emit(user.id);
      this.reassigning.set(false);
      this.candidate.set(null);
    }
  }

  submitPlan(): void {
    this.plan.markAllAsTouched();
    const equipment = this.state.equipment;
    const value = this.plan.getRawValue();
    if (this.plan.invalid || !equipment || value.remind_days_before > value.interval_days) {
      return;
    }
    this.scheduled.emit({
      equipment_id: equipment.id,
      title: value.title.trim(),
      description: null,
      interval_days: value.interval_days,
      remind_days_before: value.remind_days_before,
      first_due_at: new Date(`${value.first_due}T09:00:00`).toISOString(),
    });
    this.scheduling.set(false);
  }
}
