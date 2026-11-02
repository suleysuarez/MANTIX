import { ChangeDetectionStrategy, Component, ElementRef, HostListener, OnInit, inject, input, output, viewChild } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';

import { addDays, fromLocalInput, toLocalInput } from '../../core/calendar-utils';
import { Equipment } from '../../core/equipment.service';
import { MaintenanceHubStore } from '../../core/maintenance-hub.store';
import { MaintenanceSchedule } from '../../core/schedules.service';
import { Technician } from '../../core/technicians.service';
import {
  PLAN_LIMITS, fieldError, futureDateTime, groupError, integerRange, optionalHours, optionalText, parseHours,
  reminderFitsInterval, requiredText,
} from './plan-form';

/** Equipos sin servicio posible: el backend también los rechaza. */
const UNSERVICEABLE = ['retired', 'disposed', 'lost'];

/** Campos del servidor (snake_case) a controles del formulario. */
const SERVER_FIELDS: Record<string, string> = {
  equipment_id: 'equipmentId', title: 'title', description: 'description', interval_days: 'intervalDays',
  remind_days_before: 'remindDaysBefore', first_due_at: 'firstDueAt', estimated_hours: 'estimatedHours',
  technician_id: 'technicianId',
};

const LABEL = 'text-[12px] font-bold text-on-surface';
const FIELD =
  'mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep aria-[invalid=true]:border-error';

