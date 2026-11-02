import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';

import { pageWindow } from '../core/equipment-status';

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';

/**
 * Paginación única de toda la aplicación: resumen del rango, «Anterior» solo cuando hay una
 * página anterior, «Siguiente» solo cuando hay una siguiente, y páginas numeradas cuando se
 * conoce el total. Sin total (listas por cursor) muestra «Página N» y los dos extremos.
 */
@Component({
  selector: 'app-pagination',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { class: 'block' },
  template: `
    @if (visible()) {
      <nav [attr.aria-label]="'Paginación de ' + noun()"
        class="flex flex-col items-center justify-between gap-3 px-1 py-2 text-[12px] text-on-surface-variant sm:flex-row">
        <span role="status">
          @if (total() === null) {
            Página <strong class="text-on-surface">{{ page() }}</strong>
          } @else if (pages() === 1) {
            <strong class="text-on-surface">{{ total() }}</strong> {{ noun() }}{{ filtered() ? ' con los filtros aplicados' : '' }}
          } @else {
            {{ capitalized() }} <strong class="text-on-surface">{{ from() }}</strong>–<strong class="text-on-surface">{{ to() }}</strong>
            de <strong class="text-on-surface">{{ total() }}</strong>{{ filtered() ? ' con los filtros aplicados' : '' }}
          }
        </span>
        <div class="flex items-center gap-1.5">
          @if (page() > 1) {
            <button type="button" (click)="go(page() - 1)" [disabled]="loading()" aria-label="Página anterior"
              [class]="focus + ' flex h-8 items-center gap-1 rounded-lg border border-brand-grey bg-transparent px-2.5 text-[12px] font-semibold !text-brand-accentDeep hover:bg-surface-container-high disabled:opacity-40'">
              <span class="material-symbols-outlined text-[18px]" aria-hidden="true">chevron_left</span> Anterior
            </button>
          }
          @if (total() !== null && pages() > 1) {
            @for (entry of window(); track $index) {
              @if (entry === '…') {
                <span class="flex h-8 w-6 items-center justify-center text-on-surface-variant" aria-hidden="true">…</span>
              } @else {
                <button type="button" (click)="go(+entry)" [disabled]="loading()" [attr.aria-current]="entry === page() ? 'page' : null"
                  [attr.aria-label]="'Página ' + entry"
                  [class]="focus + ' flex h-8 min-w-8 items-center justify-center rounded-lg px-2 text-[12px] font-semibold ' + (entry === page() ? 'bg-brand-sidebar !text-white shadow-sm' : 'bg-transparent !text-brand-accentDeep hover:bg-surface-container-high')">{{ entry }}</button>
              }
            }
          }
          @if (hasNextPage()) {
            <button type="button" (click)="go(page() + 1)" [disabled]="loading()" aria-label="Página siguiente"
              [class]="focus + ' flex h-8 items-center gap-1 rounded-lg border border-brand-grey bg-transparent px-2.5 text-[12px] font-semibold !text-brand-accentDeep hover:bg-surface-container-high disabled:opacity-40'">
              Siguiente <span class="material-symbols-outlined text-[18px]" aria-hidden="true">chevron_right</span>
            </button>
          }
        </div>
      </nav>
    }
  `,
})
export class PaginationComponent {
  /** Base 1. */
  readonly page = input.required<number>();
  readonly pageSize = input(10);
  /** Total de registros; `null` cuando la API no lo da (entonces se usa `hasNext`). */
  readonly total = input<number | null>(null);
  readonly hasNext = input(false);
  readonly loading = input(false);
  /** Lo que se cuenta, en plural: «tickets», «técnicos». */
  readonly noun = input('registros');
  /** Hay filtros activos: el total es el de la búsqueda. */
  readonly filtered = input(false);
  readonly pageChange = output<number>();

  readonly focus = FOCUS;
  readonly pages = computed(() => {
    const total = this.total();
    return total === null ? 1 : Math.max(1, Math.ceil(total / this.pageSize()));
  });
  readonly from = computed(() => ((this.total() ?? 0) === 0 ? 0 : (this.page() - 1) * this.pageSize() + 1));
  readonly to = computed(() => Math.min(this.page() * this.pageSize(), this.total() ?? 0));
  readonly window = computed(() => pageWindow(this.page(), this.pages()));
  readonly capitalized = computed(() => this.noun().charAt(0).toUpperCase() + this.noun().slice(1));
  /** «Siguiente» solo existe si hay una página después de la actual. */
  readonly hasNextPage = computed(() => (this.total() === null ? this.hasNext() : this.page() < this.pages()));
  /** Con una sola página y total conocido solo queda el resumen; sin registros no se muestra nada. */
  readonly visible = computed(() => (this.total() === null ? this.page() > 1 || this.hasNext() : this.total()! > 0));

  go(target: number): void {
    if (target >= 1 && target !== this.page() && (this.total() === null || target <= this.pages())) {
      this.pageChange.emit(target);
    }
  }
}
