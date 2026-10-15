import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, inject, input, output, signal } from '@angular/core';
import { FormControl, ReactiveFormsModule } from '@angular/forms';

import { fromLocalInput, toLocalInput } from '../../core/calendar-utils';
import { MaintenanceHubStore } from '../../core/maintenance-hub.store';
import { MaintenanceSchedule, ScheduleHistory } from '../../core/schedules.service';
import {
  PLAN_LIMITS, fieldError, futureDateTime, optionalHours, optionalText, parseHours,
} from './plan-form';

type Action = 'complete' | 'reschedule' | 'deactivate' | null;

const FIELD =
  'mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep aria-[invalid=true]:border-error';

/** Detalle de un plan: datos, historial y las acciones de completar, reprogramar y desactivar. */
@Component({
  selector: 'app-plan-detail-panel',
  standalone: true,
  imports: [DatePipe, ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <aside class="glass flex max-h-[calc(100vh-2rem)] flex-col overflow-hidden rounded-2xl" aria-label="Detalle del plan">
      <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
        <h2 class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Plan preventivo</h2>
        <button type="button" (click)="closed.emit()" aria-label="Cerrar detalle"
          class="rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
          <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
        </button>
      </header>

      <div class="min-h-0 flex-1 space-y-4 overflow-y-auto px-5 py-4">
        @if (loading()) {
          <div class="space-y-3" role="status" aria-label="Cargando plan">
            <div class="h-5 w-3/4 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
            <div class="h-20 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
          </div>
        } @else if (error()) {
          <p role="alert" class="rounded-lg bg-error-container px-3 py-2 text-[13px] text-on-error-container">{{ error() }}</p>
        } @else if (plan()) {
          @let p = plan()!;
          <div>
            <h3 class="text-[17px] font-bold leading-6 text-on-surface">{{ p.title }}</h3>
            <p class="mt-0.5 text-[12px] text-on-surface-variant">{{ p.equipment.asset_tag }} · {{ p.equipment.brand }} {{ p.equipment.model }}</p>
            <p class="mt-2 inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-bold" [class]="statusClass()">
              <span class="material-symbols-outlined text-[15px]" aria-hidden="true">{{ !p.is_active ? 'pause_circle' : overdue() ? 'event_busy' : 'event_upcoming' }}</span>
              {{ !p.is_active ? 'Inactivo' : overdue() ? 'Vencido' : 'Programado' }}
            </p>
          </div>

          <dl class="grid grid-cols-2 gap-x-4 gap-y-3 text-[12px]">
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Próximo servicio</dt><dd class="mt-0.5 text-on-surface">{{ p.next_due_at | date: 'dd/MM/yyyy HH:mm' }}</dd></div>
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Cada</dt><dd class="mt-0.5 text-on-surface">{{ p.interval_days }} días</dd></div>
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Técnico</dt><dd class="mt-0.5 text-on-surface">{{ p.technician?.full_name ?? 'Sin asignar' }}</dd></div>
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Horas estimadas</dt><dd class="mt-0.5 text-on-surface">{{ p.estimated_hours ?? '—' }}</dd></div>
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Recordatorio</dt><dd class="mt-0.5 text-on-surface">{{ p.remind_days_before }} días antes</dd></div>
          </dl>
          @if (p.description) {
            <p class="whitespace-pre-line text-[13px] leading-5 text-on-surface">{{ p.description }}</p>
          }

          @if (canManage() && p.is_active) {
            <section class="space-y-3 border-t border-brand-grey/70 pt-4" aria-label="Acciones del plan">
              @if (action() === null) {
                <div class="grid grid-cols-2 gap-2">
                  <button type="button" (click)="open('complete')" [disabled]="busy()"
                    class="glass-btn col-span-2 flex items-center justify-center gap-2 rounded-xl px-4 py-2.5 text-[13px] font-bold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
                    <span class="material-symbols-outlined text-[18px]" aria-hidden="true">task_alt</span> Marcar como hecho
                  </button>
                  <button type="button" (click)="open('reschedule')" [disabled]="busy()" [class]="secondary">Reprogramar</button>
                  <button type="button" (click)="edit.emit()" [disabled]="busy()" [class]="secondary">Editar</button>
                  <button type="button" (click)="open('deactivate')" [disabled]="busy()"
                    class="col-span-2 rounded-xl border border-error bg-transparent px-4 py-2 text-[13px] font-bold !text-error hover:bg-error-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-error disabled:opacity-50">Desactivar plan…</button>
                </div>
              }

              @if (action() === 'complete') {
                <form (submit)="complete($event)" class="space-y-2" novalidate>
                  <label for="pd-hours" class="text-[12px] font-bold text-on-surface">Horas que tomó (opcional)</label>
                  <input id="pd-hours" type="text" inputmode="decimal" [formControl]="hours" placeholder="p. ej. 1.5" [class]="field" [attr.aria-invalid]="hours.invalid && hours.touched" aria-describedby="pd-hours-err" />
                  <p id="pd-hours-err" class="min-h-[1rem] text-[12px] text-error" role="alert">{{ err(hours) }}</p>
                  <p class="text-[12px] text-on-surface-variant">El siguiente servicio se programa {{ p.interval_days }} días después.</p>
                  <div class="flex justify-end gap-2">
                    <button type="button" (click)="close()" [disabled]="busy()" [class]="ghost">Volver</button>
                    <button type="submit" [disabled]="hours.invalid || busy()" class="glass-btn rounded-lg px-4 py-2 text-[13px] font-bold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">Confirmar</button>
                  </div>
                </form>
              }

              @if (action() === 'reschedule') {
                <form (submit)="reschedule($event)" class="space-y-2" novalidate>
                  <label for="pd-due" class="text-[12px] font-bold text-on-surface">Nueva fecha y hora *</label>
                  <input id="pd-due" type="datetime-local" [formControl]="newDue" [min]="minDue" [class]="field" [attr.aria-invalid]="newDue.invalid && newDue.touched" aria-describedby="pd-due-err" />
                  <p id="pd-due-err" class="min-h-[1rem] text-[12px] text-error" role="alert">{{ err(newDue) }}</p>
                  <label for="pd-reason" class="text-[12px] font-bold text-on-surface">Motivo (opcional)</label>
                  <textarea id="pd-reason" rows="2" [formControl]="reason" [class]="field" [attr.aria-invalid]="reason.invalid && reason.touched" aria-describedby="pd-reason-err"></textarea>
                  <p id="pd-reason-err" class="min-h-[1rem] text-[12px] text-error" role="alert">{{ err(reason) }}</p>
                  <div class="flex justify-end gap-2">
                    <button type="button" (click)="close()" [disabled]="busy()" [class]="ghost">Volver</button>
                    <button type="submit" [disabled]="newDue.invalid || reason.invalid || busy()" class="glass-btn rounded-lg px-4 py-2 text-[13px] font-bold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">Reprogramar</button>
                  </div>
                </form>
              }

              @if (action() === 'deactivate') {
                <div class="space-y-2 rounded-xl border border-error/40 bg-error-container/40 p-3">
                  <p class="text-[13px] font-semibold text-on-error-container">¿Desactivar este plan?</p>
                  <p class="text-[12px] text-on-error-container">Dejará de aparecer en el calendario y no enviará recordatorios. Su historial se conserva.</p>
                  <div class="flex justify-end gap-2">
                    <button type="button" (click)="close()" [disabled]="busy()" [class]="ghost">Volver</button>
                    <button type="button" (click)="deactivate()" [disabled]="busy()"
                      class="rounded-lg bg-error px-4 py-2 text-[13px] font-bold !text-on-error focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-error disabled:opacity-50">Confirmar desactivación</button>
                  </div>
                </div>
              }
            </section>
          }

          <section>
            <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Servicios realizados</h3>
            @for (run of history()?.runs ?? []; track run.id) {
              <p class="mt-1.5 flex flex-wrap items-center gap-x-2 text-[12px]">
                <span class="font-semibold text-on-surface">{{ run.completed_at | date: 'dd/MM/yyyy' }}</span>
                <span class="rounded-full px-2 py-0.5 text-[11px] font-bold" [class]="run.on_time ? 'bg-primary-fixed text-on-primary-fixed-variant' : 'bg-secondary-fixed text-on-secondary-fixed'">{{ run.on_time ? 'A tiempo' : 'Con retraso' }}</span>
                @if (run.actual_hours) { <span class="text-on-surface-variant">{{ run.actual_hours }} h</span> }
              </p>
            } @empty {
              <p class="mt-1 text-[12px] text-on-surface-variant">Aún no se ha registrado ningún servicio.</p>
            }
          </section>

          @if (history()?.reschedules?.length) {
            <section>
              <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Reprogramaciones</h3>
              @for (move of history()!.reschedules; track move.id) {
                <p class="mt-1.5 text-[12px] text-on-surface">
                  {{ move.old_due_at | date: 'dd/MM' }} → {{ move.new_due_at | date: 'dd/MM/yyyy' }}
                  @if (move.reason) { <span class="text-on-surface-variant"> · {{ move.reason }}</span> }
                </p>
              }
            </section>
          }
        }
      </div>
    </aside>
  `,
})
export class PlanDetailPanelComponent {
  private readonly store = inject(MaintenanceHubStore);

  readonly plan = input<MaintenanceSchedule | null>(null);
  readonly history = input<ScheduleHistory | null>(null);
  readonly loading = input(false);
  readonly error = input('');
  readonly busy = input(false);
  readonly canManage = input(false);
  readonly closed = output<void>();
  readonly edit = output<void>();

  readonly action = signal<Action>(null);
  readonly field = FIELD;
  readonly secondary =
    'rounded-xl border border-brand-accentDeep bg-transparent px-4 py-2 text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep disabled:opacity-50';
  readonly ghost =
    'rounded-lg bg-transparent px-3 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep';
  readonly minDue = toLocalInput(new Date());

  readonly hours = new FormControl('', { nonNullable: true, validators: [optionalHours(PLAN_LIMITS.hoursMax)] });
  readonly newDue = new FormControl('', { nonNullable: true, validators: [futureDateTime()] });
  readonly reason = new FormControl('', { nonNullable: true, validators: [optionalText(PLAN_LIMITS.reasonMax)] });

  readonly overdue = computed(() => {
    const plan = this.plan();
    return !!plan && plan.is_active && new Date(plan.next_due_at) < new Date();
  });
  readonly statusClass = computed(() =>
    !this.plan()?.is_active
      ? 'bg-surface-container text-on-surface-variant'
      : this.overdue()
        ? 'bg-error-container text-on-error-container'
        : 'bg-brand-accentLight/60 text-brand-accentDeep',
  );

  err = (control: FormControl): string => fieldError(control);

  open(action: Exclude<Action, null>): void {
    this.hours.reset('');
    this.newDue.reset('');
    this.reason.reset('');
    this.action.set(action);
  }

  close(): void {
    this.action.set(null);
  }

  complete(event: Event): void {
    event.preventDefault();
    this.hours.markAsTouched();
    const id = this.plan()?.id;
    if (id === undefined || this.hours.invalid || this.busy()) {
      return;
    }
    this.store.complete(id, parseHours(this.hours.value)).subscribe((result) => {
      if (result.ok) {
        this.close();
      } else if (result.fieldErrors['actual_hours']) {
        this.hours.setErrors({ server: result.fieldErrors['actual_hours'] });
      }
    });
  }

  reschedule(event: Event): void {
    event.preventDefault();
    this.newDue.markAsTouched();
    this.reason.markAsTouched();
    const id = this.plan()?.id;
    const iso = fromLocalInput(this.newDue.value);
    if (id === undefined || iso === null || this.newDue.invalid || this.reason.invalid || this.busy()) {
      return;
    }
    const reason = this.reason.value.trim();
    this.store
      .update(id, { next_due_at: iso, ...(reason ? { reschedule_reason: reason } : {}) }, 'Servicio reprogramado.')
      .subscribe((result) => {
        if (result.ok) {
          this.close();
        } else if (result.fieldErrors['next_due_at']) {
          this.newDue.setErrors({ server: result.fieldErrors['next_due_at'] });
        }
      });
  }

  deactivate(): void {
    const id = this.plan()?.id;
    if (id !== undefined && !this.busy()) {
      this.store.update(id, { is_active: false }, 'Plan desactivado.').subscribe((result) => result.ok && this.close());
    }
  }
}
