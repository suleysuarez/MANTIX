import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, inject, input, output, signal } from '@angular/core';
import { FormControl, ReactiveFormsModule, Validators } from '@angular/forms';

import { MaintenanceRequest } from '../../core/maintenance.service';
import { PendingRequestsStore } from '../../core/pending-requests.store';
import { Technician } from '../../core/technicians.service';
import { TicketChipComponent } from '../tickets/ticket-chip.component';
import { statusMeta } from '../tickets/ticket-ui';
import {
  MAX_REASON, categoryLabel, formatWait, reasonError, reasonValidator, waitHours, waitTone, WAIT_CLASSES,
} from './pending-ui';

const REJECTABLE = ['submitted', 'triaged', 'assigned'];

/** Panel lateral de detalle: lectura de la solicitud y las tres acciones de triaje. */
@Component({
  selector: 'app-request-detail-panel',
  standalone: true,
  imports: [DatePipe, ReactiveFormsModule, TicketChipComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <aside class="glass flex max-h-[calc(100vh-6rem)] flex-col overflow-hidden rounded-2xl" aria-label="Detalle de la solicitud">
      <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
        <span class="font-mono text-[13px] font-bold text-brand-accentDeep">{{ detail()?.ticket_number ?? 'Solicitud' }}</span>
        <button type="button" (click)="closed.emit()" aria-label="Cerrar detalle"
          class="rounded-lg bg-transparent p-1 !text-on-surface-variant transition-colors hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
          <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
        </button>
      </header>

      <div class="min-h-0 flex-1 space-y-4 overflow-y-auto px-5 py-4">
        @if (loading()) {
          <div class="space-y-3" role="status" aria-label="Cargando detalle">
            <div class="h-5 w-3/4 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
            <div class="h-4 w-1/2 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
            <div class="h-24 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
          </div>
        } @else if (error()) {
          <p role="alert" class="rounded-lg bg-error-container px-3 py-2 text-[13px] text-on-error-container">{{ error() }}</p>
        } @else if (detail()) {
          @let d = detail()!;
          <div>
            <h2 class="text-[17px] font-bold leading-6 text-on-surface">{{ d.title }}</h2>
            <div class="mt-2 flex flex-wrap items-center gap-2">
              <app-ticket-chip kind="priority" [value]="d.priority" />
              <app-ticket-chip kind="status" [value]="d.status" />
              <span class="rounded-full bg-surface-container px-2.5 py-1 text-[12px] font-semibold text-on-surface-variant">{{ category() }}</span>
            </div>
          </div>

          @if (inQueue()) {
            <p class="flex items-center gap-2 rounded-lg px-3 py-2 text-[12px] font-semibold" [class]="waitClass()">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">schedule</span>
              En cola desde hace {{ wait() }}
            </p>
          } @else {
            <p class="flex items-center gap-2 rounded-lg bg-surface-container px-3 py-2 text-[12px] font-semibold text-on-surface-variant">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">info</span>
              Ya no está en la bandeja: {{ statusLabel() }}.
            </p>
          }

          <dl class="grid grid-cols-2 gap-x-4 gap-y-3 text-[12px]">
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Equipo</dt><dd class="mt-0.5 text-on-surface">{{ d.equipment.asset_tag }} · {{ d.equipment.brand }} {{ d.equipment.model }}</dd></div>
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Solicitante</dt><dd class="mt-0.5 text-on-surface">{{ d.requested_by.full_name }}</dd></div>
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Creada</dt><dd class="mt-0.5 text-on-surface">{{ d.created_at | date: 'dd/MM/yyyy HH:mm' }}</dd></div>
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Técnico</dt><dd class="mt-0.5 text-on-surface">{{ d.current_assignment?.technician?.full_name ?? 'Sin asignar' }}</dd></div>
          </dl>

          <section>
            <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Descripción</h3>
            <p class="mt-1 whitespace-pre-line text-[13px] leading-5 text-on-surface">{{ d.description }}</p>
          </section>

          <section>
            <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Historial</h3>
            <ol class="mt-2 space-y-2 border-l-2 border-brand-accentSky pl-3">
              @for (entry of d.status_history; track entry.id) {
                <li class="text-[12px]">
                  <span class="font-semibold text-on-surface">{{ label(entry.to_status) }}</span>
                  <span class="text-on-surface-variant"> · {{ entry.changed_at | date: 'dd/MM HH:mm' }}</span>
                  @if (entry.notes) {
                    <p class="text-on-surface-variant">{{ entry.notes }}</p>
                  }
                </li>
              }
            </ol>
          </section>

          @if (inQueue()) {
            <section class="space-y-3 border-t border-brand-grey/70 pt-4" aria-label="Acciones de triaje">
              @if (d.status === 'submitted') {
                <button type="button" (click)="triage()" [disabled]="busy()"
                  class="glass-btn flex w-full items-center justify-center gap-2 rounded-xl px-4 py-2.5 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep active:scale-[0.99]">
                  <span class="material-symbols-outlined text-[18px]" aria-hidden="true">rule</span> Clasificar solicitud
                </button>
              }

              <form (submit)="assign($event)" class="space-y-1.5" novalidate>
                <label for="assign-tech" class="text-[12px] font-bold text-on-surface">Asignar técnico</label>
                <div class="flex gap-2">
                  <select id="assign-tech" [formControl]="technician"
                    class="min-w-0 flex-1 rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
                    <option [ngValue]="null">Selecciona…</option>
                    @for (t of technicians(); track t.id) {
                      <option [ngValue]="t.id">{{ t.full_name }}{{ t.is_available ? '' : ' (no disponible)' }}</option>
                    }
                  </select>
                  <button type="submit" [disabled]="technician.invalid || busy()"
                    class="glass-btn rounded-lg px-4 py-2 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">Asignar</button>
                </div>
                @if (technician.touched && technician.invalid) {
                  <p class="text-[12px] text-error" role="alert">Elige un técnico para asignar.</p>
                }
                @if (selectedUnavailable()) {
                  <p class="text-[12px] text-on-secondary-fixed-variant">Este técnico figura como no disponible; la asignación se hará igualmente.</p>
                }
              </form>

              @if (!rejecting()) {
                <button type="button" (click)="startReject()" [disabled]="busy()"
                  class="flex w-full items-center justify-center gap-2 rounded-xl border border-error bg-transparent px-4 py-2 text-[13px] font-bold !text-error transition-colors hover:bg-error-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-error disabled:opacity-50">
                  <span class="material-symbols-outlined text-[18px]" aria-hidden="true">block</span> Rechazar…
                </button>
              } @else {
                <form (submit)="confirmReject($event)" class="space-y-2 rounded-xl border border-error/40 bg-error-container/40 p-3" novalidate>
                  <label for="reject-reason" class="text-[12px] font-bold text-on-error-container">Motivo del rechazo (se guarda en el historial)</label>
                  <textarea id="reject-reason" rows="3" [formControl]="reason" [attr.maxlength]="maxReason + 50"
                    [attr.aria-invalid]="reason.invalid && reason.touched" aria-describedby="reject-reason-help"
                    class="w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface focus-visible:outline focus-visible:outline-2 focus-visible:outline-error"></textarea>
                  <div id="reject-reason-help" class="flex items-start justify-between gap-2 text-[12px]">
                    @if (reason.touched && reason.invalid) {
                      <p class="text-error" role="alert">{{ reasonMessage() }}</p>
                    } @else {
                      <span class="text-on-surface-variant">Mínimo 5 caracteres.</span>
                    }
                    <span class="shrink-0 text-on-surface-variant">{{ reasonLength() }}/{{ maxReason }}</span>
                  </div>
                  <p class="text-[12px] font-semibold text-on-error-container">Esta acción cancela la solicitud y no se puede deshacer.</p>
                  <div class="flex justify-end gap-2">
                    <button type="button" (click)="cancelReject()" [disabled]="busy()"
                      class="rounded-lg bg-transparent px-3 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">Volver</button>
                    <button type="submit" [disabled]="reason.invalid || busy()"
                      class="rounded-lg bg-error px-4 py-2 text-[13px] font-bold !text-on-error transition-opacity focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-error disabled:opacity-50">Confirmar rechazo</button>
                  </div>
                </form>
              }
            </section>
          }
        }
      </div>
    </aside>
  `,
})
export class RequestDetailPanelComponent {
  private readonly store = inject(PendingRequestsStore);

  readonly detail = input<MaintenanceRequest | null>(null);
  readonly loading = input(false);
  readonly error = input('');
  readonly busy = input(false);
  readonly technicians = input<Technician[]>([]);
  readonly categoryNames = input<Map<string, string>>(new Map());
  readonly closed = output<void>();

  readonly maxReason = MAX_REASON;
  readonly technician = new FormControl<number | null>(null, Validators.required);
  readonly reason = new FormControl('', { nonNullable: true, validators: [reasonValidator] });
  readonly rejecting = signal(false);
  private readonly now = () => new Date();

  readonly inQueue = computed(() => REJECTABLE.includes(this.detail()?.status ?? ''));
  readonly category = computed(() => categoryLabel(this.detail()?.category, this.categoryNames()));
  readonly statusLabel = computed(() => statusMeta(this.detail()?.status ?? '').label.toLowerCase());
  readonly wait = computed(() => formatWait(waitHours(this.detail()?.created_at ?? '', this.now())));
  readonly waitClass = computed(() => WAIT_CLASSES[waitTone(waitHours(this.detail()?.created_at ?? '', this.now()))]);

  readonly label = (status: string): string => statusMeta(status).label;
  readonly reasonLength = (): number => this.reason.value.trim().length;
  readonly reasonMessage = (): string => reasonError(this.reason);
  readonly selectedUnavailable = (): boolean =>
    this.technicians().some((t) => t.id === this.technician.value && !t.is_available);

  triage(): void {
    const id = this.detail()?.id;
    if (id !== undefined) {
      this.store.triage(id).subscribe();
    }
  }

  assign(event: Event): void {
    event.preventDefault();
    this.technician.markAsTouched();
    const id = this.detail()?.id;
    if (id === undefined || this.technician.invalid || this.technician.value === null || this.busy()) {
      return;
    }
    this.store.assign(id, this.technician.value).subscribe((result) => {
      if (result.ok) {
        this.technician.reset(null);
      }
    });
  }

  startReject(): void {
    this.rejecting.set(true);
  }

  cancelReject(): void {
    this.rejecting.set(false);
    this.reason.reset('');
  }

  confirmReject(event: Event): void {
    event.preventDefault();
    this.reason.markAsTouched();
    const id = this.detail()?.id;
    if (id === undefined || this.reason.invalid || this.busy()) {
      return;
    }
    this.store.reject(id, this.reason.value.trim()).subscribe((result) => {
      if (result.ok) {
        this.cancelReject();
      } else if (result.fieldErrors['reason']) {
        this.reason.setErrors({ server: result.fieldErrors['reason'] });
      }
    });
  }
}
