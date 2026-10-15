import { ChangeDetectionStrategy, Component, effect, inject, input } from '@angular/core';
import { AbstractControl, FormControl, FormGroup, ReactiveFormsModule, ValidationErrors } from '@angular/forms';

import { fieldError, requiredText } from '../../core/form-validation';
import { Organization } from '../../core/settings.service';
import { SettingsStore } from '../../core/settings.store';

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `mt-1 w-full rounded-lg border border-brand-grey bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface ${FOCUS}`;
const NIT = /^[0-9A-Za-z.-]{5,30}$/;

/** NIT opcional: si se escribe, 5 a 30 dígitos, letras, puntos o guiones (igual que el servidor). */
export function taxIdValidator(control: AbstractControl): ValidationErrors | null {
  const value = String(control.value ?? '').trim();
  return value === '' || NIT.test(value) ? null : { pattern: true };
}

/** Razón social opcional: los espacios no cuentan y se admiten 200 caracteres. */
const legalNameValidator = (control: AbstractControl): ValidationErrors | null =>
  String(control.value ?? '').trim().length > 200 ? { maxlength: { requiredLength: 200 } } : null;

/** Empresa que aparece en el encabezado de los PDF y Excel que se exportan. */
@Component({
  selector: 'app-organization-section',
  standalone: true,
  imports: [ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section aria-labelledby="org-title" class="space-y-4">
      <header>
        <h2 id="org-title" class="text-[18px] font-bold text-on-surface">Organización</h2>
        <p class="text-[13px] text-on-surface-variant">Estos datos salen en el encabezado de los reportes que exportas a PDF y Excel.</p>
      </header>

      @if (error()) { <p role="alert" class="rounded-lg bg-error-container px-3 py-2 text-[13px] text-on-error-container">{{ error() }}</p> }

      @if (loading() && !organization()) {
        <div class="h-48 animate-pulse rounded-2xl bg-surface-container motion-reduce:animate-none" role="status" aria-label="Cargando organización"></div>
      } @else {
        @if (organization() && !organization()!.configured) {
          <p class="rounded-lg bg-secondary-fixed px-3 py-2 text-[12px] font-semibold text-on-secondary-fixed" role="status">
            Aún no hay datos guardados: los reportes dicen «Mantix» y dejan vacíos la razón social y el NIT.
          </p>
        }
        <form [formGroup]="form" (ngSubmit)="save()" novalidate class="glass grid gap-4 rounded-2xl p-5 md:grid-cols-2" aria-label="Datos de la organización">
          <div class="md:col-span-2">
            <label for="org-name" class="text-[12px] font-bold text-on-surface">Nombre de la empresa</label>
            <input id="org-name" formControlName="company_name" maxlength="150" autocomplete="organization" [attr.aria-invalid]="!!error$('company_name')" aria-describedby="org-name-err" [class]="field" />
            <p id="org-name-err" class="min-h-4 text-[11px] text-error" role="alert">{{ error$('company_name') }}</p>
          </div>
          <div>
            <label for="org-legal" class="text-[12px] font-bold text-on-surface">Razón social (opcional)</label>
            <input id="org-legal" formControlName="legal_name" maxlength="200" [attr.aria-invalid]="!!error$('legal_name')" aria-describedby="org-legal-err" [class]="field" />
            <p id="org-legal-err" class="min-h-4 text-[11px] text-error" role="alert">{{ error$('legal_name') }}</p>
          </div>
          <div>
            <label for="org-nit" class="text-[12px] font-bold text-on-surface">NIT (opcional)</label>
            <input id="org-nit" formControlName="tax_id" maxlength="30" placeholder="900.123.456-7" [attr.aria-invalid]="!!error$('tax_id')" aria-describedby="org-nit-err" [class]="field" />
            <p id="org-nit-err" class="min-h-4 text-[11px] text-error" role="alert">{{ error$('tax_id') }}</p>
          </div>
          @if (canManage()) {
            <div class="md:col-span-2">
              <button type="submit" [disabled]="form.invalid || saving() || form.pristine"
                [class]="focus + ' glass-btn rounded-xl px-6 py-2.5 text-[13px] font-bold disabled:cursor-not-allowed disabled:opacity-50'">{{ saving() ? 'Guardando…' : 'Guardar cambios' }}</button>
            </div>
          }
        </form>
      }
    </section>
  `,
})
export class OrganizationSectionComponent {
  private readonly store = inject(SettingsStore);

  readonly organization = input<Organization | null>(null);
  readonly loading = input(false);
  readonly error = input('');
  readonly saving = input(false);
  readonly canManage = input(true);
  readonly serverErrors = input<Record<string, string>>({});

  readonly focus = FOCUS;
  readonly field = FIELD;
  readonly form = new FormGroup({
    company_name: new FormControl('', { nonNullable: true, validators: [requiredText(2, 150)] }),
    legal_name: new FormControl('', { nonNullable: true, validators: [legalNameValidator] }),
    tax_id: new FormControl('', { nonNullable: true, validators: [taxIdValidator] }),
  });

  constructor() {
    // El formulario parte de lo guardado y se vuelve a llenar tras guardar.
    effect(() => {
      const org = this.organization();
      if (org) {
        this.form.reset({ company_name: org.company_name, legal_name: org.legal_name ?? '', tax_id: org.tax_id ?? '' });
      }
      if (!this.canManage()) {
        this.form.disable({ emitEvent: false });
      }
    });
  }

  error$(field: 'company_name' | 'legal_name' | 'tax_id'): string {
    const control = this.form.controls[field];
    const local = fieldError(control, control.dirty);
    if (local) {
      return local;
    }
    return this.serverErrors()[field] ?? '';
  }

  save(): void {
    this.form.markAllAsTouched();
    if (this.form.invalid || this.saving()) {
      return;
    }
    const { company_name, legal_name, tax_id } = this.form.getRawValue();
    this.store.saveOrganization({ company_name: company_name.trim(), legal_name: legal_name.trim() || null, tax_id: tax_id.trim() || null });
  }
}
