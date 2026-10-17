import { ChangeDetectionStrategy, Component, DestroyRef, ElementRef, HostListener, OnChanges, SimpleChanges, inject, input, output, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule } from '@angular/forms';
import { debounceTime } from 'rxjs';

import { ExportFormat, ReportDefinition } from '../../core/reports.service';
import { EMPTY_VALUES, FilterValues, MAX_RANGE_DAYS, canCompare, dateRangeValidator, rangeError } from './report-filters';

export interface BuilderChange {
  values: FilterValues;
  compare: boolean;
  valid: boolean;
}

export const FORMATS: { id: ExportFormat; label: string }[] = [
  { id: 'xlsx', label: 'Excel' },
  { id: 'pdf', label: 'PDF' },
  { id: 'csv', label: 'CSV' },
];
const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `h-10 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 text-[13px] text-on-surface ${FOCUS} aria-[invalid=true]:border-error`;
const FILTER_ICONS: Record<string, string> = {
  statuses: 'flag', priorities: 'priority_high', categories: 'category', kinds: 'swap_vert', equipment_type_ids: 'devices', dates: 'date_range', days: 'schedule',
};

type ListKey = 'statuses' | 'priorities' | 'categories' | 'kinds' | 'equipment_type_ids';

/**
 * Panel «Filtros» del reporte elegido: cada criterio en su recuadro con un desplegable («Todos» o lo elegido),
 * rango de fechas validado, formato de exportación y «Limpiar filtros».
 */
