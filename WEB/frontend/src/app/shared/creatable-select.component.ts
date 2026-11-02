import { ChangeDetectionStrategy, Component, computed, forwardRef, input, output, signal } from '@angular/core';
import { ControlValueAccessor, NG_VALUE_ACCESSOR } from '@angular/forms';
import { Observable } from 'rxjs';

import { apiErrorMessage } from '../core/api-errors';

export interface SelectOption {
  value: string | number;
  label: string;
}

const NEW = '__new__';
const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
let nextId = 0;

/** Compara sin distinguir mayúsculas, tildes ni espacios sobrantes: «Redes», «redes » y «REDES» son lo mismo. */
export function sameName(a: string, b: string): boolean {
  const key = (value: string) => value.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim().toLowerCase();
  return key(a) === key(b);
}

/**
 * Desplegable con «+ Agregar nuevo»: al elegirlo aparece un campo para escribir el valor, se guarda en el
 * servidor con `create`, la lista se actualiza al instante y el valor nuevo queda seleccionado, sin recargar.
 * Sin `canCreate` (permiso del rol) la opción no existe; un nombre repetido (sin distinguir mayúsculas)
 * selecciona el que ya está en vez de duplicarlo. Sirve con `[value]`/`(valueChange)` y con formularios reactivos.
 */
@Component({
  selector: 'app-creatable-select',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  providers: [{ provide: NG_VALUE_ACCESSOR, useExisting: forwardRef(() => CreatableSelectComponent), multi: true }],
  host: { class: 'block' },
  template: `
    @if (!adding()) {
      <select [id]="id" [attr.aria-label]="ariaLabel() || null" [attr.aria-invalid]="invalid()" [disabled]="disabled()"
        (change)="onSelect($any($event.target).value)" [class]="selectClass()">
        <option value="" [selected]="current() === null">{{ placeholder() }}</option>
        @for (o of all(); track o.value) {
          <option [value]="o.value" [selected]="current() !== null && '' + current() === '' + o.value">{{ o.label }}</option>
        }
        @if (canCreate()) {
          <option [value]="newToken">+ {{ createLabel() }}</option>
        }
      </select>
    } @else {
      <div class="space-y-1.5" role="group" [attr.aria-label]="createLabel()">
        <div class="flex gap-2">
          <input [id]="id + '-new'" type="text" [value]="draft()" (input)="draft.set($any($event.target).value); dirty.set(true)" (keydown.enter)="$event.preventDefault(); save()"
            (keydown.escape)="cancel()" [attr.maxlength]="maxLength() + 20" autocomplete="off" [attr.aria-invalid]="!!error()" [attr.aria-describedby]="id + '-err'"
            [attr.aria-label]="createLabel()" placeholder="Escribe el nombre" [disabled]="busy()" [class]="inputClass" />
          <button type="button" (click)="save()" [disabled]="busy() || !!validation()" [class]="focus + ' glass-btn rounded-lg px-3 text-[12px] font-bold disabled:opacity-50'">{{ busy() ? 'Guardando…' : 'Guardar' }}</button>
          <button type="button" (click)="cancel()" [disabled]="busy()" [class]="focus + ' rounded-lg bg-transparent px-2 text-[12px] font-bold !text-brand-accentDeep hover:bg-surface-container-high'">Cancelar</button>
        </div>
        <p [id]="id + '-err'" class="min-h-4 text-[12px] text-error" role="alert">{{ error() || (dirty() ? validation() : '') }}</p>
      </div>
    }
  `,
})
export class CreatableSelectComponent implements ControlValueAccessor {
  readonly options = input<SelectOption[]>([]);
  readonly value = input<string | number | null>(null);
  readonly placeholder = input('Selecciona…');
  readonly createLabel = input('Agregar nuevo');
  /** Guarda el valor nuevo en el servidor y devuelve la opción creada. */
  readonly create = input<((name: string) => Observable<SelectOption>) | null>(null);
  /** Permiso del rol: sin él no hay opción «+ Agregar nuevo». */
  readonly canCreate = input(true);
  readonly minLength = input(2);
  readonly maxLength = input(100);
  readonly ariaLabel = input('');
  readonly invalid = input(false);

