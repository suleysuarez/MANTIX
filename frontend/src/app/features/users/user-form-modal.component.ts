import { ChangeDetectionStrategy, Component, ElementRef, HostListener, OnInit, computed, inject, input, output, signal, viewChild } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';
import { map, startWith } from 'rxjs';

import { AdminRole } from '../../core/admin-users.service';
import { ManagedAccount } from '../../core/users.service';
import { UsersStore } from '../../core/users.store';
import { USER_LIMITS, UserFormErrors, UserFormValues, hasErrors, validateUserForm } from './users-ui';

const LABEL = 'text-[12px] font-bold text-on-surface';
const FIELD =
  'mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep aria-[invalid=true]:border-error disabled:bg-surface-container disabled:text-on-surface-variant';

/** Campos del servidor a controles del formulario. */
const SERVER_FIELDS = ['full_name', 'email', 'phone', 'employee_code', 'role_ids'] as const;

/**
 * Alta y edición de un usuario. El alta es un pre-registro: la persona entra con ese correo y la
 * contraseña la gestiona el servicio de acceso. En edición el correo se bloquea cuando la persona
 * ya inició sesión (el backend también lo rechaza).
 */
@Component({
  selector: 'app-user-form-modal',
  standalone: true,
  imports: [ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
      <div class="absolute inset-0 bg-brand-navy/50" (click)="closed.emit()" aria-hidden="true"></div>
      <form class="glass relative max-h-[92vh] w-full max-w-xl overflow-y-auto rounded-t-2xl sm:rounded-2xl" role="dialog" aria-modal="true"
        aria-labelledby="uf-title" [formGroup]="form" (ngSubmit)="submit()" novalidate>
        <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
          <h2 id="uf-title" class="text-[16px] font-bold text-on-surface">{{ user() ? 'Editar usuario' : 'Nuevo usuario' }}</h2>
          <button type="button" (click)="closed.emit()" aria-label="Cerrar"
            class="rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
            <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
          </button>
        </header>

        <div class="grid grid-cols-1 gap-x-4 gap-y-3 px-5 py-4 sm:grid-cols-2">
          <div class="sm:col-span-2">
            <label for="uf-name" [class]="label">Nombre completo {{ user() ? '' : '*' }}</label>
            <input #firstField id="uf-name" type="text" formControlName="full_name" [class]="field" autocomplete="off"
              [attr.maxlength]="limits.nameMax" [attr.aria-invalid]="!!shown('full_name')" aria-describedby="uf-name-err" />
            @if (user()) {
              <p id="uf-name-hint" class="mt-1 text-[12px] text-on-surface-variant">Cada persona edita su nombre desde su perfil.</p>
            }
            <p id="uf-name-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ shown('full_name') }}</p>
          </div>
          <div class="sm:col-span-2">
            <label for="uf-email" [class]="label">Correo *</label>
            <input id="uf-email" type="email" formControlName="email" [class]="field" autocomplete="off"
              [attr.aria-invalid]="!!shown('email')" aria-describedby="uf-email-err uf-email-hint" />
            <p id="uf-email-hint" class="mt-1 text-[12px] text-on-surface-variant">
              @if (emailLocked()) { Esta persona ya inició sesión: su correo no se puede cambiar. }
              @else { Con este correo entrará a Mantix; la contraseña la crea ella misma al registrarse. }
            </p>
            <p id="uf-email-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ shown('email') }}</p>
          </div>
          <div>
            <label for="uf-phone" [class]="label">Teléfono</label>
            <input id="uf-phone" type="tel" formControlName="phone" [class]="field" autocomplete="off" [attr.maxlength]="limits.phoneMax"
              placeholder="+57 300 123 4567" [attr.aria-invalid]="!!shown('phone')" aria-describedby="uf-phone-err" />
            <p id="uf-phone-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ shown('phone') }}</p>
          </div>
          <div>
            <label for="uf-code" [class]="label">Código de empleado</label>
            <input id="uf-code" type="text" formControlName="employee_code" [class]="field" autocomplete="off" [attr.maxlength]="limits.codeMax"
              placeholder="EMP-014" [attr.aria-invalid]="!!shown('employee_code')" aria-describedby="uf-code-err" />
            <p id="uf-code-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ shown('employee_code') }}</p>
          </div>

          <fieldset class="sm:col-span-2" [attr.aria-describedby]="'uf-roles-err'">
            <legend [class]="label">Roles *</legend>
            <div class="mt-1 grid grid-cols-1 gap-2 sm:grid-cols-2">
              @for (role of roles(); track role.id) {
                <label class="flex cursor-pointer items-center gap-2 rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface">
                  <input type="checkbox" class="h-4 w-4 accent-brand-accentDeep" [checked]="selectedRoles().includes(role.id)" (change)="toggleRole(role.id)" />
                  {{ role.name }}
                </label>
              }
            </div>
            <p id="uf-roles-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ shown('role_ids') }}</p>
          </fieldset>
        </div>

        <footer class="flex justify-end gap-2 border-t border-brand-grey/70 px-5 py-3">
          <button type="button" (click)="closed.emit()" [disabled]="busy()"
            class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">Cancelar</button>
          <button type="submit" [disabled]="busy()"
            class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
            {{ busy() ? 'Guardando…' : user() ? 'Guardar cambios' : 'Registrar usuario' }}
          </button>
        </footer>
      </form>
    </div>
  `,
})
export class UserFormModalComponent implements OnInit {
  private readonly store = inject(UsersStore);

  /** Con un usuario se edita; sin él se crea. */
  readonly user = input<ManagedAccount | null>(null);
  readonly roles = input<AdminRole[]>([]);
  readonly busy = input(false);
  readonly closed = output<void>();

  readonly firstField = viewChild<ElementRef<HTMLInputElement>>('firstField');
  readonly label = LABEL;
  readonly field = FIELD;
  readonly limits = USER_LIMITS;

  readonly form = new FormGroup({
    full_name: new FormControl('', { nonNullable: true }),
    email: new FormControl('', { nonNullable: true }),
    phone: new FormControl('', { nonNullable: true }),
    employee_code: new FormControl('', { nonNullable: true }),
  });
  readonly selectedRoles = signal<number[]>([]);
  private readonly submitted = signal(false);
  private readonly serverErrors = signal<UserFormErrors>({});
  private readonly values = toSignal(this.form.valueChanges.pipe(map(() => this.form.getRawValue()), startWith(this.form.getRawValue())), { initialValue: this.form.getRawValue() });

  readonly emailLocked = computed(() => this.user()?.linked === true);
  readonly errors = computed<UserFormErrors>(() => {
    const local = validateUserForm({ ...(this.values() as Omit<UserFormValues, 'role_ids'>), role_ids: this.selectedRoles() }, true);
    return { ...local, ...this.serverErrors() };
  });

  /** El mensaje de un campo, una vez que la persona lo tocó o intentó guardar. */
  shown(name: keyof UserFormValues): string {
    const touched = name === 'role_ids' ? this.submitted() : this.submitted() || !!this.form.get(name)?.touched;
    return touched ? (this.errors()[name] ?? '') : '';
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closed.emit();
  }

  ngOnInit(): void {
    const user = this.user();
    if (user) {
      this.form.patchValue({
        full_name: user.full_name, email: user.email, phone: user.phone ?? '', employee_code: user.employee_code ?? '',
      });
      this.selectedRoles.set(user.roles.map((role) => role.id));
      this.form.controls.full_name.disable(); // lo edita cada persona desde su perfil
      if (user.linked) {
        this.form.controls.email.disable();
      }
    }
    this.form.valueChanges.subscribe(() => this.serverErrors.set({}));
    setTimeout(() => this.firstField()?.nativeElement.focus());
  }

  toggleRole(id: number): void {
    const current = this.selectedRoles();
    this.selectedRoles.set(current.includes(id) ? current.filter((value) => value !== id) : [...current, id]);
    this.serverErrors.set({});
  }

  submit(): void {
    this.submitted.set(true);
    this.form.markAllAsTouched();
    if (hasErrors(this.errors()) || this.busy()) {
      return;
    }
    const v = this.form.getRawValue();
    const name = v.full_name.trim().replace(/\s+/g, ' ');
    const common = {
      phone: v.phone.trim() || null,
      employee_code: v.employee_code.trim() || null,
    };
    const user = this.user();
    if (user) {
      this.finish(this.store.update(user.id, user.linked ? common : { ...common, email: v.email.trim() }), user);
      return;
    }
    this.finish(this.store.create({ ...common, full_name: name, email: v.email.trim(), role_ids: this.selectedRoles() }), null);
  }

  /** Al editar, los roles viajan aparte: solo se llama si cambiaron. */
  private finish(call: ReturnType<UsersStore['create']>, user: ManagedAccount | null): void {
    call.subscribe((result) => {
      if (!result.ok) {
        this.showServerErrors(result.fieldErrors);
        return;
      }
      if (user && this.rolesChanged(user)) {
        this.store.replaceRoles(user.id, this.selectedRoles()).subscribe(() => this.closed.emit());
        return;
      }
      this.closed.emit();
    });
  }

  private rolesChanged(user: ManagedAccount): boolean {
    const before = user.roles.map((role) => role.id).sort();
    const after = [...this.selectedRoles()].sort();
    return before.length !== after.length || before.some((id, index) => id !== after[index]);
  }

  private showServerErrors(fieldErrors: Record<string, string>): void {
    const mapped: UserFormErrors = {};
    for (const field of SERVER_FIELDS) {
      if (fieldErrors[field]) {
        mapped[field] = fieldErrors[field];
      }
    }
    this.serverErrors.set(mapped);
  }
}