@Component({
  selector: 'app-report-builder',
  standalone: true,
  imports: [ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="glass flex h-full flex-col gap-3 rounded-2xl p-4" aria-label="Constructor de filtros" [formGroup]="form">
      <header class="flex items-start gap-3">
        <span class="material-symbols-outlined mt-0.5 text-[24px] text-brand-accentDeep" aria-hidden="true">filter_alt</span>
        <div>
          <h2 class="text-[16px] font-extrabold leading-tight text-brand-sidebar">Filtros</h2>
          <p class="text-[12px] text-on-surface-variant">Selecciona los criterios para tu reporte.</p>
        </div>
      </header>

      @for (filter of definition().filters; track filter.key) {
        <div class="rounded-xl border border-brand-grey/70 bg-surface-container-lowest p-2.5">
          @switch (filter.kind) {
            @case ('multiselect') {
              <div class="relative">
                <p class="flex items-center gap-2 text-[12px] font-bold text-on-surface">
                  <span class="material-symbols-outlined text-[18px] text-brand-accentDeep" aria-hidden="true">{{ icon(filter.key) }}</span>{{ filter.label }}
                </p>
                <button type="button" (click)="toggleMenu(filter.key); $event.stopPropagation()" [attr.aria-expanded]="openMenu() === filter.key" aria-haspopup="listbox"
                  [attr.aria-label]="filter.label + ': ' + summary(listKey(filter.key), filter.options)"
                  [class]="focus + ' mt-1.5 flex h-10 w-full items-center justify-between gap-2 rounded-lg border border-outline bg-surface-container-lowest px-3 text-left text-[13px] text-on-surface'">
                  <span class="min-w-0 truncate">{{ summary(listKey(filter.key), filter.options) }}</span>
                  <span class="material-symbols-outlined text-[20px] text-on-surface-variant" aria-hidden="true">expand_more</span>
                </button>
                @if (openMenu() === filter.key) {
                  <ul role="listbox" tabindex="-1" aria-multiselectable="true" [attr.aria-label]="filter.label" (click)="$event.stopPropagation()" (keydown.escape)="openMenu.set(null)"
                    class="absolute left-0 right-0 z-20 mt-1 max-h-56 overflow-y-auto rounded-xl border border-brand-grey bg-surface-container-lowest p-1 shadow-lg">
                    @for (option of filter.options; track option.value) {
                      <li role="option" [attr.aria-selected]="isOn(listKey(filter.key), option.value)">
                        <label class="flex cursor-pointer items-center gap-2 rounded-lg px-2 py-1.5 text-[13px] text-on-surface hover:bg-surface-container-high">
                          <input type="checkbox" class="h-4 w-4 accent-brand-accentDeep" [checked]="isOn(listKey(filter.key), option.value)" (change)="toggle(listKey(filter.key), option.value)" />
                          {{ option.label }}
                        </label>
                      </li>
                    } @empty {
                      <li class="px-2 py-1.5 text-[12px] text-on-surface-variant">Sin opciones disponibles.</li>
                    }
                    @if (form.controls[listKey(filter.key)].value.length > 0) {
                      <li class="border-t border-brand-grey/60 pt-1">
                        <button type="button" (click)="clearList(listKey(filter.key))" [class]="focus + ' w-full rounded-lg bg-transparent px-2 py-1.5 text-left text-[12px] font-semibold !text-brand-accentDeep hover:bg-surface-container-high'">Mostrar todos</button>
                      </li>
                    }
                  </ul>
                }
              </div>
            }
            @case ('dates') {
              <fieldset>
                <legend class="flex items-center gap-2 text-[12px] font-bold text-on-surface">
                  <span class="material-symbols-outlined text-[18px] text-brand-accentDeep" aria-hidden="true">{{ icon(filter.key) }}</span>{{ filter.label }}
                </legend>
                <div class="mt-1.5 grid grid-cols-2 gap-2">
                  <div>
                    <label for="rb-from" class="sr-only">Desde</label>
                    <input id="rb-from" type="date" formControlName="dateFrom" [class]="field" [attr.aria-invalid]="!!rangeMessage()" aria-describedby="rb-range-err" />
                  </div>
                  <div>
                    <label for="rb-to" class="sr-only">Hasta</label>
                    <input id="rb-to" type="date" formControlName="dateTo" [class]="field" [attr.aria-invalid]="!!rangeMessage()" aria-describedby="rb-range-err" />
                  </div>
                </div>
                <p id="rb-range-err" class="mt-1 min-h-[1rem] text-[12px] text-error empty:min-h-0" role="alert">{{ rangeMessage() }}</p>
                <p class="text-[11px] text-on-surface-variant">Máximo {{ maxDays }} días. Vacías: sin límite.</p>
              </fieldset>
            }
            @case ('days') {
              <div>
                <label for="rb-days" class="flex items-center gap-2 text-[12px] font-bold text-on-surface">
                  <span class="material-symbols-outlined text-[18px] text-brand-accentDeep" aria-hidden="true">{{ icon(filter.key) }}</span>{{ filter.label }}
                </label>
                <select id="rb-days" formControlName="days" [class]="field + ' mt-1.5'">
                  @for (option of filter.options; track option.value) { <option [value]="option.value">{{ option.label }}</option> }
                </select>
              </div>
            }
          }
        </div>
      }

      @if (definition().supports_compare) {
        <label class="flex items-start gap-2 rounded-xl border border-brand-grey/70 bg-surface-container-lowest p-2.5 text-[13px] text-on-surface">
          <input type="checkbox" formControlName="compare" class="mt-0.5 h-4 w-4 accent-brand-accentDeep" />
          <span>Comparar con el periodo anterior
            <span class="block text-[11px] text-on-surface-variant">{{ compareEnabled() ? 'Mismo número de días justo antes del rango.' : 'Elige fecha inicial y final para comparar.' }}</span>
          </span>
        </label>
      }

      <div class="rounded-xl border border-brand-grey/70 bg-surface-container-lowest p-2.5">
        <label for="rb-format" class="flex items-center gap-2 text-[12px] font-bold text-on-surface">
          <span class="material-symbols-outlined text-[18px] text-brand-accentDeep" aria-hidden="true">description</span>Formato de exportación
        </label>
        <select id="rb-format" [class]="field + ' mt-1.5'" (change)="setFormat($any($event.target).value)">
          @for (f of formats; track f.id) { <option [value]="f.id" [selected]="f.id === format()">{{ f.label }}</option> }
        </select>
      </div>

      <button type="button" (click)="reset()"
        [class]="focus + ' mt-auto flex h-10 items-center justify-center gap-2 rounded-xl border border-brand-accentDeep bg-transparent text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container'">
        <span class="material-symbols-outlined text-[18px]" aria-hidden="true">refresh</span> Limpiar filtros
      </button>
    </section>
  `,
})
export class ReportBuilderComponent implements OnChanges {
  private readonly destroyRef = inject(DestroyRef);
  private readonly host = inject<ElementRef<HTMLElement>>(ElementRef);

  readonly definition = input.required<ReportDefinition>();
  readonly changed = output<BuilderChange>();
  /** El formato elegido; quien exporta (el botón de la vista previa) lo lee de aquí. */
  readonly formatChange = output<ExportFormat>();

  readonly formats = FORMATS;
  readonly focus = FOCUS;
  readonly field = FIELD;
  readonly maxDays = MAX_RANGE_DAYS;
  readonly format = signal<ExportFormat>('xlsx');
  /** Desplegable de opciones múltiples abierto (uno a la vez). */
  readonly openMenu = signal<string | null>(null);

  readonly form = new FormGroup(
    {
      statuses: new FormControl<string[]>([], { nonNullable: true }),
      priorities: new FormControl<string[]>([], { nonNullable: true }),
      categories: new FormControl<string[]>([], { nonNullable: true }),
      kinds: new FormControl<string[]>([], { nonNullable: true }),
      equipment_type_ids: new FormControl<string[]>([], { nonNullable: true }),
      dateFrom: new FormControl('', { nonNullable: true }),
      dateTo: new FormControl('', { nonNullable: true }),
      days: new FormControl('30', { nonNullable: true }),
      compare: new FormControl(false, { nonNullable: true }),
    },
    { validators: dateRangeValidator },
  );

  constructor() {
    this.form.valueChanges.pipe(debounceTime(350), takeUntilDestroyed(this.destroyRef)).subscribe(() => this.emit());
  }

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['definition'] && !changes['definition'].firstChange) {
      this.reset();
    } else if (changes['definition']) {
      this.emit();
    }
  }

  @HostListener('document:click', ['$event'])
  closeOnOutsideClick(event: Event): void {
    if (this.openMenu() !== null && !this.host.nativeElement.contains(event.target as Node)) {
      this.openMenu.set(null);
    }
  }

  @HostListener('document:keydown.escape')
  closeOnEscape(): void {
    this.openMenu.set(null);
  }

  listKey = (key: string): ListKey => key as ListKey;
  icon = (key: string): string => FILTER_ICONS[key] ?? 'tune';
  isOn = (key: ListKey, value: string): boolean => this.form.controls[key].value.includes(value);
  rangeMessage = (): string => rangeError(this.form.errors);
  compareEnabled = (): boolean => canCompare(this.definition(), this.values());

  /** Lo que muestra el desplegable: «Todos», la opción elegida o cuántas hay elegidas. */
  summary(key: ListKey, options: { value: string; label: string }[]): string {
    const chosen = this.form.controls[key].value;
    if (chosen.length === 0) {
      return 'Todos';
    }
    return chosen.length === 1 ? (options.find((o) => o.value === chosen[0])?.label ?? chosen[0]) : `${chosen.length} seleccionados`;
  }

  toggleMenu(key: string): void {
    this.openMenu.set(this.openMenu() === key ? null : key);
  }

  toggle(key: ListKey, value: string): void {
    const control = this.form.controls[key];
    const next = control.value.includes(value) ? control.value.filter((v) => v !== value) : [...control.value, value];
    control.setValue(next);
  }

  clearList(key: ListKey): void {
    this.form.controls[key].setValue([]);
    this.openMenu.set(null);
  }

  setFormat(value: string): void {
    this.format.set(value as ExportFormat);
    this.formatChange.emit(this.format());
  }

  reset(): void {
    this.form.reset({ ...EMPTY_VALUES, compare: false }, { emitEvent: false });
    this.openMenu.set(null);
    this.emit();
  }

  private values(): FilterValues {
    const v = this.form.getRawValue();
    return {
      statuses: v.statuses, priorities: v.priorities, categories: v.categories, kinds: v.kinds,
      equipment_type_ids: v.equipment_type_ids, dateFrom: v.dateFrom, dateTo: v.dateTo, days: v.days,
    };
  }

  private emit(): void {
    const compare = this.form.controls.compare.value && this.compareEnabled();
    this.changed.emit({ values: this.values(), compare, valid: this.form.valid });
  }
}
