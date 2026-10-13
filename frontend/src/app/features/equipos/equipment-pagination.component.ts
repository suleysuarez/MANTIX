import { ChangeDetectionStrategy, Component, EventEmitter, Input, Output } from '@angular/core';

import { pageWindow } from '../../core/equipment-status';

/** Dumb component: «Mostrando X a Y de N equipos» y páginas numeradas. */
@Component({
  selector: 'app-equipment-pagination',
  standalone: true,
  template: `
    <nav aria-label="Paginación del catálogo"
      class="flex flex-col items-center justify-between gap-4 !border-t !border-slate-100 bg-white px-6 py-4 text-xs text-slate-500 sm:flex-row">
      <span>
        @if (total === 0) {
          Sin resultados
        } @else {
          Mostrando <strong class="text-slate-800">{{ from }}</strong> a <strong class="text-slate-800">{{ to }}</strong>
          de <strong class="text-slate-800">{{ total }}</strong> equipos
        }
      </span>
      @if (pages > 1) {
        <div class="flex items-center gap-1.5">
          <button type="button" (click)="pageChange.emit(page - 1)" [disabled]="page === 1 || loading" aria-label="Página anterior"
            class="bg-transparent flex h-8 w-8 items-center justify-center rounded-lg !border !border-slate-200 !text-slate-500 transition-colors hover:bg-slate-50 hover:text-slate-800 disabled:opacity-40">
            <span class="material-symbols-outlined text-[16px]">chevron_left</span>
          </button>
          @for (entry of window; track $index) {
            @if (entry === '…') {
              <span class="flex h-8 w-6 items-center justify-center text-slate-400" aria-hidden="true">…</span>
            } @else {
              <button type="button" (click)="pageChange.emit(+entry)" [disabled]="loading"
                [attr.aria-current]="entry === page ? 'page' : null" [attr.aria-label]="'Página ' + entry"
                class="flex h-8 w-8 items-center justify-center rounded-lg transition-colors"
                [class]="entry === page ? 'bg-sky-600 !font-bold !text-white shadow-sm' : 'bg-transparent !font-medium !text-slate-600 hover:bg-slate-100'">
                {{ entry }}
              </button>
            }
          }
          <button type="button" (click)="pageChange.emit(page + 1)" [disabled]="page === pages || loading" aria-label="Página siguiente"
            class="bg-transparent flex h-8 w-8 items-center justify-center rounded-lg !border !border-slate-200 !text-slate-500 transition-colors hover:bg-slate-50 hover:text-slate-800 disabled:opacity-40">
            <span class="material-symbols-outlined text-[16px]">chevron_right</span>
          </button>
        </div>
      }
    </nav>
  `,
  host: { class: 'block' },
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentPaginationComponent {
  /** Base 1. */
  @Input() page = 1;
  @Input() pageSize = 10;
  @Input() total = 0;
  @Input() loading = false;
  @Output() readonly pageChange = new EventEmitter<number>();

  get pages(): number {
    return Math.max(1, Math.ceil(this.total / this.pageSize));
  }

  get from(): number {
    return this.total === 0 ? 0 : (this.page - 1) * this.pageSize + 1;
  }

  get to(): number {
    return Math.min(this.page * this.pageSize, this.total);
  }

  get window(): (number | '…')[] {
    return pageWindow(this.page, this.pages);
  }
}
