import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  EventEmitter,
  Input,
  OnInit,
  Output,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Subject, catchError, debounceTime, distinctUntilChanged, of, switchMap } from 'rxjs';

import { initials } from '../../core/equipment-status';
import { CustodianCandidate, EquipmentService } from '../../core/equipment.service';

/**
 * Selector de custodio con búsqueda por nombre o correo. Es un widget autónomo: consulta
 * `/equipment/custodian-candidates` (permiso `equipment.manage`) con debounce y emite el
 * usuario elegido, o `null` al quitarlo.
 */
@Component({
  selector: 'app-custodian-picker',
  standalone: true,
  template: `
    @if (selected(); as user) {
      <div class="flex items-center justify-between gap-3 rounded-xl !border !border-emerald-200 bg-emerald-50/50 px-3 py-2">
        <div class="flex min-w-0 items-center gap-2.5">
          <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-slate-200 text-[11px] font-bold text-slate-700">{{ initialsOf(user.full_name) }}</span>
          <span class="min-w-0">
            <span class="block truncate text-xs font-semibold text-slate-800">{{ user.full_name }}</span>
            <span class="block truncate text-[11px] text-slate-500">{{ user.email }}</span>
          </span>
        </div>
        <button type="button" (click)="clear()" aria-label="Quitar custodio"
          class="bg-transparent flex h-7 w-7 shrink-0 items-center justify-center rounded-lg !text-slate-400 hover:bg-white hover:text-slate-700">
          <span class="material-symbols-outlined text-[18px]">close</span>
        </button>
      </div>
    } @else {
      <div class="relative">
        <span class="material-symbols-outlined pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[18px] text-slate-400">person_search</span>
        <input type="search" autocomplete="off" [placeholder]="placeholder" [attr.aria-label]="placeholder"
          (input)="onType($any($event.target).value)" (focus)="open.set(true)"
          class="w-full rounded-xl !border !border-slate-200 bg-white py-2.5 pl-10 pr-3 text-xs text-slate-800 focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-500/20" />
        @if (open() && query().length > 0) {
          <ul role="listbox" class="m-0 list-none p-0 absolute z-20 mt-1 max-h-52 w-full overflow-y-auto rounded-xl !border !border-slate-200 bg-white py-1 shadow-lg">
            @for (user of results(); track user.id) {
              <li role="option" aria-selected="false">
                <button type="button" (click)="pick(user)"
                  class="bg-transparent flex w-full flex-col px-3 py-2 text-left hover:bg-slate-50">
                  <span class="text-xs font-semibold text-slate-800">{{ user.full_name }}</span>
                  <span class="text-[11px] text-slate-500">{{ user.email }}</span>
                </button>
              </li>
            } @empty {
              <li class="px-3 py-2 text-xs text-slate-400">{{ searching() ? 'Buscando…' : 'Sin coincidencias' }}</li>
            }
          </ul>
        }
      </div>
    }
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class CustodianPickerComponent implements OnInit {
  @Input() placeholder = 'Buscar por nombre o correo…';
  @Output() readonly picked = new EventEmitter<CustodianCandidate | null>();

  private readonly api = inject(EquipmentService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly typed = new Subject<string>();

  readonly selected = signal<CustodianCandidate | null>(null);
  readonly results = signal<CustodianCandidate[]>([]);
  readonly query = signal('');
  readonly open = signal(false);
  readonly searching = signal(false);

  ngOnInit(): void {
    this.typed
      .pipe(
        debounceTime(250),
        distinctUntilChanged(),
        switchMap((term) => {
          if (!term) {
            return of([] as CustodianCandidate[]);
          }
          this.searching.set(true);
          return this.api.custodianCandidates(term).pipe(catchError(() => of([] as CustodianCandidate[])));
        }),
        takeUntilDestroyed(this.destroyRef),
      )
      .subscribe((users) => {
        this.searching.set(false);
        this.results.set(users);
      });
  }

  onType(value: string): void {
    const term = value.trim();
    this.query.set(term);
    this.open.set(true);
    this.typed.next(term);
  }

  pick(user: CustodianCandidate): void {
    this.selected.set(user);
    this.open.set(false);
    this.picked.emit(user);
  }

  clear(): void {
    this.selected.set(null);
    this.query.set('');
    this.results.set([]);
    this.picked.emit(null);
  }

  initialsOf(name: string): string {
    return initials(name);
  }
}