/** Alta y edición de un plan preventivo con formulario reactivo y mensajes bajo cada campo. */
@Component({
  selector: 'app-plan-form-modal',
  standalone: true,
  imports: [ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
      <div class="absolute inset-0 bg-brand-navy/50" (click)="closed.emit()" aria-hidden="true"></div>
      <form class="glass relative max-h-[92vh] w-full max-w-xl overflow-y-auto rounded-t-2xl sm:rounded-2xl" role="dialog" aria-modal="true"
        aria-labelledby="plan-form-title" [formGroup]="form" (ngSubmit)="submit()" novalidate>
        <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
          <h2 id="plan-form-title" class="text-[16px] font-bold text-on-surface">{{ plan() ? 'Editar plan' : 'Programar mantenimiento' }}</h2>
          <button type="button" (click)="closed.emit()" aria-label="Cerrar"
            class="rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
            <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
          </button>
        </header>

        <div class="grid grid-cols-1 gap-4 px-5 py-4 sm:grid-cols-2">
          <div class="sm:col-span-2">
            <label for="pf-equipment" [class]="label">Equipo *</label>
            <select #firstField id="pf-equipment" formControlName="equipmentId" [class]="field" [attr.aria-invalid]="invalid('equipmentId')" aria-describedby="pf-equipment-err">
              <option [ngValue]="null">Selecciona un equipo…</option>
              @for (e of serviceable(); track e.id) {
                <option [ngValue]="e.id">{{ e.asset_tag }} · {{ e.brand }} {{ e.model }}</option>
              }
            </select>
            <p id="pf-equipment-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('equipmentId') }}</p>
          </div>

          <div class="sm:col-span-2">
            <label for="pf-title" [class]="label">Título *</label>
            <input id="pf-title" type="text" formControlName="title" [class]="field" [attr.maxlength]="limits.titleMax + 50" [attr.aria-invalid]="invalid('title')" aria-describedby="pf-title-err" />
            <p id="pf-title-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('title') }}</p>
          </div>

          <div class="sm:col-span-2">
            <label for="pf-description" [class]="label">Descripción</label>
            <textarea id="pf-description" rows="2" formControlName="description" [class]="field" [attr.aria-invalid]="invalid('description')" aria-describedby="pf-description-err"></textarea>
            <p id="pf-description-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('description') }}</p>
          </div>

          <div>
            <label for="pf-interval" [class]="label">Cada cuántos días *</label>
            <input id="pf-interval" type="number" inputmode="numeric" min="1" step="1" formControlName="intervalDays" [class]="field" [attr.aria-invalid]="invalid('intervalDays')" aria-describedby="pf-interval-err" />
            <p id="pf-interval-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('intervalDays') }}</p>
          </div>

          <div>
            <label for="pf-remind" [class]="label">Recordar con (días de antelación) *</label>
            <input id="pf-remind" type="number" inputmode="numeric" min="0" step="1" formControlName="remindDaysBefore" [class]="field" [attr.aria-invalid]="invalid('remindDaysBefore')" aria-describedby="pf-remind-err" />
            <p id="pf-remind-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('remindDaysBefore') || groupMessage() }}</p>
          </div>

          @if (!plan()) {
            <div>
              <label for="pf-due" [class]="label">Primer servicio *</label>
              <input id="pf-due" type="datetime-local" formControlName="firstDueAt" [min]="minDue" [class]="field" [attr.aria-invalid]="invalid('firstDueAt')" aria-describedby="pf-due-err" />
              <p id="pf-due-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('firstDueAt') }}</p>
            </div>
          }

          <div>
            <label for="pf-hours" [class]="label">Horas estimadas</label>
            <input id="pf-hours" type="text" inputmode="decimal" formControlName="estimatedHours" placeholder="p. ej. 1.5" [class]="field" [attr.aria-invalid]="invalid('estimatedHours')" aria-describedby="pf-hours-err" />
            <p id="pf-hours-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('estimatedHours') }}</p>
          </div>

          <div class="sm:col-span-2">
            <label for="pf-tech" [class]="label">Técnico responsable</label>
            <select id="pf-tech" formControlName="technicianId" [class]="field">
              <option [ngValue]="null">Sin asignar</option>
              @for (t of technicians(); track t.id) {
                <option [ngValue]="t.id">{{ t.full_name }}{{ t.is_available ? '' : ' (no disponible)' }}</option>
              }
            </select>
            <p class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('technicianId') }}</p>
          </div>
        </div>

        <footer class="flex justify-end gap-2 border-t border-brand-grey/70 px-5 py-3">
          <button type="button" (click)="closed.emit()" [disabled]="busy()"
            class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">Cancelar</button>
          <button type="submit" [disabled]="form.invalid || busy()"
            class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
            {{ busy() ? 'Guardando…' : plan() ? 'Guardar cambios' : 'Programar' }}
          </button>
        </footer>
      </form>
    </div>
  `,
})
export class PlanFormModalComponent implements OnInit {
  private readonly store = inject(MaintenanceHubStore);

  /** Con un plan se edita; sin él se crea. */
  readonly plan = input<MaintenanceSchedule | null>(null);
  readonly equipment = input<Equipment[]>([]);
  readonly technicians = input<Technician[]>([]);
  readonly busy = input(false);
  readonly closed = output<void>();

  readonly firstField = viewChild<ElementRef<HTMLSelectElement>>('firstField');
  readonly label = LABEL;
  readonly field = FIELD;
  readonly limits = PLAN_LIMITS;
  readonly minDue = toLocalInput(new Date());

  readonly form = new FormGroup(
    {
      equipmentId: new FormControl<number | null>(null, Validators.required),
      title: new FormControl('', { nonNullable: true, validators: [requiredText(PLAN_LIMITS.titleMin, PLAN_LIMITS.titleMax)] }),
      description: new FormControl('', { nonNullable: true, validators: [optionalText(PLAN_LIMITS.descriptionMax)] }),
      intervalDays: new FormControl<number | string>(30, { validators: [integerRange(PLAN_LIMITS.intervalMin, PLAN_LIMITS.intervalMax)] }),
      remindDaysBefore: new FormControl<number | string>(3, { validators: [integerRange(0, PLAN_LIMITS.remindMax)] }),
      firstDueAt: new FormControl(toLocalInput(this.tomorrowAtNine()), { nonNullable: true, validators: [futureDateTime()] }),
      estimatedHours: new FormControl('', { nonNullable: true, validators: [optionalHours(PLAN_LIMITS.hoursMax)] }),
      technicianId: new FormControl<number | null>(null),
    },
    { validators: reminderFitsInterval },
  );

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closed.emit();
  }

  serviceable = (): Equipment[] => this.equipment().filter((e) => !UNSERVICEABLE.includes(e.status));
  error = (name: string): string => fieldError(this.form.get(name));
  invalid = (name: string): boolean => !!this.form.get(name)?.invalid && !!this.form.get(name)?.touched;
  groupMessage = (): string => (this.form.touched ? groupError(this.form) : '');

  ngOnInit(): void {
    const plan = this.plan();
    if (plan) {
      this.form.controls.firstDueAt.disable();
      this.form.controls.equipmentId.disable();
      this.form.patchValue({
        equipmentId: plan.equipment.id,
        title: plan.title,
        description: plan.description ?? '',
        intervalDays: plan.interval_days,
        remindDaysBefore: plan.remind_days_before,
        estimatedHours: plan.estimated_hours ?? '',
        technicianId: plan.technician?.id ?? null,
      });
    }
    setTimeout(() => this.firstField()?.nativeElement.focus());
  }

  submit(): void {
    this.form.markAllAsTouched();
    if (this.form.invalid || this.busy()) {
      return;
    }
    const value = this.form.getRawValue();
    const common = {
      title: value.title.trim(),
      description: value.description.trim() || null,
      interval_days: Number(value.intervalDays),
      remind_days_before: Number(value.remindDaysBefore),
      estimated_hours: parseHours(value.estimatedHours),
      technician_id: value.technicianId,
    };
    const plan = this.plan();
    const call = plan
      ? this.store.update(plan.id, common)
      : this.store.create({
          ...common,
          equipment_id: value.equipmentId as number,
          first_due_at: fromLocalInput(value.firstDueAt) as string,
        });
    call.subscribe((result) => {
      if (result.ok) {
        this.closed.emit();
        return;
      }
      for (const [serverField, message] of Object.entries(result.fieldErrors)) {
        this.form.get(SERVER_FIELDS[serverField] ?? serverField)?.setErrors({ server: message });
        this.form.get(SERVER_FIELDS[serverField] ?? serverField)?.markAsTouched();
      }
    });
  }

  private tomorrowAtNine(): Date {
    const tomorrow = addDays(new Date(), 1);
    return new Date(tomorrow.getFullYear(), tomorrow.getMonth(), tomorrow.getDate(), 9, 0);
  }
}
