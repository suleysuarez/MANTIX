import { ChangeDetectionStrategy, Component, ElementRef, HostListener, OnInit, computed, inject, input, output, signal, viewChild } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';
import { startWith } from 'rxjs';

import {
  fieldError, optionalInteger, optionalMoney, optionalText, parseDecimal,
} from '../../core/form-validation';
import { INVENTORY_LIMITS, InventoryItem, MovementKind } from '../../core/inventory.service';
import { InventoryStore } from '../../core/inventory.store';
import { KIND_LABELS, movementQuantity } from './inventory-ui';

const SERVER_FIELDS: Record<string, string> = {
  quantity: 'quantity', unit_cost: 'unitCost', notes: 'notes', record_id: 'recordId', request_id: 'requestId',
};
const LABEL = 'text-[12px] font-bold text-on-surface';
const FIELD =
  'mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep aria-[invalid=true]:border-error';

/** Registra una entrada, un consumo o un ajuste; el consumo nunca supera el stock disponible. */
@Component({
  selector: 'app-movement-modal',
  standalone: true,
  imports: [ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
      <div class="absolute inset-0 bg-brand-navy/50" (click)="closed.emit()" aria-hidden="true"></div>
      <form class="glass relative max-h-[92vh] w-full max-w-md overflow-y-auto rounded-t-2xl sm:rounded-2xl" role="dialog" aria-modal="true"
        aria-labelledby="mm-title" [formGroup]="form" (ngSubmit)="submit()" novalidate>
        <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
          <div class="min-w-0">
            <h2 id="mm-title" class="text-[16px] font-bold text-on-surface">Registrar movimiento</h2>
            <p class="truncate text-[12px] text-on-surface-variant">{{ item().sku }} · {{ item().name }} · stock {{ item().stock }}</p>
          </div>
          <button type="button" (click)="closed.emit()" aria-label="Cerrar"
            class="rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
            <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
          </button>
        </header>

        <div class="space-y-3 px-5 py-4">
          <fieldset>
            <legend [class]="label">Tipo</legend>
            <div class="mt-1 flex gap-1 rounded-full bg-surface-container p-0.5" role="group">
              @for (k of kinds(); track k) {
                <button type="button" (click)="setKind(k)" [attr.aria-pressed]="kind() === k"
                  class="flex-1 rounded-full px-3 py-1.5 text-[12px] font-semibold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep"
                  [class]="kind() === k ? 'bg-brand-sidebar !text-white' : 'bg-transparent !text-brand-accentDeep hover:bg-surface-container-high'">{{ labels[k] }}</button>
              }
            </div>
          </fieldset>

          <div>
            <label for="mm-quantity" [class]="label">{{ kind() === 'adjust' ? 'Ajuste (+ suma, − resta) *' : 'Cantidad *' }}</label>
            <input #firstField id="mm-quantity" type="number" inputmode="numeric" step="1" formControlName="quantity" [class]="field" [attr.aria-invalid]="invalid('quantity')" aria-describedby="mm-quantity-err" />
            <p id="mm-quantity-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('quantity') }}</p>
            @if (resulting() !== null) {
              <p class="text-[12px] text-on-surface-variant">Stock resultante: <strong class="text-on-surface">{{ resulting() }}</strong></p>
            }
          </div>

          @if (kind() === 'in') {
            <div>
              <label for="mm-cost" [class]="label">Costo unitario de esta entrada</label>
              <input id="mm-cost" type="text" inputmode="decimal" formControlName="unitCost" placeholder="Opcional" [class]="field" [attr.aria-invalid]="invalid('unitCost')" aria-describedby="mm-cost-err" />
              <p id="mm-cost-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('unitCost') }}</p>
            </div>
          }

          @if (kind() === 'out') {
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label for="mm-record" [class]="label">Registro de mant.</label>
                <input id="mm-record" type="number" inputmode="numeric" min="1" step="1" formControlName="recordId" placeholder="ID (opcional)" [class]="field" [attr.aria-invalid]="invalid('recordId')" aria-describedby="mm-record-err" />
                <p id="mm-record-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('recordId') }}</p>
              </div>
              <div>
                <label for="mm-request" [class]="label">Ticket</label>
                <input id="mm-request" type="number" inputmode="numeric" min="1" step="1" formControlName="requestId" placeholder="ID (opcional)" [class]="field" [attr.aria-invalid]="invalid('requestId')" aria-describedby="mm-request-err" />
                <p id="mm-request-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('requestId') }}</p>
              </div>
            </div>
          }

          <div>
            <label for="mm-notes" [class]="label">Motivo o nota</label>
            <input id="mm-notes" type="text" formControlName="notes" [class]="field" [attr.aria-invalid]="invalid('notes')" aria-describedby="mm-notes-err" />
            <p id="mm-notes-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ error('notes') }}</p>
          </div>
        </div>

        <footer class="flex justify-end gap-2 border-t border-brand-grey/70 px-5 py-3">
          <button type="button" (click)="closed.emit()" [disabled]="busy()"
            class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">Cancelar</button>
          <button type="submit" [disabled]="form.invalid || busy()"
            class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
            {{ busy() ? 'Guardando…' : 'Registrar' }}
          </button>
        </footer>
      </form>
    </div>
  `,
})
export class MovementModalComponent implements OnInit {
  private readonly store = inject(InventoryStore);

  readonly item = input.required<InventoryItem>();
  readonly initialKind = input<MovementKind>('out');
  /** Solo quien gestiona el inventario registra entradas y ajustes; el resto, consumo. */
  readonly canManage = input(false);
  readonly busy = input(false);
  readonly closed = output<void>();

  readonly firstField = viewChild<ElementRef<HTMLInputElement>>('firstField');
  readonly label = LABEL;
  readonly field = FIELD;
  readonly labels = KIND_LABELS;
  readonly kind = signal<MovementKind>('out');
  readonly kinds = computed<MovementKind[]>(() => (this.canManage() ? ['out', 'in', 'adjust'] : ['out']));

  readonly form = new FormGroup({
    quantity: new FormControl<number | string>('', {
      validators: [movementQuantity(() => this.kind(), () => this.item().stock)],
    }),
    unitCost: new FormControl('', { nonNullable: true, validators: [optionalMoney(INVENTORY_LIMITS.maxCost)] }),
    recordId: new FormControl<number | string>('', { validators: [optionalInteger(1, 2_147_483_647)] }),
    requestId: new FormControl<number | string>('', { validators: [optionalInteger(1, 2_147_483_647)] }),
    notes: new FormControl('', { nonNullable: true, validators: [optionalText(300)] }),
  });

  private readonly quantity = toSignal(this.form.controls.quantity.valueChanges.pipe(startWith('')), { initialValue: '' });
  /** Stock que quedaría tras el movimiento (solo si la cantidad es válida). */
  readonly resulting = computed<number | null>(() => {
    const raw = this.quantity();
    const value = Number(raw);
    if (String(raw ?? '').trim() === '' || !Number.isInteger(value) || this.form.controls.quantity.invalid) {
      return null;
    }
    return this.item().stock + (this.kind() === 'out' ? -value : value);
  });

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closed.emit();
  }

  error = (name: string): string => fieldError(this.form.get(name));
  invalid = (name: string): boolean => !!this.form.get(name)?.invalid && !!this.form.get(name)?.touched;

  ngOnInit(): void {
    this.kind.set(this.kinds().includes(this.initialKind()) ? this.initialKind() : 'out');
    setTimeout(() => this.firstField()?.nativeElement.focus());
  }

  setKind(kind: MovementKind): void {
    this.kind.set(kind);
    this.form.controls.quantity.updateValueAndValidity();
    this.form.controls.quantity.markAsTouched();
  }

  submit(): void {
    this.form.markAllAsTouched();
    if (this.form.invalid || this.busy()) {
      return;
    }
    const v = this.form.getRawValue();
    const kind = this.kind();
    this.store
      .move(this.item().id, {
        kind,
        quantity: Number(v.quantity),
        unit_cost: kind === 'in' ? parseDecimal(v.unitCost) : null,
        notes: v.notes.trim() || null,
        record_id: kind === 'out' && String(v.recordId).trim() ? Number(v.recordId) : null,
        request_id: kind === 'out' && String(v.requestId).trim() ? Number(v.requestId) : null,
      })
      .subscribe((result) => {
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
