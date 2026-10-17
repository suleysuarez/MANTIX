import { ChangeDetectionStrategy, Component, computed, input, output, signal } from '@angular/core';

import { RangeShortcut, SHORTCUTS, dateRangeError, dayString, shortcutOf, shortcutRange } from './date-range';

export interface DateRange {
  from: string;
  to: string;
}

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
let nextId = 0;

/**
 * Filtro por intervalo de fechas con atajos (Todo, Hoy, 7 días, 30 días, Este mes, Personalizado).
 * Valida el rango y avisa del error bajo los campos; el padre decide qué hacer con un rango inválido
 * (los listados no consultan al servidor mientras `error` no esté vacío).
 */
@Component({
  selector: 'app-date-range-filter',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { class: 'block' },
  template: `
    <fieldset [class]="inline() ? 'flex flex-wrap items-end gap-x-4 gap-y-2' : 'space-y-2'">
      <legend [class]="inline() ? 'sr-only' : 'text-[11px] font-bold uppercase tracking-wider text-on-surface-variant'">{{ label() }}</legend>
      @if (inline()) {
        <span class="self-center text-[11px] font-bold uppercase tracking-wider text-on-surface-variant" aria-hidden="true">{{ label() }}</span>
      }
      <div class="flex flex-wrap gap-1.5 self-center">
        @for (s of shortcuts; track s.id) {
          <button type="button" (click)="pick(s.id)" [attr.aria-pressed]="active() === s.id"
            [class]="focus + ' rounded-full border px-3 py-1 text-[12px] font-semibold ' + (active() === s.id ? 'border-brand-sidebar bg-brand-sidebar !text-white' : 'border-brand-grey bg-transparent !text-brand-accentDeep hover:bg-surface-container')">{{ shortcutLabel(s) }}</button>
        }
      </div>
      <div [class]="inline() ? 'grid w-full max-w-sm grid-cols-2 gap-2 sm:w-auto sm:min-w-[22rem]' : 'grid grid-cols-2 gap-2'">
        <div>
          <label [for]="id + '-from'" class="text-[11px] font-semibold text-on-surface-variant">Desde</label>
          <input [id]="id + '-from'" type="date" [value]="from()" [attr.max]="upcoming() ? null : today" [attr.aria-invalid]="!!error()" [attr.aria-describedby]="id + '-err'"
            (change)="edit('from', $any($event.target).value)"
            [class]="focus + ' h-10 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 text-[13px] text-on-surface'" />
        </div>
        <div>
          <label [for]="id + '-to'" class="text-[11px] font-semibold text-on-surface-variant">Hasta</label>
          <input [id]="id + '-to'" type="date" [value]="to()" [attr.aria-invalid]="!!error()" [attr.aria-describedby]="id + '-err'"
            (change)="edit('to', $any($event.target).value)"
            [class]="focus + ' h-10 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 text-[13px] text-on-surface'" />
        </div>
      </div>
      <p [id]="id + '-err'" [class]="(inline() ? 'w-full empty:hidden ' : 'min-h-4 ') + 'text-[12px] text-error'" role="alert">{{ error() }}</p>
    </fieldset>
  `,
})
export class DateRangeFilterComponent {
  readonly from = input('');
  readonly to = input('');
  readonly label = input('Periodo');
  /** `true`: atajos y fechas en una sola fila (barras de filtros anchas); `false`: apilado (paneles estrechos). */
  readonly inline = input(false);
  /** `true`: para fechas programadas; los atajos miran hacia adelante y la fecha inicial puede ser futura. */
  readonly upcoming = input(false);
  readonly rangeChange = output<DateRange>();

  readonly shortcuts = SHORTCUTS;
  readonly focus = FOCUS;
  readonly today = dayString(new Date());
  readonly id = `dr-${nextId++}`;
  /** «Personalizado» queda marcado aunque el rango siga vacío, mientras la persona lo esté escribiendo. */
  private readonly typing = signal(false);

  readonly error = computed(() => dateRangeError(this.from(), this.to(), new Date(), this.upcoming()));
  readonly active = computed<RangeShortcut>(() => {
    const matched = shortcutOf(this.from(), this.to(), new Date(), this.upcoming());
    return this.typing() && matched === 'all' ? 'custom' : matched;
  });

  shortcutLabel(shortcut: { id: RangeShortcut; label: string }): string {
    if (!this.upcoming()) {
      return shortcut.label;
    }
    return { '7d': 'Próx. 7 días', '30d': 'Próx. 30 días' }[shortcut.id as '7d' | '30d'] ?? shortcut.label;
  }

  pick(shortcut: RangeShortcut): void {
    const range = shortcutRange(shortcut, new Date(), this.upcoming());
    this.typing.set(shortcut === 'custom');
    if (range) {
      this.rangeChange.emit(range);
    }
  }

  edit(side: 'from' | 'to', value: string): void {
    this.typing.set(true);
    this.rangeChange.emit({ from: side === 'from' ? value : this.from(), to: side === 'to' ? value : this.to() });
  }
}
