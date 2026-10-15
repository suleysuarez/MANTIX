import { ChangeDetectionStrategy, Component, ElementRef, OnInit, computed, input, output, viewChild } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';

import { fieldError, requiredText } from '../../core/form-validation';
import { Technician } from '../../core/technicians.service';
import { Requirement, TransitionData } from '../../core/workflow.service';

export interface Choice {
  value: string;
  label: string;
}

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `${FOCUS} mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface`;

/** Diálogo corto que pide lo que falta para pasar un ticket a un estado (categoría, técnico, resumen, motivo…). */
@Component({
  selector: 'app-transition-dialog',
  standalone: true,
  imports: [ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { '(keydown.escape)': 'cancel()' },
  template: `
    <div class="fixed inset-0 z-[70] flex items-center justify-center p-4" role="presentation">
      <div class="absolute inset-0 bg-brand-sidebar/50" (click)="cancel()" aria-hidden="true"></div>
      <form role="dialog" aria-modal="true" aria-labelledby="td-title" [formGroup]="form" (ngSubmit)="confirm()" novalidate
        class="tw-reset relative w-full max-w-md space-y-4 rounded-2xl border border-brand-grey bg-surface-container-lowest p-5 shadow-2xl">
        <header>
          <h2 id="td-title" class="text-[16px] font-bold text-on-surface">{{ title() }}</h2>
          <p class="text-[12px] text-on-surface-variant">{{ subtitle() }}</p>
        </header>

        @if (needs('category')) {
          <div>
            <label for="td-category" class="text-[12px] font-bold text-on-surface">Categoría</label>
            <select id="td-category" #first formControlName="category" [attr.aria-invalid]="shows('category')" [class]="field">
              <option value="">Selecciona…</option>
              @for (c of categories(); track c.value) { <option [value]="c.value">{{ c.label }}</option> }
            </select>
            <p class="min-h-4 text-[11px] text-error" role="alert">{{ message('category') }}</p>
          </div>
        }
        @if (needs('priority')) {
          <div>
            <label for="td-priority" class="text-[12px] font-bold text-on-surface">Prioridad</label>
            <select id="td-priority" formControlName="priority" [attr.aria-invalid]="shows('priority')" [class]="field">
              <option value="">Selecciona…</option>
              @for (p of priorities(); track p.value) { <option [value]="p.value">{{ p.label }}</option> }
            </select>
            <p class="min-h-4 text-[11px] text-error" role="alert">{{ message('priority') }}</p>
          </div>
        }
        @if (needs('technician')) {
          <div>
            <label for="td-technician" class="text-[12px] font-bold text-on-surface">Técnico</label>
            <select id="td-technician" #first formControlName="technician" [attr.aria-invalid]="shows('technician')" [class]="field">
              <option value="">Selecciona…</option>
              @for (t of technicians(); track t.id) {
                <option [value]="t.id" [disabled]="!t.is_available">{{ t.full_name }}{{ t.is_available ? '' : ' (no disponible)' }}</option>
              }
            </select>
            <p class="min-h-4 text-[11px] text-error" role="alert">{{ message('technician') }}</p>
          </div>
        }
        @if (needs('resolution_summary')) {
          <div>
            <label for="td-summary" class="text-[12px] font-bold text-on-surface">Resumen de la resolución</label>
            <textarea id="td-summary" #first rows="3" formControlName="summary" [attr.maxlength]="1050" [attr.aria-invalid]="shows('summary')" [class]="field"></textarea>
            <p class="min-h-4 text-[11px] text-error" role="alert">{{ message('summary') }}</p>
          </div>
        }
        @if (needs('reason')) {
          <div>
            <label for="td-reason" class="text-[12px] font-bold text-on-surface">Motivo (se guarda en el historial)</label>
            <textarea id="td-reason" #first rows="3" formControlName="reason" [attr.maxlength]="550" [attr.aria-invalid]="shows('reason')" [class]="field"></textarea>
            <p class="min-h-4 text-[11px] text-error" role="alert">{{ message('reason') }}</p>
          </div>
        }

        <footer class="flex justify-end gap-2">
          <button type="button" (click)="cancel()" [disabled]="busy()" [class]="focus + ' rounded-lg bg-transparent px-4 py-2 text-[13px] font-bold !text-brand-accentDeep hover:bg-surface-container-high'">Cancelar</button>
          <button type="submit" [disabled]="form.invalid || busy()" [class]="focus + ' glass-btn rounded-lg px-5 py-2 text-[13px] font-bold disabled:opacity-50'">{{ busy() ? 'Guardando…' : confirmLabel() }}</button>
        </footer>
      </form>
    </div>
  `,
})
export class TransitionDialogComponent implements OnInit {
  readonly title = input('Completa los datos');
  readonly subtitle = input('');
  readonly confirmLabel = input('Confirmar');
  readonly requires = input.required<Requirement[]>();
  readonly categories = input<Choice[]>([]);
  readonly priorities = input<Choice[]>([]);
  readonly technicians = input<Technician[]>([]);
  /** Valores con los que arranca (p. ej. la categoría que el ticket ya tiene). */
  readonly initial = input<TransitionData>({});
  readonly busy = input(false);

  readonly confirmed = output<TransitionData>();
  readonly cancelled = output<void>();

  readonly focus = FOCUS;
  readonly field = FIELD;
  private readonly firstField = viewChild<ElementRef<HTMLElement>>('first');
  readonly needed = computed(() => new Set(this.requires()));

  readonly form = new FormGroup({
    category: new FormControl('', { nonNullable: true }),
    priority: new FormControl('', { nonNullable: true }),
    technician: new FormControl('', { nonNullable: true }),
    summary: new FormControl('', { nonNullable: true }),
    reason: new FormControl('', { nonNullable: true }),
  });

  ngOnInit(): void {
    const need = this.needed();
    const initial = this.initial();
    // Solo se exige lo que este paso pide, con las mismas reglas que el servidor.
    if (need.has('category')) {
      this.form.controls.category.setValidators(Validators.required);
      this.form.controls.category.setValue(initial.category ?? '');
    }
    if (need.has('priority')) {
      this.form.controls.priority.setValidators(Validators.required);
      this.form.controls.priority.setValue(initial.priority ?? '');
    }
    if (need.has('technician')) {
      this.form.controls.technician.setValidators(Validators.required);
    }
    if (need.has('resolution_summary')) {
      this.form.controls.summary.setValidators(requiredText(5, 1000));
    }
    if (need.has('reason')) {
      this.form.controls.reason.setValidators(requiredText(5, 500));
    }
    this.form.updateValueAndValidity();
    queueMicrotask(() => this.firstField()?.nativeElement.focus());
  }

  needs(requirement: Requirement): boolean {
    return this.needed().has(requirement);
  }

  shows(field: keyof typeof this.form.controls): boolean {
    const control = this.form.controls[field];
    return control.invalid && control.touched;
  }

  message(field: keyof typeof this.form.controls): string {
    const control = this.form.controls[field];
    if (field === 'category' || field === 'priority' || field === 'technician') {
      return control.invalid && control.touched ? 'Elige una opción.' : '';
    }
    return fieldError(control, control.dirty);
  }

  confirm(): void {
    this.form.markAllAsTouched();
    if (this.form.invalid || this.busy()) {
      return;
    }
    const value = this.form.getRawValue();
    const data: TransitionData = {};
    if (this.needs('category')) {
      data.category = value.category;
    }
    if (this.needs('priority')) {
      data.priority = value.priority;
    }
    if (this.needs('technician')) {
      data.technicianId = Number(value.technician);
    }
    if (this.needs('resolution_summary')) {
      data.resolutionSummary = value.summary.trim();
    }
    if (this.needs('reason')) {
      data.reason = value.reason.trim();
    }
    this.confirmed.emit(data);
  }

  cancel(): void {
    if (!this.busy()) {
      this.cancelled.emit();
    }
  }
}
