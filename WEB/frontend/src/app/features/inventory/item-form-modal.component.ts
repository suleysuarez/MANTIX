import { ChangeDetectionStrategy, Component, ElementRef, HostListener, OnInit, inject, input, output, viewChild } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { Observable, map } from 'rxjs';

import {
  fieldError, groupError, integerRange, maxNotBelowMin, optionalInteger, optionalMoney, optionalText,
  parseDecimal, requiredText,
} from '../../core/form-validation';
import { INVENTORY_LIMITS, InventoryItem, ItemCategory, OptionKind } from '../../core/inventory.service';
import { InventoryStore } from '../../core/inventory.store';
import { CreatableSelectComponent, SelectOption } from '../../shared/creatable-select.component';
import { CATEGORIES, optionsOf, skuValidator } from './inventory-ui';

/** Campos del servidor (snake_case) a controles del formulario. */
const SERVER_FIELDS: Record<string, string> = {
  sku: 'sku', name: 'name', description: 'description', category: 'category', unit: 'unit', unit_cost: 'unitCost',
  min_stock: 'minStock', max_stock: 'maxStock', initial_stock: 'initialStock', location: 'location', supplier: 'supplier',
};
const LABEL = 'text-[12px] font-bold text-on-surface';
const FIELD =
  'mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep aria-[invalid=true]:border-error';

