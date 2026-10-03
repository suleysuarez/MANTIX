import { ChangeDetectionStrategy, Component, EventEmitter, Input, OnDestroy, OnInit, Output } from '@angular/core';
import { Subject, Subscription, debounceTime } from 'rxjs';

/** Dumb component: búsqueda con debounce, filtro de estado y paginación. */
@Component({
  selector: 'app-equipment-toolbar',
  standalone: true,
  template: `
    <div class="toolbar">
      <label>
        <span>Search</span>
        <input
          type="search"
          placeholder="Asset tag, serial, brand or model"
          [value]="search"
          (input)="onSearch($any($event.target).value)" />
      </label>
      <label>
        <span>Status</span>
        <select [value]="status" (change)="statusChange.emit($any($event.target).value)">
          <option value="">All</option>
          @for (option of statuses; track option) {
            <option [value]="option" [selected]="option === status">{{ option }}</option>
          }
        </select>
      </label>
    </div>
    <nav class="pager" aria-label="Catalog pages">
      <button type="button" [disabled]="page === 0 || loading" (click)="pageChange.emit(page - 1)">Previous</button>
      <span>Page {{ page + 1 }}</span>
      <button type="button" [disabled]="!hasNext || loading" (click)="pageChange.emit(page + 1)">Next</button>
    </nav>
  `,
  styles: [
    `.toolbar { display: flex; gap: 1rem; flex-wrap: wrap; margin: 1rem 0; }
     label { display: grid; gap: .25rem; font-size: .85rem; color: #475569; }
     input, select { padding: .5rem .7rem; border: 1px solid #cbd5e1; border-radius: 6px; min-width: 14rem; }
     .pager { display: flex; align-items: center; gap: 1rem; margin: .5rem 0 1rem; }
     .pager button { padding: .4rem .9rem; border: 1px solid #cbd5e1; border-radius: 6px; background: white; cursor: pointer; }
     .pager button:disabled { color: #94a3b8; cursor: default; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentToolbarComponent implements OnInit, OnDestroy {
  @Input() search = '';
  @Input() status = '';
  @Input() statuses: readonly string[] = [];
  @Input() page = 0;
  @Input() hasNext = false;
  @Input() loading = false;

  @Output() searchChange = new EventEmitter<string>();
  @Output() statusChange = new EventEmitter<string>();
  @Output() pageChange = new EventEmitter<number>();

  private readonly typed = new Subject<string>();
  private subscription?: Subscription;

  ngOnInit(): void {
    this.subscription = this.typed.pipe(debounceTime(300)).subscribe((value) => this.searchChange.emit(value));
  }

  ngOnDestroy(): void {
    this.subscription?.unsubscribe();
  }

  onSearch(value: string): void {
    this.typed.next(value);
  }
}
