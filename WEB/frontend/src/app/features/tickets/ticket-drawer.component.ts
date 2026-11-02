import { AsyncPipe, CurrencyPipe, DatePipe, NgTemplateOutlet } from '@angular/common';
import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  HostListener,
  OnChanges,
  OnInit,
  inject,
  input,
  output,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import { MaintenanceDetailState, MaintenanceDetailStore } from '../../core/maintenance-detail.store';
import { WORK_TYPES } from '../../core/maintenance.service';
import { TicketChipComponent } from './ticket-chip.component';
import {
  DEFAULT_TRANSITION_STYLE,
  TRANSITION_LABELS,
  TRANSITION_STYLES,
  WORK_TYPE_LABELS,
  initials,
  statusMeta,
} from './ticket-ui';

type Dialog = 'transition' | 'assign' | 'record';

const MAX_COST = 9_999_999_999.99;

const FIELD =
  'w-full rounded-lg border border-[#CED4DA] bg-[#F7FAFC] px-3 py-2 text-[13px] text-[#1E293B] focus:border-[#457b9d] focus:outline-none';

/** `YYYY-MM-DDTHH:mm` en hora local, el formato que espera `<input type="datetime-local">`. */
function localInputValue(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/**
 * Panel lateral con el detalle de un ticket: ficha, técnico, historial de trabajos y línea de
 * tiempo. Las acciones (cambiar estado, asignar, registrar trabajo) solo se ofrecen con
 * `maintenance.manage`; los estados disponibles los dicta el backend (`allowed_next_statuses`).
 */
@Component({
  selector: 'app-ticket-drawer',
  standalone: true,
  imports: [AsyncPipe, CurrencyPipe, DatePipe, NgTemplateOutlet, TicketChipComponent],
  template: `
    <div class="fixed inset-0 z-[60] flex justify-end">
      <div class="absolute inset-0 bg-[#0b1f3a]/45" (click)="closed.emit()" aria-hidden="true"></div>
      <section
        role="dialog" aria-modal="true" aria-label="Detalle del ticket"
        class="relative flex h-full w-full max-w-2xl flex-col overflow-hidden border-l border-[#CED4DA] bg-white shadow-2xl">
        @if (state$ | async; as state) {
          @if (state.loading) {
            <div class="flex flex-1 items-center justify-center text-[14px] text-[#64748B]">Cargando ticket…</div>
          } @else {
          @if (state.request; as request) {
            <header class="flex shrink-0 items-center justify-between gap-4 bg-[#0b1f3a] px-6 py-4 text-white">
              <div class="flex min-w-0 items-center gap-4">
                <span class="shrink-0 rounded-lg border border-[#ADD7F6]/30 bg-white/10 px-2.5 py-1.5 font-mono text-[13px] font-bold text-[#ADD7F6]">{{ request.ticket_number }}</span>
                <div class="min-w-0">
                  <h2 class="truncate text-[17px] font-bold">{{ request.title }}</h2>
                  <p class="truncate text-[12px] text-[#CED4DA]">
                    <span class="font-semibold text-[#ADD7F6]">{{ request.equipment.asset_tag }} · {{ request.equipment.brand }} {{ request.equipment.model }}</span>
                    · {{ request.created_at | date: 'dd/MM/yyyy HH:mm' }}
                  </p>
                </div>
              </div>
              <button type="button" (click)="closed.emit()" aria-label="Cerrar panel"
                class="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg !text-[#CED4DA] transition-colors hover:bg-white/15 hover:!text-white">
                <span class="material-symbols-outlined">close</span>
              </button>
            </header>

            <div class="flex shrink-0 flex-wrap items-center justify-between gap-3 border-b border-[#E2E8F0] bg-[#F7FAFC] px-6 py-3">
              <div class="flex items-center gap-4">
                <div>
                  <span class="block text-[10px] font-bold uppercase text-[#94A3B8]">Estado</span>
                  <app-ticket-chip kind="status" [value]="request.status" />
                </div>
                <div>
                  <span class="block text-[10px] font-bold uppercase text-[#94A3B8]">Prioridad</span>
                  <app-ticket-chip kind="priority" [value]="request.priority" />
                </div>
              </div>
              @if (canManage()) {
                <div class="flex flex-wrap items-center gap-2">
                  <button type="button" (click)="open('record')" [disabled]="state.busy"
                    class="flex items-center gap-1.5 rounded-lg bg-[#457b9d] px-3 py-1.5 text-[12px] font-semibold !text-white transition-colors hover:bg-[#3E5C76] disabled:opacity-50">
                    <span class="material-symbols-outlined text-[16px]">build</span> Registrar mantenimiento
                  </button>
                  @for (next of request.allowed_next_statuses; track next) {
                    <button type="button" (click)="startTransition(next)" [disabled]="state.busy"
                      class="rounded-lg px-2.5 py-1.5 text-[12px] font-semibold transition-colors disabled:opacity-50"
                      [class]="transitionStyle(next)">{{ transitionLabel(next) }}</button>
                  }
                </div>
              }
            </div>

            <div class="flex-1 space-y-5 overflow-y-auto px-6 py-5">
              @if (state.error) {
                <p class="rounded-lg bg-[#FEE2E2] px-3 py-2 text-[13px] text-[#991B1B]" role="alert">{{ state.error }}</p>
              } @else if (notice()) {
                <p class="flex items-center gap-2 rounded-lg bg-[#D1FAE5] px-3 py-2 text-[13px] font-medium text-[#065F46]" role="status">
                  <span class="material-symbols-outlined text-[18px]">check_circle</span>{{ notice() }}
                </p>
              }

              <section class="space-y-3 rounded-xl border border-[#E2E8F0] bg-[#F7FAFC]/60 p-4">
                <span class="block border-b border-[#E2E8F0] pb-2 text-[11px] font-bold uppercase tracking-wider text-[#457b9d]">Ficha del ticket</span>
                <dl class="grid grid-cols-2 gap-3 text-[12px]">
                  <div><dt class="text-[#94A3B8]">Equipo</dt><dd class="font-bold">{{ request.equipment.asset_tag }} ({{ request.equipment.brand }} {{ request.equipment.model }})</dd></div>
                  <div><dt class="text-[#94A3B8]">Solicitante</dt><dd class="font-semibold">{{ request.requested_by.full_name }}</dd></div>
                  <div><dt class="text-[#94A3B8]">Creado</dt><dd class="font-medium">{{ request.created_at | date: 'dd/MM/yyyy HH:mm' }}</dd></div>
                  <div><dt class="text-[#94A3B8]">Última actualización</dt><dd class="font-medium">{{ request.updated_at | date: 'dd/MM/yyyy HH:mm' }}</dd></div>
                  @if (request.resolved_at) {
                    <div><dt class="text-[#94A3B8]">Resuelto</dt><dd class="font-semibold text-[#047857]">{{ request.resolved_at | date: 'dd/MM/yyyy HH:mm' }}</dd></div>
                  }
                  @if (request.closed_at) {
                    <div><dt class="text-[#94A3B8]">Cerrado</dt><dd class="font-semibold text-[#334155]">{{ request.closed_at | date: 'dd/MM/yyyy HH:mm' }}</dd></div>
                  }
                </dl>
                <div>
                  <span class="mb-1 block text-[11px] font-semibold uppercase text-[#94A3B8]">Descripción del problema</span>
                  <p class="whitespace-pre-line rounded-lg border border-[#E2E8F0] bg-white p-3 text-[13px] leading-relaxed">{{ request.description }}</p>
                </div>
                @if (request.resolution_summary) {
                  <div>
                    <span class="mb-1 block text-[11px] font-bold uppercase text-[#065F46]">Resumen de resolución</span>
                    <p class="whitespace-pre-line rounded-lg border border-[#A7F3D0] bg-[#ECFDF5] p-3 text-[13px] font-medium leading-relaxed text-[#064E3B]">{{ request.resolution_summary }}</p>
                  </div>
                }
              </section>

              <section class="flex items-center justify-between gap-3 rounded-xl border border-[#E2E8F0] bg-[#F7FAFC]/60 p-4">
                <div class="flex min-w-0 items-center gap-3">
                  <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-[13px] font-bold"
                    [class]="request.current_assignment ? 'bg-[#ADD7F6] text-[#3E5C76]' : 'bg-[#E9EEF5] text-[#94A3B8]'">
                    {{ request.current_assignment ? initialsOf(request.current_assignment.technician.full_name) : '--' }}
                  </span>
                  <div class="min-w-0">
                    <span class="block text-[10px] font-bold uppercase text-[#94A3B8]">Técnico asignado</span>
                    <p class="truncate text-[15px] font-bold">{{ request.current_assignment?.technician?.full_name ?? 'Sin técnico asignado' }}</p>
                    @if (request.current_assignment?.notes; as assignmentNotes) {
                      <span class="block truncate text-[12px] text-[#64748B]">{{ assignmentNotes }}</span>
                    }
                  </div>
                </div>
                @if (canManage()) {
                  <button type="button" (click)="open('assign')" [disabled]="state.busy"
                    class="flex shrink-0 items-center gap-1.5 rounded-lg border border-[#CED4DA] bg-white px-3 py-1.5 text-[12px] font-semibold !text-[#3E5C76] transition-colors hover:bg-[#ADD7F6]/30 disabled:opacity-50">
                    <span class="material-symbols-outlined text-[16px]">person_add</span>
                    {{ request.current_assignment ? 'Reasignar técnico' : 'Asignar técnico' }}
                  </button>
                }
              </section>

              <section class="space-y-3 rounded-xl border border-[#E2E8F0] bg-[#F7FAFC]/60 p-4">
                <div class="flex items-center justify-between">
                  <span class="flex items-center gap-2 text-[11px] font-bold uppercase tracking-wider text-[#457b9d]">
                    <span class="material-symbols-outlined text-[18px]">receipt_long</span> Historial de mantenimientos
                  </span>
                  <span class="rounded bg-[#E9EEF5] px-2 py-0.5 text-[12px] font-bold">{{ state.records.length }} {{ state.records.length === 1 ? 'registro' : 'registros' }}</span>
                </div>
                @for (record of state.records; track record.id) {
                  <article class="space-y-1.5 rounded-lg border border-[#E2E8F0] bg-white p-3 text-[12px]">
                    <div class="flex items-center justify-between">
                      <span class="rounded bg-[#DBEAFE] px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-[#1E40AF]">{{ workTypeLabel(record.work_type) }}</span>
                      <span class="font-mono text-[12px] font-bold text-[#065F46]">Total: {{ record.total_cost ?? 0 | currency }}</span>
                    </div>
                    <p><strong>Diagnóstico:</strong> <span class="text-[#64748B]">{{ record.diagnosis }}</span></p>
                    <p><strong>Acciones:</strong> <span class="text-[#64748B]">{{ record.actions_taken }}</span></p>
                    <p><strong>Resultado:</strong> <span class="text-[#64748B]">{{ record.result }}</span></p>
                    <p class="flex justify-between border-t border-[#E2E8F0] pt-1 text-[11px] text-[#94A3B8]">
                      <span>Mano de obra: {{ record.labor_cost ?? 0 | currency }} · Repuestos: {{ record.parts_cost ?? 0 | currency }}</span>
                      <span class="font-mono">{{ record.started_at | date: 'dd/MM/yyyy HH:mm' }}</span>
                    </p>
                  </article>
                } @empty {
                  <p class="py-2 text-center text-[12px] italic text-[#94A3B8]">Aún no hay trabajos registrados en este ticket.</p>
                }
              </section>

              <section>
                <span class="mb-3 block text-[11px] font-bold uppercase tracking-wider text-[#94A3B8]">
                  Línea de tiempo ({{ timeline(state).length }} {{ timeline(state).length === 1 ? 'evento' : 'eventos' }})
                </span>
                <ol class="relative space-y-4 pl-6 before:absolute before:bottom-2 before:left-[9px] before:top-2 before:w-0.5 before:bg-[#E2E8F0]">
                  @for (entry of timeline(state); track entry.id) {
                    <li class="relative">
                      <span class="absolute -left-6 top-1 h-2.5 w-2.5 rounded-full ring-4 ring-white" [class]="statusDot(entry.to_status)"></span>
                      @if (entry.from_status) {
                        <p class="text-[13px] font-semibold">{{ statusLabel(entry.from_status) }} → <strong>{{ statusLabel(entry.to_status) }}</strong></p>
                      } @else {
                        <p class="text-[13px] font-semibold">Creación del ticket · <strong>{{ statusLabel(entry.to_status) }}</strong></p>
                        <p class="mt-0.5 text-[12px] font-medium text-[#64748B]">Registrado por {{ request.requested_by.full_name }}</p>
                      }
                      @if (entry.notes) { <p class="mt-0.5 text-[12px] font-medium text-[#64748B]">{{ entry.notes }}</p> }
                      <p class="mt-0.5 font-mono text-[11px] text-[#94A3B8]">{{ entry.changed_at | date: 'dd/MM/yyyy HH:mm' }}</p>
                    </li>
                  }
                </ol>
              </section>
            </div>

            <footer class="flex shrink-0 items-center justify-between border-t border-[#E2E8F0] bg-[#F7FAFC] px-6 py-3">
              <button type="button" (click)="closed.emit()" class="rounded-lg px-4 py-2 text-[13px] font-medium !text-[#475569] transition-colors hover:bg-[#E9EEF5]">Cerrar panel</button>
              @if (!canManage()) {
                <span class="text-[12px] text-[#94A3B8]">Solo lectura</span>
              }
            </footer>

            @if (dialog(); as current) {
              <div class="fixed inset-0 z-[70] flex items-center justify-center p-4">
                <div class="absolute inset-0 bg-[#0b1f3a]/50" (click)="closeDialog()" aria-hidden="true"></div>
                <div role="dialog" aria-modal="true" class="relative max-h-[90vh] w-full overflow-y-auto rounded-2xl border border-[#CED4DA] bg-white shadow-2xl"
                  [class]="current === 'record' ? 'max-w-xl' : 'max-w-md'">
                  @switch (current) {
                    @case ('transition') {
                      <form class="space-y-4 p-6" (submit)="submitTransition($event)">
                        <div>
                          <h3 class="text-[17px] font-bold">Cambiar estado</h3>
                          <p class="text-[12px] text-[#64748B]">Nuevo estado a aplicar:</p>
                          <div class="mt-1"><app-ticket-chip kind="status" [value]="target()" /></div>
                        </div>
                        @if (target() === 'resolved') {
                          <label class="block text-[12px] font-bold">Resumen de resolución <span class="text-[#BA1A1A]">*</span>
                            <textarea name="summary" rows="3" required class="mt-1 font-normal" [class]="field" placeholder="Explica la solución técnica ejecutada…"></textarea>
                          </label>
                        }
                        <label class="block text-[12px] font-bold">Notas del evento (opcional)
                          <input name="notes" class="mt-1 font-normal" [class]="field" placeholder="Ej: pruebas superadas con éxito" />
                        </label>
                        <p class="flex items-center gap-2 rounded-lg bg-[#F7FAFC] p-2.5 text-[11px] text-[#64748B]">
                          <span class="material-symbols-outlined text-[16px] text-[#457b9d]">mail</span>
                          Al pasar a Resuelto o Cerrado se notifica al solicitante.
                        </p>
                        <ng-container *ngTemplateOutlet="dialogActions; context: { label: 'Confirmar y aplicar', busy: state.busy }" />
                      </form>
                    }
                    @case ('assign') {
                      <form class="space-y-4 p-6" (submit)="submitAssign($event)">
                        <h3 class="flex items-center gap-2 text-[17px] font-bold"><span class="material-symbols-outlined text-[#457b9d]">engineering</span> Asignar técnico</h3>
                        @if (state.technicians.length === 0) {
                          <p class="text-[13px] text-[#64748B]">No hay técnicos disponibles para asignar.</p>
                        } @else {
                          <label class="block text-[12px] font-bold">Técnico responsable
                            <select name="technician" required class="mt-1 font-normal" [class]="field">
                              @for (tech of state.technicians; track tech.id) {
                                <option [value]="tech.id" [disabled]="!tech.is_available" [selected]="tech.id === request.current_assignment?.technician?.id">
                                  #{{ tech.id }} · {{ tech.specialization || 'Técnico' }}{{ tech.is_available ? '' : ' (no disponible)' }}
                                </option>
                              }
                            </select>
                          </label>
                          <label class="block text-[12px] font-bold">Notas (opcional)
                            <input name="notes" class="mt-1 font-normal" [class]="field" placeholder="Ej: visita en sitio" />
                          </label>
                        }
                        <div class="flex items-center justify-between gap-2 pt-2">
                          @if (request.current_assignment) {
                            <button type="button" (click)="unassign()" [disabled]="state.busy"
                              class="rounded-lg px-3 py-2 text-[12px] font-semibold !text-[#991B1B] hover:bg-[#FEE2E2] disabled:opacity-50">
                              {{ confirmUnassign() ? '¿Seguro? Pulsa de nuevo para quitar' : 'Quitar asignación' }}
                            </button>
                          } @else { <span></span> }
                          <div class="flex gap-2">
                            <button type="button" (click)="closeDialog()" class="rounded-lg px-3 py-2 text-[12px] font-semibold hover:bg-[#E9EEF5]">Cancelar</button>
                            <button type="submit" [disabled]="state.busy || state.technicians.length === 0"
                              class="rounded-lg bg-[#0b1f3a] px-4 py-2 text-[12px] font-bold !text-[#D4A017] hover:bg-[#3E5C76] disabled:opacity-50">Guardar asignación</button>
                          </div>
                        </div>
                      </form>
                    }
                    @case ('record') {
                      <form class="space-y-4 p-6" (submit)="submitRecord($event)">
                        <div>
                          <h3 class="text-[17px] font-bold">Registrar mantenimiento</h3>
                          <p class="text-[12px] text-[#64748B]">Hoja de intervención técnica</p>
                        </div>
                        <label class="block text-[12px] font-bold">Tipo de trabajo <span class="text-[#BA1A1A]">*</span>
                          <select name="work_type" required class="mt-1 font-normal" [class]="field">
                            @for (type of workTypes; track type) { <option [value]="type">{{ workTypeLabel(type) }}</option> }
                          </select>
                        </label>
                        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                          <label class="block text-[12px] font-bold">Inicio <span class="text-[#BA1A1A]">*</span>
                            <input name="started_at" type="datetime-local" required [value]="nowLocal" [max]="nowLocal" class="mt-1 font-normal" [class]="field" />
                          </label>
                          <label class="block text-[12px] font-bold">Finalización
                            <input name="completed_at" type="datetime-local" [max]="nowLocal" class="mt-1 font-normal" [class]="field" />
                          </label>
                        </div>
                        <label class="block text-[12px] font-bold">Diagnóstico <span class="text-[#BA1A1A]">*</span>
                          <textarea name="diagnosis" rows="2" required class="mt-1 font-normal" [class]="field" placeholder="Causa raíz identificada…"></textarea>
                        </label>
                        <label class="block text-[12px] font-bold">Acciones realizadas <span class="text-[#BA1A1A]">*</span>
                          <textarea name="actions" rows="2" required class="mt-1 font-normal" [class]="field" placeholder="Procedimientos efectuados, componentes sustituidos…"></textarea>
                        </label>
                        <label class="block text-[12px] font-bold">Resultado <span class="text-[#BA1A1A]">*</span>
                          <input name="result" required maxlength="50" class="mt-1 font-normal" [class]="field" placeholder="Ej: Operatividad restablecida" />
                        </label>
                        <div class="grid grid-cols-1 gap-3 rounded-xl border border-[#E2E8F0] bg-[#F7FAFC] p-3 sm:grid-cols-3">
                          <label class="block text-[12px] font-semibold text-[#64748B]">Mano de obra
                            <input name="labor" type="number" min="0" max="9999999999.99" step="0.01" (input)="labor.set(toNumber($any($event.target).value))" class="mt-1 font-mono font-normal" [class]="field" />
                          </label>
                          <label class="block text-[12px] font-semibold text-[#64748B]">Repuestos
                            <input name="parts" type="number" min="0" max="9999999999.99" step="0.01" (input)="parts.set(toNumber($any($event.target).value))" class="mt-1 font-mono font-normal" [class]="field" />
                          </label>
                          <div>
                            <span class="block text-[12px] font-bold text-[#457b9d]">Total calculado</span>
                            <div class="mt-1 flex h-[38px] items-center rounded-lg bg-[#ADD7F6]/50 px-3 font-mono text-[13px] font-bold text-[#3E5C76]">{{ labor() + parts() | currency }}</div>
                          </div>
                        </div>
                        <label class="block text-[12px] font-bold">Notas complementarias
                          <input name="notes" class="mt-1 font-normal" [class]="field" />
                        </label>
                        <ng-container *ngTemplateOutlet="dialogActions; context: { label: 'Guardar hoja de intervención', busy: state.busy }" />
                      </form>
                    }
                  }
                  @if (formError() || state.error) {
                    <p class="mx-6 mb-5 -mt-2 rounded-lg bg-[#FEE2E2] px-3 py-2 text-[12px] text-[#991B1B]" role="alert">{{ formError() || state.error }}</p>
                  }
                </div>
              </div>
            }
          } @else if (state.error) {
            <div class="flex flex-1 flex-col items-center justify-center gap-3 p-8 text-center">
              <p class="text-[14px] text-[#991B1B]" role="alert">{{ state.error }}</p>
              <button type="button" (click)="closed.emit()" class="rounded-lg bg-[#0b1f3a] px-4 py-2 text-[13px] font-semibold !text-white">Cerrar</button>
            </div>
          }
          }
        }

        <ng-template #dialogActions let-label="label" let-busy="busy">
          <div class="flex items-center justify-end gap-2 border-t border-[#E2E8F0] pt-4">
            <button type="button" (click)="closeDialog()" class="rounded-lg px-3 py-2 text-[12px] font-semibold hover:bg-[#E9EEF5]">Cancelar</button>
            <button type="submit" [disabled]="busy" class="rounded-lg bg-[#0b1f3a] px-4 py-2 text-[12px] font-bold !text-[#D4A017] hover:bg-[#3E5C76] disabled:opacity-50">{{ label }}</button>
          </div>
        </ng-template>
      </section>
    </div>
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class TicketDrawerComponent implements OnInit, OnChanges {
  private readonly store = inject(MaintenanceDetailStore);
  private readonly destroyRef = inject(DestroyRef);

  readonly ticketId = input.required<number>();
  readonly canManage = input(false);
  readonly closed = output<void>();
  /** Se emite cuando una acción cambió el ticket (estado o asignación), para refrescar la lista. */
  readonly changed = output<void>();

  readonly state$ = this.store.state$;
  readonly workTypes = WORK_TYPES;
  readonly field = FIELD;
  readonly dialog = signal<Dialog | null>(null);
  readonly target = signal('');
  readonly formError = signal('');
  readonly notice = signal('');
  readonly confirmUnassign = signal(false);
  readonly labor = signal(0);
  readonly parts = signal(0);
  nowLocal = localInputValue(new Date());

  private wasBusy = false;
  private pendingNotice = '';
  private lastKey = '';

  ngOnInit(): void {
    this.store.state$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe((state) => this.react(state));
  }

  ngOnChanges(): void {
    this.dialog.set(null);
    this.notice.set('');
    this.lastKey = '';
    this.store.load(this.ticketId());
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    if (this.dialog()) {
      this.closeDialog();
    } else {
      this.closed.emit();
    }
  }

  open(dialog: Dialog): void {
    this.formError.set('');
    this.notice.set('');
    this.confirmUnassign.set(false);
    if (dialog === 'record') {
      this.nowLocal = localInputValue(new Date());
      this.labor.set(0);
      this.parts.set(0);
    }
    this.dialog.set(dialog);
  }

  startTransition(status: string): void {
    this.target.set(status);
    this.open('transition');
  }

  closeDialog(): void {
    this.confirmUnassign.set(false);
    this.dialog.set(null);
  }

  submitTransition(event: Event): void {
    event.preventDefault();
    const data = this.formData(event);
    const summary = this.text(data, 'summary');
    if (this.target() === 'resolved' && !summary) {
      this.formError.set('El resumen de resolución es obligatorio para resolver el ticket.');
      return;
    }
    this.formError.set('');
    this.pendingNotice = `Estado cambiado a «${statusMeta(this.target()).label}».`;
    this.store.transition(this.target(), this.text(data, 'notes') || null, summary || null);
  }

  submitAssign(event: Event): void {
    event.preventDefault();
    const data = this.formData(event);
    const technician = Number(data.get('technician'));
    if (!technician) {
      this.formError.set('Selecciona un técnico.');
      return;
    }
    this.formError.set('');
    this.pendingNotice = 'Técnico asignado.';
    this.store.assign(technician, this.text(data, 'notes') || null);
  }

  /** Quitar la asignación pide una segunda pulsación para confirmar. */
  unassign(): void {
    if (!this.confirmUnassign()) {
      this.confirmUnassign.set(true);
      return;
    }
    this.confirmUnassign.set(false);
    this.pendingNotice = 'Asignación retirada.';
    this.store.unassign();
  }

  submitRecord(event: Event): void {
    event.preventDefault();
    const data = this.formData(event);
    const started = new Date(String(data.get('started_at')));
    const completedRaw = String(data.get('completed_at') ?? '');
    const completed = completedRaw ? new Date(completedRaw) : null;
    const now = new Date();
    const labor = this.cost(data, 'labor');
    const parts = this.cost(data, 'parts');
    const error = this.recordError(started, completed, now, labor, parts, data);
    if (error) {
      this.formError.set(error);
      return;
    }
    this.formError.set('');
    this.pendingNotice = 'Mantenimiento registrado.';
    this.store.addRecord({
      work_type: String(data.get('work_type')),
      started_at: started.toISOString(),
      completed_at: completed ? completed.toISOString() : null,
      diagnosis: this.text(data, 'diagnosis'),
      actions_taken: this.text(data, 'actions'),
      result: this.text(data, 'result'),
      labor_cost: labor,
      parts_cost: parts,
      notes: this.text(data, 'notes') || null,
    });
  }

  /** La línea de tiempo muestra primero lo más reciente. */
  timeline(state: MaintenanceDetailState) {
    return [...(state.request?.status_history ?? [])].reverse();
  }

  transitionLabel = (status: string): string => TRANSITION_LABELS[status] ?? statusMeta(status).label;
  transitionStyle = (status: string): string => TRANSITION_STYLES[status] ?? DEFAULT_TRANSITION_STYLE;
  statusLabel = (status: string): string => statusMeta(status).label;
  statusDot = (status: string): string => statusMeta(status).dot;
  workTypeLabel = (type: string): string => WORK_TYPE_LABELS[type] ?? type;
  initialsOf = initials;
  toNumber = (value: string): number => Number(value) || 0;

  /** Cierra el diálogo cuando una acción termina bien y avisa a la lista si el ticket cambió. */
  private react(state: MaintenanceDetailState): void {
    if (this.wasBusy && !state.busy && !state.error) {
      this.dialog.set(null);
      this.notice.set(this.pendingNotice);
    }
    this.wasBusy = state.busy;

    const request = state.request;
    if (!request || request.id !== this.ticketId()) {
      return;
    }
    const key = `${request.id}|${request.status}|${request.updated_at}|${request.current_assignment?.id ?? ''}`;
    if (this.lastKey && key !== this.lastKey) {
      this.changed.emit();
    }
    this.lastKey = key;
  }

  /** Primer problema de la hoja de intervención, o `''` si es válida. */
  private recordError(
    started: Date,
    completed: Date | null,
    now: Date,
    labor: number | null,
    parts: number | null,
    data: FormData,
  ): string {
    if (Number.isNaN(started.getTime())) {
      return 'Indica la fecha de inicio del trabajo.';
    }
    if (completed && Number.isNaN(completed.getTime())) {
      return 'La fecha de finalización no es válida.';
    }
    if (started > now) {
      return 'La fecha de inicio no puede ser futura: el trabajo ya se realizó.';
    }
    if (completed && completed > now) {
      return 'La fecha de finalización no puede ser futura.';
    }
    if (completed && completed < started) {
      return 'La finalización no puede ser anterior al inicio.';
    }
    if (!this.text(data, 'diagnosis') || !this.text(data, 'actions') || !this.text(data, 'result')) {
      return 'Diagnóstico, acciones y resultado no pueden estar vacíos.';
    }
    for (const value of [labor, parts]) {
      if (value === null) {
        continue;
      }
      if (!Number.isFinite(value) || value < 0) {
        return 'Los costos deben ser números iguales o mayores a cero.';
      }
      if (Math.round(value * 100) !== Number((value * 100).toFixed(4))) {
        return 'Los costos admiten como máximo dos decimales.';
      }
    }
    if ((labor ?? 0) + (parts ?? 0) > MAX_COST) {
      return 'El costo total supera el máximo permitido.';
    }
    return '';
  }

  private formData(event: Event): FormData {
    return new FormData(event.target as HTMLFormElement);
  }

  private text(data: FormData, name: string): string {
    return String(data.get(name) ?? '').trim();
  }

  private cost(data: FormData, name: string): number | null {
    const raw = this.text(data, name);
    return raw ? Number(raw) : null;
  }
}
