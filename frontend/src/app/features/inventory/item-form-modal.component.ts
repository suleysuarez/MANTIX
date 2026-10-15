import { ChangeDetectionStrategy, Component, ElementRef, HostListener, OnInit, inject, input, output, viewChild } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';

import {
  fieldError, groupError, integerRange, maxNotBelowMin, optionalInteger, optionalMoney, optionalText,
  parseDecimal, requiredText,
} from '../../core/form-validation';
import { INVENTORY_LIMITS, InventoryItem, ItemCategory } from '../../core/inventory.service';
import { InventoryStore } from '../../core/inventory.store';
import { CATEGORIES, skuValidator } from './inventory-ui';

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
  imports: [ReactiveFormsModule],
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
            <select id="if-category" formControlName="category" [class]="field">
              @for (c of categories; track c.code) { <option [value]="c.code">{{ c.label }}</option> }
            </select>
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
            <input id="if-unit" type="text" formControlName="unit" [class]="field" [attr.aria-invalid]="invalid('unit')" aria-describedby="if-unit-err" />
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
            <input id="if-location" type="text" formControlName="location" [class]="field" [attr.aria-invalid]="invalid('location')" aria-describedby="if-location-err" />
            <p id="if-location-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('location') }}</p>
          </div>
          <div>
            <label for="if-supplier" [class]="label">Proveedor</label>
            <input id="if-supplier" type="text" formControlName="supplier" [class]="field" [attr.aria-invalid]="invalid('supplier')" aria-describedby="if-supplier-err" />
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
  readonly categories = CATEGORIES;

  readonly form = new FormGroup(
    {
      sku: new FormControl('', { nonNullable: true, validators: [skuValidator] }),
      name: new FormControl('', { nonNullable: true, validators: [requiredText(3, 200)] }),
      description: new FormControl('', { nonNullable: true, validators: [optionalText(2000)] }),
      category: new FormControl<ItemCategory>('spare_part', { nonNullable: true, validators: [Validators.required] }),
      unit: new FormControl('unidad', { nonNullable: true, validators: [requiredText(1, 20), Validators.pattern(/^[A-Za-zÁÉÍÓÚáéíóúÑñ0-9 ./]*$/)] }),
      unitCost: new FormControl('', { nonNullable: true, validators: [optionalMoney(INVENTORY_LIMITS.maxCost)] }),
      initialStock: new FormControl<number | string>(0, { validators: [optionalInteger(0, INVENTORY_LIMITS.maxQuantity)] }),
      minStock: new FormControl<number | string>(0, { validators: [integerRange(0, INVENTORY_LIMITS.maxQuantity)] }),
      maxStock: new FormControl<number | string | null>(null, { validators: [optionalInteger(0, INVENTORY_LIMITS.maxQuantity)] }),
      location: new FormControl('', { nonNullable: true, validators: [optionalText(100)] }),
      supplier: new FormControl('', { nonNullable: true, validators: [optionalText(150)] }),
    },
    { validators: maxNotBelowMin('minStock', 'maxStock') },
  );

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closed.emit();
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
        unitCost: item.unit_cost, minStock: item.min_stock, maxStock: item.max_stock, location: item.location ?? '',
        supplier: item.supplier ?? '',
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
      category: v.category,
      unit: v.unit.trim(),
      unit_cost: parseDecimal(v.unitCost) ?? 0,
      min_stock: Number(v.minStock),
      max_stock: v.maxStock === null || String(v.maxStock).trim() === '' ? null : Number(v.maxStock),
      location: v.location.trim() || null,
      supplier: v.supplier.trim() || null,
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
