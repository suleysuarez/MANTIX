import { ChangeDetectionStrategy, Component, inject, input, signal } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';

import { fieldError, integerRange, optionalInteger, requiredText } from '../../core/form-validation';
import { PriorityAdmin } from '../../core/settings.service';
import { SettingsStore } from '../../core/settings.store';

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const MAX_SLA_HOURS = 24 * 365;

/** Prioridades de tickets: nombre, urgencia y tiempo objetivo (SLA) editables; el código es fijo. */
@Component({
  selector: 'app-priorities-section',
  standalone: true,
  imports: [ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section aria-labelledby="pri-title" class="space-y-4">
      <header>
        <h2 id="pri-title" class="text-[18px] font-bold text-on-surface">Prioridades y tiempos objetivo</h2>
        <p class="text-[13px] text-on-surface-variant">El tiempo objetivo (SLA) es el plazo en horas para resolver un ticket de esa prioridad. El identificador no se puede cambiar.</p>
      </header>

      @if (error()) { <p role="alert" class="rounded-lg bg-error-container px-3 py-2 text-[13px] text-on-error-container">{{ error() }}</p> }

      @if (loading() && priorities().length === 0) {
        <div class="space-y-2" role="status" aria-label="Cargando prioridades">
          @for (n of skeleton; track n) { <div class="h-14 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none"></div> }
        </div>
      } @else if (priorities().length === 0 && !error()) {
        <p class="rounded-xl bg-surface-container px-4 py-6 text-center text-[13px] text-on-surface-variant">No hay prioridades definidas.</p>
      } @else {
        <ul class="divide-y divide-brand-grey/60 rounded-2xl border border-brand-grey bg-surface-container-lowest">
          @for (p of priorities(); track p.id) {
            <li class="px-4 py-3">
              @if (editing() === p.id) {
                <form [formGroup]="form" (ngSubmit)="save(p)" novalidate class="grid gap-3 sm:grid-cols-[1fr_6rem_8rem_auto] sm:items-start">
                  <div>
                    <label [for]="'p-name-' + p.id" class="text-[12px] font-bold text-on-surface">Nombre</label>
                    <input [id]="'p-name-' + p.id" formControlName="name" maxlength="100" [attr.aria-invalid]="!!error$('name')"
                      class="mt-1 w-full rounded-lg border border-brand-grey bg-surface-container-lowest px-3 py-1.5 text-[13px] text-on-surface" />
                    <p class="min-h-4 text-[11px] text-error" role="alert">{{ error$('name') }}</p>
                  </div>
                  <div>
                    <label [for]="'p-level-' + p.id" class="text-[12px] font-bold text-on-surface">Urgencia</label>
                    <input [id]="'p-level-' + p.id" formControlName="level" inputmode="numeric" [attr.aria-invalid]="!!error$('level')"
                      class="mt-1 w-full rounded-lg border border-brand-grey bg-surface-container-lowest px-3 py-1.5 text-[13px] text-on-surface" />
                    <p class="min-h-4 text-[11px] text-error" role="alert">{{ error$('level') }}</p>
                  </div>
                  <div>
                    <label [for]="'p-sla-' + p.id" class="text-[12px] font-bold text-on-surface">SLA (horas)</label>
                    <input [id]="'p-sla-' + p.id" formControlName="sla_hours" inputmode="numeric" placeholder="Sin plazo" [attr.aria-invalid]="!!error$('sla_hours')"
                      class="mt-1 w-full rounded-lg border border-brand-grey bg-surface-container-lowest px-3 py-1.5 text-[13px] text-on-surface" />
                    <p class="min-h-4 text-[11px] text-error" role="alert">{{ error$('sla_hours') }}</p>
                  </div>
                  <div class="flex gap-2 sm:mt-5">
                    <button type="submit" [disabled]="form.invalid || saving()" [class]="primary">Guardar</button>
                    <button type="button" (click)="editing.set(null)" [class]="ghost">Cancelar</button>
                  </div>
                </form>
              } @else {
                <div class="flex flex-wrap items-center gap-3">
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-[14px] font-semibold text-on-surface">{{ p.name }} <span class="font-mono text-[11px] font-normal text-on-surface-variant">{{ p.code }}</span></p>
                    <p class="text-[11px] text-on-surface-variant">Urgencia {{ p.level }} · {{ p.sla_hours === null ? 'sin plazo objetivo' : 'resolver en ' + p.sla_hours + ' h' }}</p>
                  </div>
                  <span class="rounded-full px-2.5 py-0.5 text-[11px] font-bold" [class]="p.is_active ? 'bg-brand-accentLight/60 text-brand-accentDeep' : 'bg-surface-container-high text-on-surface-variant'">{{ p.is_active ? 'Activa' : 'Inactiva' }}</span>
                  @if (canManage()) {
                    @if (confirm() === p.id) {
                      <span class="flex flex-wrap items-center gap-2 text-[12px] text-on-surface" role="alertdialog" aria-label="Confirmar cambio de estado">
                        ¿{{ p.is_active ? 'Desactivar' : 'Reactivar' }} «{{ p.name }}»?
                        <button type="button" (click)="toggle(p)" [disabled]="saving()" [class]="primary">Confirmar</button>
                        <button type="button" (click)="confirm.set(null)" [class]="ghost">Volver</button>
                      </span>
                    } @else {
                      <button type="button" (click)="startEdit(p)" [class]="ghost">Editar</button>
                      <button type="button" (click)="confirm.set(p.id)" [disabled]="saving()" [class]="ghost">{{ p.is_active ? 'Desactivar' : 'Reactivar' }}</button>
                    }
                  }
                </div>
              }
            </li>
          }
        </ul>
      }
    </section>
  `,
})
export class PrioritiesSectionComponent {
  private readonly store = inject(SettingsStore);

  readonly priorities = input.required<PriorityAdmin[]>();
  readonly loading = input(false);
  readonly error = input('');
  readonly saving = input(false);
  readonly canManage = input(true);
  readonly serverErrors = input<Record<string, string>>({});

  readonly skeleton = [1, 2, 3];
  readonly editing = signal<number | null>(null);
  readonly confirm = signal<number | null>(null);

  readonly primary = `${FOCUS} glass-btn rounded-lg px-4 py-2 text-[13px] font-bold disabled:opacity-50`;
  readonly ghost = `${FOCUS} rounded-lg bg-transparent px-2.5 py-1.5 text-[12px] font-bold !text-brand-accentDeep hover:bg-surface-container-high disabled:opacity-50`;

  readonly form = new FormGroup({
    name: new FormControl('', { nonNullable: true, validators: [requiredText(1, 100)] }),
    level: new FormControl('', { nonNullable: true, validators: [integerRange(1, 100)] }),
    sla_hours: new FormControl('', { nonNullable: true, validators: [optionalInteger(1, MAX_SLA_HOURS)] }),
  });

  error$(field: 'name' | 'level' | 'sla_hours'): string {
    return fieldError(this.form.controls[field], true) || this.serverErrors()[field] || '';
  }

  startEdit(priority: PriorityAdmin): void {
    this.confirm.set(null);
    this.form.reset({ name: priority.name, level: String(priority.level), sla_hours: priority.sla_hours === null ? '' : String(priority.sla_hours) });
    this.editing.set(priority.id);
  }

  save(priority: PriorityAdmin): void {
    if (this.form.invalid || this.saving()) {
      return;
    }
    const { name, level, sla_hours } = this.form.getRawValue();
    this.store.updatePriority(
      priority,
      { name: name.trim(), level: Number(level), sla_hours: sla_hours.trim() === '' ? null : Number(sla_hours) },
      () => this.editing.set(null),
    );
  }

  toggle(priority: PriorityAdmin): void {
    this.confirm.set(null);
    this.store.updatePriority(priority, { is_active: !priority.is_active }, () => undefined);
  }
}
