import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, inject, input, output, signal } from '@angular/core';

import { InventoryItem, Movement } from '../../core/inventory.service';
import { InventoryStore } from '../../core/inventory.store';
import { KIND_LABELS, STATUS_META, categoryIcon, categoryLabel, minMarker, money } from './inventory-ui';

type Confirm = 'toggle' | 'delete' | null;

/** Detalle de un ítem: datos, nivel de stock, últimos movimientos y acciones (con confirmación). */
@Component({
  selector: 'app-item-detail-panel',
  standalone: true,
  imports: [DatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <aside class="glass flex max-h-[calc(100vh-2rem)] flex-col overflow-hidden rounded-2xl" aria-label="Detalle del ítem">
      <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
        <h2 class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Ítem de inventario</h2>
        <button type="button" (click)="closed.emit()" aria-label="Cerrar detalle"
          class="rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
          <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
        </button>
      </header>

      <div class="min-h-0 flex-1 space-y-4 overflow-y-auto px-5 py-4">
        @if (loading()) {
          <div class="space-y-3" role="status" aria-label="Cargando ítem">
            <div class="h-5 w-3/4 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
            <div class="h-24 animate-pulse rounded bg-surface-container motion-reduce:animate-none"></div>
          </div>
        } @else if (error()) {
          <p role="alert" class="rounded-lg bg-error-container px-3 py-2 text-[13px] text-on-error-container">{{ error() }}</p>
        } @else if (item()) {
          @let i = item()!;
          <div class="flex items-start gap-3">
            <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-brand-accentLight/60 text-brand-accentDeep">
              <span class="material-symbols-outlined text-[24px]" aria-hidden="true">{{ icon(i.category) }}</span>
            </span>
            <div class="min-w-0">
              <h3 class="text-[17px] font-bold leading-6 text-on-surface">{{ i.name }}</h3>
              <p class="font-mono text-[12px] text-on-surface-variant">{{ i.sku }} · {{ categoryName(i.category) }}</p>
              <p class="mt-1.5 inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-bold" [class]="i.is_active ? meta[i.status].chip : 'bg-surface-container text-on-surface-variant'">
                {{ i.is_active ? meta[i.status].label : 'Inactivo' }}
              </p>
            </div>
          </div>

          <div>
            <div class="flex items-baseline justify-between text-[12px]">
              <span class="text-on-surface-variant">Stock</span>
              <span><strong class="text-[20px] text-on-surface">{{ i.stock }}</strong> {{ i.unit }}</span>
            </div>
            <div class="relative mt-1.5 h-3 overflow-hidden rounded-full bg-surface-container" role="img"
              [attr.aria-label]="'Stock ' + i.stock + ', mínimo ' + i.min_stock + (i.max_stock !== null ? ', máximo ' + i.max_stock : '')">
              <div class="h-full rounded-full" [class]="meta[i.status].bar" [style.width.%]="i.level_pct"></div>
              @if (marker(i); as m) { <span class="absolute inset-y-0 w-0.5 bg-on-surface" [style.left.%]="m"></span> }
            </div>
            <p class="mt-1 text-[11px] text-on-surface-variant">Mínimo {{ i.min_stock }}{{ i.max_stock !== null ? ' · máximo ' + i.max_stock : '' }}</p>
          </div>

          <dl class="grid grid-cols-2 gap-x-4 gap-y-3 text-[12px]">
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Costo unitario</dt><dd class="mt-0.5 text-on-surface">{{ fmt(i.unit_cost) }}</dd></div>
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Valor en stock</dt><dd class="mt-0.5 text-on-surface">{{ fmt(i.stock_value) }}</dd></div>
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Ubicación</dt><dd class="mt-0.5 text-on-surface">{{ i.location ?? '—' }}</dd></div>
            <div><dt class="font-bold uppercase tracking-wider text-on-surface-variant">Proveedor</dt><dd class="mt-0.5 text-on-surface">{{ i.supplier ?? '—' }}</dd></div>
          </dl>
          @if (i.description) { <p class="whitespace-pre-line text-[13px] leading-5 text-on-surface">{{ i.description }}</p> }

          @if (confirm() === null) {
            <div class="grid grid-cols-2 gap-2 border-t border-brand-grey/70 pt-4" aria-label="Acciones del ítem">
              @if (i.is_active) {
                <button type="button" (click)="move.emit('out')" [disabled]="busy() || i.stock === 0" [class]="primary">Consumir</button>
              }
              @if (canManage()) {
                @if (i.is_active) {
                  <button type="button" (click)="move.emit('in')" [disabled]="busy()" [class]="secondary">Entrada</button>
                  <button type="button" (click)="move.emit('adjust')" [disabled]="busy()" [class]="secondary">Ajuste</button>
                }
                <button type="button" (click)="edit.emit()" [disabled]="busy()" [class]="secondary">Editar</button>
                <button type="button" (click)="confirm.set('toggle')" [disabled]="busy()" [class]="secondary">{{ i.is_active ? 'Desactivar…' : 'Reactivar…' }}</button>
                @if (movementsTotal() === 0) {
                  <button type="button" (click)="confirm.set('delete')" [disabled]="busy()"
                    class="rounded-xl border border-error bg-transparent px-4 py-2 text-[13px] font-bold !text-error hover:bg-error-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-error disabled:opacity-50">Eliminar…</button>
                }
              }
            </div>
          } @else if (confirm() === 'toggle') {
            <div class="space-y-2 rounded-xl border border-brand-grey bg-surface-container-low p-3">
              <p class="text-[13px] font-semibold text-on-surface">{{ i.is_active ? '¿Desactivar este ítem?' : '¿Reactivar este ítem?' }}</p>
              <p class="text-[12px] text-on-surface-variant">{{ i.is_active ? 'No podrá moverse ni aparecerá en las alertas. Su historial se conserva.' : 'Volverá a poder usarse y contarse en las métricas.' }}</p>
              <div class="flex justify-end gap-2">
                <button type="button" (click)="confirm.set(null)" [disabled]="busy()" [class]="ghost">Volver</button>
                <button type="button" (click)="toggle(i)" [disabled]="busy()" class="glass-btn rounded-lg px-4 py-2 text-[13px] font-bold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">Confirmar</button>
              </div>
            </div>
          } @else {
            <div class="space-y-2 rounded-xl border border-error/40 bg-error-container/40 p-3">
              <p class="text-[13px] font-semibold text-on-error-container">¿Eliminar este ítem?</p>
              <p class="text-[12px] text-on-error-container">Esta acción no se puede deshacer. Solo es posible porque nunca tuvo movimientos.</p>
              <div class="flex justify-end gap-2">
                <button type="button" (click)="confirm.set(null)" [disabled]="busy()" [class]="ghost">Volver</button>
                <button type="button" (click)="remove(i)" [disabled]="busy()"
                  class="rounded-lg bg-error px-4 py-2 text-[13px] font-bold !text-on-error focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-error disabled:opacity-50">Confirmar eliminación</button>
              </div>
            </div>
          }

          <section>
            <h3 class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">Últimos movimientos</h3>
            <ul class="mt-2 space-y-1.5">
              @for (m of movements(); track m.id) {
                <li class="flex items-baseline justify-between gap-2 text-[12px]">
                  <span class="min-w-0">
                    <span class="font-semibold text-on-surface">{{ kinds[m.kind] }}</span>
                    <span class="text-on-surface-variant"> · {{ m.created_at | date: 'dd/MM/yy HH:mm' }}@if (m.created_by) { · {{ m.created_by }} }</span>
                    @if (m.notes) { <span class="block truncate text-on-surface-variant">{{ m.notes }}</span> }
                  </span>
                  <span class="shrink-0 font-bold" [class]="m.quantity < 0 ? 'text-on-secondary-fixed-variant' : 'text-brand-accentDeep'">{{ m.quantity > 0 ? '+' : '' }}{{ m.quantity }} → {{ m.stock_after }}</span>
                </li>
              } @empty {
                <li class="text-[12px] text-on-surface-variant">Aún no hay movimientos.</li>
              }
            </ul>
          </section>
        }
      </div>
    </aside>
  `,
})
export class ItemDetailPanelComponent {
  private readonly store = inject(InventoryStore);

  readonly item = input<InventoryItem | null>(null);
  readonly movements = input<Movement[]>([]);
  readonly movementsTotal = input(0);
  readonly loading = input(false);
  readonly error = input('');
  readonly busy = input(false);
  readonly canManage = input(false);
  readonly closed = output<void>();
  readonly edit = output<void>();
  readonly move = output<'in' | 'out' | 'adjust'>();

  readonly confirm = signal<Confirm>(null);
  readonly meta = STATUS_META;
  readonly kinds = KIND_LABELS;
  readonly icon = categoryIcon;
  readonly categoryName = categoryLabel;
  readonly marker = minMarker;
  readonly fmt = money;
  readonly primary =
    'glass-btn col-span-2 flex items-center justify-center rounded-xl px-4 py-2.5 text-[13px] font-bold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
  readonly secondary =
    'rounded-xl border border-brand-accentDeep bg-transparent px-4 py-2 text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep disabled:opacity-50';
  readonly ghost =
    'rounded-lg bg-transparent px-3 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep';

  toggle(item: InventoryItem): void {
    this.store
      .update(item.id, { is_active: !item.is_active }, item.is_active ? 'Ítem desactivado.' : 'Ítem reactivado.')
      .subscribe((result) => result.ok && this.confirm.set(null));
  }

  remove(item: InventoryItem): void {
    this.store.remove(item.id).subscribe((result) => result.ok && this.confirm.set(null));
  }
}