/** Alta y edición de un ítem. El stock solo cambia con movimientos: aquí se fija únicamente el inicial. */
@Component({
  selector: 'app-item-form-modal',
  standalone: true,
  imports: [ReactiveFormsModule, CreatableSelectComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
      <div class="absolute inset-0 bg-brand-navy/50" (click)="closed.emit()" aria-hidden="true"></div>
      <form class="glass relative max-h-[92vh] w-full max-w-2xl overflow-y-auto rounded-t-2xl sm:rounded-2xl" role="dialog" aria-modal="true"
        aria-labelledby="if-title" [formGroup]="form" (ngSubmit)="submit()" novalidate>
        <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
          <h2 id="if-title" class="text-[16px] font-bold text-on-surface">{{ item() ? 'Editar ítem' : 'Nuevo ítem' }}</h2>
          <button type="button" (click)="closed.emit()" aria-label="Cerrar"
            class="rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
            <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
          </button>
        </header>

        <div class="grid grid-cols-1 gap-x-4 gap-y-3 px-5 py-4 sm:grid-cols-2">
          <div>
            <label for="if-sku" [class]="label">Código (SKU) *</label>
            <input #firstField id="if-sku" type="text" formControlName="sku" [class]="field" autocomplete="off" [attr.aria-invalid]="invalid('sku')" aria-describedby="if-sku-err" />
            <p id="if-sku-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('sku') }}</p>
          </div>
          <div>
            <label for="if-category" [class]="label">Categoría *</label>
            <app-creatable-select class="mt-1" formControlName="category" ariaLabel="Categoría" placeholder="Selecciona una categoría"
              [options]="choices('category')" [create]="creator('category')" [maxLength]="30" [invalid]="invalid('category')" />
            <p class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('category') }}</p>
          </div>
          <div class="sm:col-span-2">
            <label for="if-name" [class]="label">Nombre *</label>
            <input id="if-name" type="text" formControlName="name" [class]="field" [attr.aria-invalid]="invalid('name')" aria-describedby="if-name-err" />
            <p id="if-name-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('name') }}</p>
          </div>
          <div class="sm:col-span-2">
            <label for="if-description" [class]="label">Descripción</label>
            <textarea id="if-description" rows="2" formControlName="description" [class]="field" [attr.aria-invalid]="invalid('description')" aria-describedby="if-description-err"></textarea>
            <p id="if-description-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('description') }}</p>
          </div>
          <div>
            <label for="if-unit" [class]="label">Unidad *</label>
            <app-creatable-select class="mt-1" formControlName="unit" ariaLabel="Unidad" placeholder="Selecciona una unidad"
              [options]="choices('unit')" [create]="creator('unit')" [minLength]="1" [maxLength]="20" [invalid]="invalid('unit')" />
            <p id="if-unit-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('unit') }}</p>
          </div>
          <div>
            <label for="if-cost" [class]="label">Costo unitario</label>
            <input id="if-cost" type="text" inputmode="decimal" formControlName="unitCost" placeholder="0.00" [class]="field" [attr.aria-invalid]="invalid('unitCost')" aria-describedby="if-cost-err" />
            <p id="if-cost-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('unitCost') }}</p>
          </div>
          @if (!item()) {
            <div>
              <label for="if-initial" [class]="label">Stock inicial</label>
              <input id="if-initial" type="number" inputmode="numeric" min="0" step="1" formControlName="initialStock" [class]="field" [attr.aria-invalid]="invalid('initialStock')" aria-describedby="if-initial-err" />
              <p id="if-initial-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('initialStock') }}</p>
            </div>
          } @else {
            <p class="self-end pb-5 text-[12px] text-on-surface-variant">El stock actual ({{ item()!.stock }}) cambia solo con movimientos.</p>
          }
          <div></div>
          <div>
            <label for="if-min" [class]="label">Stock mínimo *</label>
            <input id="if-min" type="number" inputmode="numeric" min="0" step="1" formControlName="minStock" [class]="field" [attr.aria-invalid]="invalid('minStock')" aria-describedby="if-min-err" />
            <p id="if-min-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('minStock') }}</p>
          </div>
          <div>
            <label for="if-max" [class]="label">Stock máximo</label>
            <input id="if-max" type="number" inputmode="numeric" min="0" step="1" formControlName="maxStock" [class]="field" [attr.aria-invalid]="invalid('maxStock') || groupMessage() !== ''" aria-describedby="if-max-err" />
            <p id="if-max-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('maxStock') || groupMessage() }}</p>
          </div>
          <div>
            <label for="if-location" [class]="label">Ubicación</label>
            <app-creatable-select class="mt-1" formControlName="location" ariaLabel="Ubicación" placeholder="Sin ubicación"
              [options]="choices('location')" [create]="creator('location')" [maxLength]="100" [invalid]="invalid('location')" />
            <p id="if-location-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('location') }}</p>
          </div>
          <div>
            <label for="if-supplier" [class]="label">Proveedor</label>
            <app-creatable-select class="mt-1" formControlName="supplier" ariaLabel="Proveedor" placeholder="Sin proveedor"
              [options]="choices('supplier')" [create]="creator('supplier')" [maxLength]="150" [invalid]="invalid('supplier')" />
            <p id="if-supplier-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('supplier') }}</p>
          </div>
        </div>

        <footer class="flex justify-end gap-2 border-t border-brand-grey/70 px-5 py-3">
          <button type="button" (click)="closed.emit()" [disabled]="busy()"
            class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">Cancelar</button>
          <button type="submit" [disabled]="form.invalid || busy()"
            class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
            {{ busy() ? 'Guardando…' : item() ? 'Guardar cambios' : 'Crear ítem' }}
          </button>
        </footer>
      </form>
    </div>
  `,
})
export class ItemFormModalComponent implements OnInit {
  private readonly store = inject(InventoryStore);

  /** Con un ítem se edita; sin él se crea. */
  readonly item = input<InventoryItem | null>(null);
  readonly busy = input(false);
  readonly closed = output<void>();

  readonly firstField = viewChild<ElementRef<HTMLInputElement>>('firstField');
  readonly label = LABEL;
  readonly field = FIELD;
  private readonly state = toSignal(this.store.state$, { initialValue: null });

  readonly form = new FormGroup(
    {
      sku: new FormControl('', { nonNullable: true, validators: [skuValidator] }),
      name: new FormControl('', { nonNullable: true, validators: [requiredText(3, 200)] }),
      description: new FormControl('', { nonNullable: true, validators: [optionalText(2000)] }),
      category: new FormControl<ItemCategory | null>('spare_part', { validators: [Validators.required] }),
      unit: new FormControl<string | null>('unidad', { validators: [Validators.required] }),
      unitCost: new FormControl('', { nonNullable: true, validators: [optionalMoney(INVENTORY_LIMITS.maxCost)] }),
      initialStock: new FormControl<number | string>(0, { validators: [optionalInteger(0, INVENTORY_LIMITS.maxQuantity)] }),
      minStock: new FormControl<number | string>(0, { validators: [integerRange(0, INVENTORY_LIMITS.maxQuantity)] }),
      maxStock: new FormControl<number | string | null>(null, { validators: [optionalInteger(0, INVENTORY_LIMITS.maxQuantity)] }),
      location: new FormControl<string | null>(null),
      supplier: new FormControl<string | null>(null),
    },
    { validators: maxNotBelowMin('minStock', 'maxStock') },
  );

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closed.emit();
  }

  /**
   * Opciones de un desplegable: las del servidor y, si el ítem ya trae un valor que aún no figura
   * (datos anteriores), ese también, para que se vea seleccionado.
   */
  choices(kind: OptionKind): SelectOption[] {
    const list: SelectOption[] = optionsOf(this.state()?.options ?? [], kind);
    if (kind === 'category' && list.length === 0) {
      list.push(...CATEGORIES.map((c) => ({ value: c.code, label: c.label })));
    }
    const current = this.form.get(kind)?.value as string | null | undefined;
    return current && !list.some((o) => o.value === current) ? [...list, { value: current, label: current }] : list;
  }

  /** Función que guarda un valor nuevo en el servidor (`+ Agregar nuevo`) y devuelve la opción creada. */
  creator(kind: OptionKind): (name: string) => Observable<SelectOption> {
    return (name) => this.store.createOption(kind, name).pipe(map((o) => ({ value: o.value, label: o.label })));
  }

  error = (name: string): string => fieldError(this.form.get(name));
  invalid = (name: string): boolean => !!this.form.get(name)?.invalid && !!this.form.get(name)?.touched;
  groupMessage = (): string => (this.form.touched ? groupError(this.form) : '');

  ngOnInit(): void {
    const item = this.item();
    if (item) {
      this.form.controls.sku.disable();
      this.form.controls.initialStock.disable();
      this.form.patchValue({
        sku: item.sku, name: item.name, description: item.description ?? '', category: item.category, unit: item.unit,
        unitCost: item.unit_cost, minStock: item.min_stock, maxStock: item.max_stock, location: item.location,
        supplier: item.supplier,
      });
    }
    setTimeout(() => this.firstField()?.nativeElement.focus());
  }

  submit(): void {
    this.form.markAllAsTouched();
    if (this.form.invalid || this.busy()) {
      return;
    }
    const v = this.form.getRawValue();
    const common = {
      name: v.name.trim(),
      description: v.description.trim() || null,
      category: v.category ?? 'spare_part',
      unit: (v.unit ?? '').trim(),
      unit_cost: parseDecimal(v.unitCost) ?? 0,
      min_stock: Number(v.minStock),
      max_stock: v.maxStock === null || String(v.maxStock).trim() === '' ? null : Number(v.maxStock),
      location: v.location?.trim() || null,
      supplier: v.supplier?.trim() || null,
    };
    const item = this.item();
    const call = item
      ? this.store.update(item.id, common)
      : this.store.create({ ...common, sku: v.sku.trim().toUpperCase(), initial_stock: Number(v.initialStock || 0) });
    call.subscribe((result) => {
      if (result.ok) {
        this.closed.emit();
        return;
      }
      for (const [serverField, message] of Object.entries(result.fieldErrors)) {
        const control = this.form.get(SERVER_FIELDS[serverField] ?? serverField);
        control?.setErrors({ server: message });
        control?.markAsTouched();
      }
    });
  }
}
