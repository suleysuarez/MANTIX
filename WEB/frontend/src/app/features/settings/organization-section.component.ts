import { ChangeDetectionStrategy, Component, effect, inject, input } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';

import { fieldError, requiredText } from '../../core/form-validation';
import { Organization } from '../../core/settings.service';
import { SettingsStore } from '../../core/settings.store';

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `mt-1 w-full rounded-lg border border-brand-grey bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface ${FOCUS}`;
/** Nombre de la empresa que aparece en el encabezado de los PDF y Excel que se exportan. */
@Component({
  selector: 'app-organization-section',
  standalone: true,
  imports: [ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section aria-labelledby="org-title" class="space-y-4">
      <header>
        <h2 id="org-title" class="text-[18px] font-bold text-on-surface">Organización</h2>
        <p class="text-[13px] text-on-surface-variant">El nombre sale en el encabezado de los reportes que exportas a PDF y Excel.</p>
      </header>

      @if (error()) { <p role="alert" class="rounded-lg bg-error-container px-3 py-2 text-[13px] text-on-error-container">{{ error() }}</p> }

      @if (loading() && !organization()) {
        <div class="h-48 animate-pulse rounded-2xl bg-surface-container motion-reduce:animate-none" role="status" aria-label="Cargando organización"></div>
      } @else {
        @if (organization() && !organization()!.configured) {
          <p class="rounded-lg bg-secondary-fixed px-3 py-2 text-[12px] font-semibold text-on-secondary-fixed" role="status">
            Aún no hay un nombre guardado: los reportes dicen «Mantix».
          </p>
        }
        <form [formGroup]="form" (ngSubmit)="save()" novalidate class="glass grid gap-4 rounded-2xl p-5" aria-label="Datos de la organización">
          <div>
            <label for="org-name" class="text-[12px] font-bold text-on-surface">Nombre de la empresa</label>
            <input id="org-name" formControlName="company_name" maxlength="150" autocomplete="organization" [attr.aria-invalid]="!!error$('company_name')" aria-describedby="org-name-err" [class]="field" />
            <p id="org-name-err" class="min-h-4 text-[11px] text-error" role="alert">{{ error$('company_name') }}</p>
          </div>
          @if (canManage()) {
            <div>
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
  });

  constructor() {
    // El formulario parte de lo guardado y se vuelve a llenar tras guardar.
    effect(() => {
      const org = this.organization();
      if (org) {
        this.form.reset({ company_name: org.company_name });
      }
      if (!this.canManage()) {
        this.form.disable({ emitEvent: false });
      }
    });
  }

  error$(field: 'company_name'): string {
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
    this.store.saveOrganization({ company_name: this.form.getRawValue().company_name.replace(/\s+/g, ' ').trim() });
  }
}
