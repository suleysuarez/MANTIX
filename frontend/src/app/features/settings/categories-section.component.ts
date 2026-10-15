import { ChangeDetectionStrategy, Component, computed, inject, input, signal } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';

import { fieldError, requiredText } from '../../core/form-validation';
import { CategoryAdmin } from '../../core/settings.service';
import { SettingsStore } from '../../core/settings.store';

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const CODE_PATTERN = /^[a-z][a-z_]{1,29}$/;

/** Catálogo de categorías de solicitud: alta, renombrado, (des)activación y borrado de las que nadie usa. */
@Component({
  selector: 'app-categories-section',
  standalone: true,
  imports: [ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section aria-labelledby="cat-title" class="space-y-4">
      <header>
        <h2 id="cat-title" class="text-[18px] font-bold text-on-surface">Categorías de solicitud</h2>
        <p class="text-[13px] text-on-surface-variant">Clasifican las solicitudes de mantenimiento. Una categoría en uso no se puede borrar: desactívala.</p>
      </header>

      @if (canManage()) {
        <form [formGroup]="form" (ngSubmit)="create()" novalidate class="glass grid gap-3 rounded-2xl p-4 sm:grid-cols-[1fr_1fr_auto] sm:items-start" aria-label="Nueva categoría">
          <div>
            <label for="cat-name" class="text-[12px] font-bold text-on-surface">Nombre</label>
            <input id="cat-name" formControlName="name" maxlength="100" autocomplete="off" [attr.aria-invalid]="!!error('name')" aria-describedby="cat-name-err"
              class="mt-1 w-full rounded-lg border border-brand-grey bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface" />
            <p id="cat-name-err" class="min-h-4 text-[11px] text-error" role="alert">{{ error('name') }}</p>
          </div>
          <div>
            <label for="cat-code" class="text-[12px] font-bold text-on-surface">Identificador</label>
            <input id="cat-code" formControlName="code" maxlength="30" autocomplete="off" [attr.aria-invalid]="!!error('code')" aria-describedby="cat-code-err"
              class="mt-1 w-full rounded-lg border border-brand-grey bg-surface-container-lowest px-3 py-2 font-mono text-[13px] text-on-surface" />
            <p id="cat-code-err" class="min-h-4 text-[11px] text-error" role="alert">{{ error('code') }}</p>
          </div>
          <button type="submit" [disabled]="form.invalid || saving()" [class]="primary + ' sm:mt-5'">{{ saving() ? 'Guardando…' : 'Añadir' }}</button>
        </form>
      }

      @if (error$()) { <p role="alert" class="rounded-lg bg-error-container px-3 py-2 text-[13px] text-on-error-container">{{ error$() }}</p> }

      @if (loading() && categories().length === 0) {
        <div class="space-y-2" role="status" aria-label="Cargando categorías">
          @for (n of skeleton; track n) { <div class="h-12 animate-pulse rounded-xl bg-surface-container motion-reduce:animate-none"></div> }
        </div>
      } @else if (categories().length === 0 && !error$()) {
        <p class="rounded-xl bg-surface-container px-4 py-6 text-center text-[13px] text-on-surface-variant">Aún no hay categorías. Añade la primera.</p>
      } @else {
        <ul class="divide-y divide-brand-grey/60 rounded-2xl border border-brand-grey bg-surface-container-lowest">
          @for (c of categories(); track c.id) {
            <li class="flex flex-wrap items-center gap-3 px-4 py-3">
              @if (editing() === c.id) {
                <form [formGroup]="rename" (ngSubmit)="saveName(c)" novalidate class="flex flex-1 flex-wrap items-start gap-2">
                  <div class="min-w-[12rem] flex-1">
                    <label [for]="'ren-' + c.id" class="sr-only">Nuevo nombre de {{ c.name }}</label>
                    <input [id]="'ren-' + c.id" formControlName="name" maxlength="100" [attr.aria-invalid]="!!renameError()"
                      class="w-full rounded-lg border border-brand-grey bg-surface-container-lowest px-3 py-1.5 text-[13px] text-on-surface" />
                    <p class="min-h-4 text-[11px] text-error" role="alert">{{ renameError() }}</p>
                  </div>
                  <button type="submit" [disabled]="rename.invalid || saving()" [class]="primary">Guardar</button>
                  <button type="button" (click)="editing.set(null)" [class]="ghost">Cancelar</button>
                </form>
              } @else {
                <div class="min-w-0 flex-1">
                  <p class="truncate text-[14px] font-semibold text-on-surface">{{ c.name }}</p>
                  <p class="text-[11px] text-on-surface-variant"><span class="font-mono">{{ c.code }}</span> · {{ c.usage }} {{ c.usage === 1 ? 'solicitud' : 'solicitudes' }}</p>
                </div>
                <span class="rounded-full px-2.5 py-0.5 text-[11px] font-bold" [class]="c.is_active ? 'bg-brand-accentLight/60 text-brand-accentDeep' : 'bg-surface-container-high text-on-surface-variant'">{{ c.is_active ? 'Activa' : 'Inactiva' }}</span>
                @if (canManage()) {
                  @if (confirm()?.id === c.id) {
                    <span class="flex flex-wrap items-center gap-2 text-[12px] text-on-surface" role="alertdialog" [attr.aria-label]="'Confirmar ' + confirm()!.action">
                      {{ confirmText(c) }}
                      <button type="button" (click)="confirmed(c)" [disabled]="saving()" [class]="danger">Confirmar</button>
                      <button type="button" (click)="confirm.set(null)" [class]="ghost">Volver</button>
                    </span>
                  } @else {
                    <button type="button" (click)="startEdit(c)" [class]="ghost">Renombrar</button>
                    <button type="button" (click)="confirm.set({ id: c.id, action: c.is_active ? 'desactivar' : 'reactivar' })" [disabled]="saving()" [class]="ghost">{{ c.is_active ? 'Desactivar' : 'Reactivar' }}</button>
                    @if (c.usage === 0) { <button type="button" (click)="confirm.set({ id: c.id, action: 'eliminar' })" [disabled]="saving()" [class]="ghost">Eliminar</button> }
                  }
                }
              }
            </li>
          }
        </ul>
      }
    </section>
  `,
})
export class CategoriesSectionComponent {
  private readonly store = inject(SettingsStore);

  readonly categories = input.required<CategoryAdmin[]>();
  readonly loading = input(false);
  readonly error$ = input('');
  readonly saving = input(false);
  readonly canManage = input(true);
  readonly serverErrors = input<Record<string, string>>({});

  readonly skeleton = [1, 2, 3];
  readonly editing = signal<number | null>(null);
  readonly confirm = signal<{ id: number; action: 'desactivar' | 'reactivar' | 'eliminar' } | null>(null);

  readonly primary = `${FOCUS} glass-btn rounded-lg px-4 py-2 text-[13px] font-bold disabled:opacity-50`;
  readonly ghost = `${FOCUS} rounded-lg bg-transparent px-2.5 py-1.5 text-[12px] font-bold !text-brand-accentDeep hover:bg-surface-container-high disabled:opacity-50`;
  readonly danger = `${FOCUS} rounded-lg bg-error px-3 py-1.5 text-[12px] font-bold !text-on-error disabled:opacity-50`;

  readonly form = new FormGroup({
    name: new FormControl('', { nonNullable: true, validators: [requiredText(3, 100)] }),
    code: new FormControl('', {
      nonNullable: true,
      validators: [(control) => (CODE_PATTERN.test(String(control.value ?? '')) ? null : { pattern: true })],
    }),
  });
  readonly rename = new FormGroup({ name: new FormControl('', { nonNullable: true, validators: [requiredText(3, 100)] }) });
  readonly renameError = computed(() => (this.rename.dirty ? fieldError(this.rename.controls.name, true) : '') || this.serverErrors()['name'] || '');

  error(field: 'name' | 'code'): string {
    return fieldError(this.form.controls[field]) || this.serverErrors()[field] || '';
  }

  create(): void {
    if (this.form.invalid || this.saving()) {
      this.form.markAllAsTouched();
      return;
    }
    const { name, code } = this.form.getRawValue();
    this.store.createCategory({ name: name.trim(), code }, () => this.form.reset());
  }

  startEdit(category: CategoryAdmin): void {
    this.confirm.set(null);
    this.rename.reset({ name: category.name });
    this.editing.set(category.id);
  }

  saveName(category: CategoryAdmin): void {
    if (this.rename.invalid || this.saving()) {
      return;
    }
    this.store.renameCategory(category, this.rename.getRawValue().name.trim(), () => this.editing.set(null));
  }

  confirmText(category: CategoryAdmin): string {
    switch (this.confirm()?.action) {
      case 'eliminar':
        return `¿Eliminar «${category.name}»? No se puede deshacer.`;
      case 'desactivar':
        return `¿Desactivar «${category.name}»? Dejará de ofrecerse en solicitudes nuevas.`;
      default:
        return `¿Reactivar «${category.name}»?`;
    }
  }

  confirmed(category: CategoryAdmin): void {
    const action = this.confirm()?.action;
    this.confirm.set(null);
    if (action === 'eliminar') {
      this.store.deleteCategory(category);
    } else {
      this.store.toggleCategory(category);
    }
  }
}