  readonly valueChange = output<string | number | null>();
  readonly created = output<SelectOption>();

  readonly id = `cs-${nextId++}`;
  readonly newToken = NEW;
  readonly focus = FOCUS;
  readonly inputClass = `${FOCUS} h-10 min-w-0 flex-1 rounded-lg border border-outline bg-surface-container-lowest px-3 text-[13px] text-on-surface`;

  readonly adding = signal(false);
  readonly draft = signal('');
  readonly dirty = signal(false);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly disabled = signal(false);
  /** Valor elegido (el del padre o el que se acaba de crear). */
  private readonly chosen = signal<string | number | null | undefined>(undefined);
  /** Opciones creadas aquí: aparecen al instante aunque el padre aún no haya recargado su lista. */
  private readonly added = signal<SelectOption[]>([]);

  readonly current = computed(() => (this.chosen() !== undefined ? (this.chosen() as string | number | null) : this.value()));
  readonly all = computed(() => {
    const own = this.options();
    return [...own, ...this.added().filter((a) => !own.some((o) => '' + o.value === '' + a.value))];
  });
  readonly validation = computed(() => {
    const name = this.draft().replace(/\s+/g, ' ').trim();
    if (!name) {
      return 'Escribe el nombre.';
    }
    if (name.length < this.minLength()) {
      return `Debe tener al menos ${this.minLength()} caracteres.`;
    }
    return name.length > this.maxLength() ? `Debe tener como máximo ${this.maxLength()} caracteres.` : '';
  });
  readonly selectClass = computed(
    () => `${FOCUS} h-10 w-full rounded-lg border bg-surface-container-lowest px-3 text-[13px] text-on-surface ${this.invalid() ? 'border-error' : 'border-outline'}`,
  );

  private onChange: (value: string | number | null) => void = () => undefined;
  private onTouched: () => void = () => undefined;

  writeValue(value: string | number | null): void {
    this.chosen.set(value);
  }

  registerOnChange(fn: (value: string | number | null) => void): void {
    this.onChange = fn;
  }

  registerOnTouched(fn: () => void): void {
    this.onTouched = fn;
  }

  setDisabledState(disabled: boolean): void {
    this.disabled.set(disabled);
  }

  onSelect(raw: string): void {
    if (raw === NEW) {
      this.draft.set('');
      this.dirty.set(false);
      this.error.set('');
      this.adding.set(true);
      return;
    }
    const found = this.all().find((o) => '' + o.value === raw);
    this.pick(raw === '' ? null : (found?.value ?? raw));
  }

  save(): void {
    this.dirty.set(true);
    const create = this.create();
    if (this.busy() || this.validation() || !create) {
      return;
    }
    const name = this.draft().replace(/\s+/g, ' ').trim();
    const existing = this.all().find((o) => sameName(o.label, name));
    if (existing) {
      // Sin duplicados: se usa el que ya estaba, sin llamar al servidor.
      this.adding.set(false);
      this.pick(existing.value);
      return;
    }
    this.busy.set(true);
    this.error.set('');
    create(name).subscribe({
      next: (option) => {
        this.busy.set(false);
        this.added.update((list) => [...list, option]);
        this.adding.set(false);
        this.created.emit(option);
        this.pick(option.value);
      },
      error: (error) => {
        this.busy.set(false);
        this.error.set(apiErrorMessage(error, 'No se pudo guardar el valor nuevo.'));
      },
    });
  }

  cancel(): void {
    if (!this.busy()) {
      this.adding.set(false);
    }
  }

  private pick(value: string | number | null): void {
    this.chosen.set(value);
    this.onChange(value);
    this.onTouched();
    this.valueChange.emit(value);
  }
}
