import { ChangeDetectionStrategy, Component, ElementRef, OnInit, computed, input, output, signal, viewChild } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { RoleAdmin } from '../../core/roles-admin.service';
import { ROLE_LIMITS, RoleFormErrors, RoleFormValues, hasErrors, parentOptions, validateRoleForm } from './roles-ui';

const LABEL = 'text-[12px] font-bold text-on-surface';
const FIELD =
  'mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep aria-[invalid=true]:border-error disabled:bg-surface-container disabled:text-on-surface-variant';

export interface RoleFormResult extends RoleFormValues {
  is_active: boolean;
}

/**
 * Alta y edición de un rol. El padre solo admite roles activos que no sean el propio ni uno de sus
 * descendientes (sin ciclos posibles); un rol base conserva su lugar en la jerarquía. El servidor
 * vuelve a comprobar todo.
 */
@Component({
  selector: 'app-role-form-modal',
  standalone: true,
  imports: [FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
      <div class="absolute inset-0 bg-brand-navy/50" (click)="closed.emit()" aria-hidden="true"></div>
      <form class="glass relative max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-t-2xl sm:rounded-2xl" role="dialog" aria-modal="true"
        aria-labelledby="rf-title" (submit)="submit($event)" novalidate>
        <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
          <h2 id="rf-title" class="text-[16px] font-bold text-on-surface">{{ role() ? 'Editar rol' : 'Nuevo rol' }}</h2>
          <button type="button" (click)="closed.emit()" aria-label="Cerrar"
            class="rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
            <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
          </button>
        </header>

        <div class="space-y-3 px-5 py-4">
          <div>
            <label for="rf-name" [class]="label">Nombre *</label>
            <input #firstField id="rf-name" type="text" [class]="field" autocomplete="off" [attr.maxlength]="limits.nameMax"
              [attr.aria-invalid]="!!shown().name" aria-describedby="rf-name-err" [ngModel]="name()" (ngModelChange)="name.set($event)" name="name" />
            <p id="rf-name-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ shown().name }}</p>
          </div>
          <div>
            <label for="rf-desc" [class]="label">Descripción</label>
            <textarea id="rf-desc" rows="2" [class]="field" [attr.maxlength]="limits.descriptionMax" [attr.aria-invalid]="!!shown().description"
              aria-describedby="rf-desc-err" [ngModel]="description()" (ngModelChange)="description.set($event)" name="description"></textarea>
            <p id="rf-desc-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ shown().description }}</p>
          </div>
          <div>
            <label for="rf-parent" [class]="label">Hereda de</label>
            <select id="rf-parent" [class]="field" [disabled]="locked()" aria-describedby="rf-parent-hint"
              [ngModel]="parent()" (ngModelChange)="parent.set($event === 'null' ? null : +$event)" name="parent">
              <option value="null">Ninguno (rol independiente)</option>
              @for (option of parents(); track option.id) {
                <option [value]="option.id">{{ option.name }}</option>
              }
            </select>
            <p id="rf-parent-hint" class="mt-1 text-[12px] text-on-surface-variant">
              @if (locked()) { Los roles base conservan su lugar en la jerarquía. }
              @else { Tendrá todos los permisos de este rol además de los suyos. }
            </p>
          </div>
          @if (role() && !role()!.is_system) {
            <label class="flex cursor-pointer items-center gap-2 text-[13px] text-on-surface">
              <input type="checkbox" class="h-4 w-4 accent-brand-accentDeep" [ngModel]="active()" (ngModelChange)="active.set($event)" name="active" />
              Rol activo
            </label>
          }
        </div>

        <footer class="flex justify-end gap-2 border-t border-brand-grey/70 px-5 py-3">
          <button type="button" (click)="closed.emit()" [disabled]="busy()"
            class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">Cancelar</button>
          <button type="submit" [disabled]="busy()"
            class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
            {{ busy() ? 'Guardando…' : role() ? 'Guardar cambios' : 'Crear rol' }}
          </button>
        </footer>
      </form>
    </div>
  `,
})
export class RoleFormModalComponent implements OnInit {
  /** Con un rol se edita; sin él se crea. */
  readonly role = input<RoleAdmin | null>(null);
  readonly roles = input<readonly RoleAdmin[]>([]);
  readonly busy = input(false);
  /** Mensaje de campo que devolvió el servidor (p. ej. nombre repetido). */
  readonly serverError = input('');
  readonly saved = output<RoleFormResult>();
  readonly closed = output<void>();

  readonly firstField = viewChild<ElementRef<HTMLInputElement>>('firstField');
  readonly label = LABEL;
  readonly field = FIELD;
  readonly limits = ROLE_LIMITS;

  readonly name = signal('');
  readonly description = signal('');
  readonly parent = signal<number | null>(null);
  readonly active = signal(true);
  private readonly submitted = signal(false);

  readonly locked = computed(() => this.role()?.is_system ?? false);
  readonly parents = computed(() => parentOptions(this.roles(), this.role()?.id ?? null));
  private readonly errors = computed<RoleFormErrors>(() =>
    validateRoleForm({ name: this.name(), description: this.description(), parent_role_id: this.parent() }, this.roles(), this.role()?.id ?? null),
  );
  /** Los errores se muestran al intentar guardar, no mientras se escribe por primera vez. */
  readonly shown = computed<RoleFormErrors>(() => {
    const own = this.submitted() ? this.errors() : {};
    return this.serverError() && !own.name ? { ...own, name: this.serverError() } : own;
  });

  ngOnInit(): void {
    const role = this.role();
    if (role) {
      this.name.set(role.name);
      this.description.set(role.description ?? '');
      this.parent.set(role.parent_role_id);
      this.active.set(role.is_active);
    }
    queueMicrotask(() => this.firstField()?.nativeElement.focus());
  }

  submit(event: Event): void {
    event.preventDefault();
    this.submitted.set(true);
    if (hasErrors(this.errors())) {
      return;
    }
    this.saved.emit({
      name: this.name().trim(),
      description: this.description().trim(),
      parent_role_id: this.parent(),
      is_active: this.active(),
    });
  }
}
