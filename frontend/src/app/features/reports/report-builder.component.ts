import { ChangeDetectionStrategy, Component, DestroyRef, OnChanges, SimpleChanges, inject, input, output } from '@angular/core';
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

const FORMATS: { id: ExportFormat; label: string }[] = [
  { id: 'xlsx', label: 'Excel' },
  { id: 'pdf', label: 'PDF' },
  { id: 'csv', label: 'CSV' },
];
const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';
const FIELD = `mt-1 w-full rounded-lg border border-outline bg-surface-container-lowest px-3 py-2 text-[13px] text-on-surface ${FOCUS} aria-[invalid=true]:border-error`;

type ListKey = 'statuses' | 'priorities' | 'categories' | 'kinds' | 'equipment_type_ids';

/** Constructor de filtros del reporte elegido: chips de opciones múltiples, rango de fechas validado y formato. */
@Component({
  selector: 'app-report-builder',
  standalone: true,
  imports: [ReactiveFormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="glass space-y-4 rounded-2xl p-4" aria-label="Constructor de filtros" [formGroup]="form">
      <div>
        <h2 class="text-[13px] font-bold uppercase tracking-wider text-brand-accentDeep">Filtros</h2>
        <p class="mt-0.5 text-[12px] text-on-surface-variant">{{ definition().title }}</p>
      </div>

      @for (filter of definition().filters; track filter.key) {
        @switch (filter.kind) {
          @case ('multiselect') {
            <fieldset>
              <legend class="text-[12px] font-bold text-on-surface">{{ filter.label }}</legend>
              <div class="mt-1.5 flex flex-wrap gap-1.5">
                @for (option of filter.options; track option.value) {
                  <button type="button" (click)="toggle(listKey(filter.key), option.value)" [attr.aria-pressed]="isOn(listKey(filter.key), option.value)"
                    [class]="focus + ' rounded-full border px-2.5 py-1 text-[12px] font-semibold transition-colors ' + (isOn(listKey(filter.key), option.value) ? 'border-brand-sidebar bg-brand-sidebar !text-white' : 'border-brand-grey bg-transparent !text-brand-accentDeep hover:bg-surface-container')">
                    {{ option.label }}
                  </button>
                } @empty {
                  <span class="text-[12px] text-on-surface-variant">Sin opciones disponibles.</span>
                }
              </div>
            </fieldset>
          }
          @case ('dates') {
            <fieldset>
              <legend class="text-[12px] font-bold text-on-surface">{{ filter.label }}</legend>
              <div class="grid grid-cols-2 gap-2">
                <div>
                  <label for="rb-from" class="sr-only">Desde</label>
                  <input id="rb-from" type="date" formControlName="dateFrom" [class]="field" [attr.aria-invalid]="!!rangeMessage()" aria-describedby="rb-range-err" />
                </div>
                <div>
                  <label for="rb-to" class="sr-only">Hasta</label>
                  <input id="rb-to" type="date" formControlName="dateTo" [class]="field" [attr.aria-invalid]="!!rangeMessage()" aria-describedby="rb-range-err" />
                </div>
              </div>
              <p id="rb-range-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ rangeMessage() }}</p>
              <p class="text-[11px] text-on-surface-variant">Máximo {{ maxDays }} días. Déjalas vacías para no limitar.</p>
            </fieldset>
          }
          @case ('days') {
            <div>
              <label for="rb-days" class="text-[12px] font-bold text-on-surface">{{ filter.label }}</label>
              <select id="rb-days" formControlName="days" [class]="field">
                @for (option of filter.options; track option.value) { <option [value]="option.value">{{ option.label }}</option> }
              </select>
            </div>
          }
        }
      }

      @if (definition().supports_compare) {
        <label class="flex items-start gap-2 text-[13px] text-on-surface">
          <input type="checkbox" formControlName="compare" class="mt-0.5 h-4 w-4 accent-brand-accentDeep" />
          <span>Comparar con el periodo anterior
            <span class="block text-[11px] text-on-surface-variant">{{ compareEnabled() ? 'Mismo número de días justo antes del rango.' : 'Elige fecha inicial y final para comparar.' }}</span>
          </span>
        </label>
      }

      <fieldset>
        <legend class="text-[12px] font-bold text-on-surface">Formato de exportación</legend>
        <div class="mt-1.5 flex gap-1 rounded-full bg-surface-container p-0.5" role="group">
          @for (f of formats; track f.id) {
            <button type="button" (click)="format = f.id" [attr.aria-pressed]="format === f.id"
              [class]="focus + ' flex-1 rounded-full px-3 py-1 text-[12px] font-semibold transition-colors ' + (format === f.id ? 'bg-brand-sidebar !text-white' : 'bg-transparent !text-brand-accentDeep hover:bg-surface-container-high')">{{ f.label }}</button>
          }
        </div>
      </fieldset>

      <div class="flex flex-wrap gap-2">
        <button type="button" (click)="exportRequested.emit(format)" [disabled]="!canExport() || exporting() !== null"
          class="glass-btn flex flex-1 items-center justify-center gap-1.5 rounded-xl px-4 py-2.5 text-[13px] font-bold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">
          <span class="material-symbols-outlined text-[18px]" aria-hidden="true">file_download</span>
          {{ exporting() ? 'Generando…' : 'Exportar ' + formatLabel() }}
        </button>
        <button type="button" (click)="reset()"
          [class]="focus + ' rounded-xl bg-transparent px-3 py-2 text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container'">Limpiar</button>
      </div>
      @if (!canExport() && exporting() === null) {
        <p class="text-[11px] text-on-surface-variant">{{ exportHint() }}</p>
      }
    </section>
  `,
})
export class ReportBuilderComponent implements OnChanges {
  private readonly destroyRef = inject(DestroyRef);

  readonly definition = input.required<ReportDefinition>();
  /** La vista previa tiene filas exportables y el formulario es válido. */
  readonly canExport = input(false);
  readonly exportHint = input('Ajusta los filtros para exportar.');
  readonly exporting = input<ExportFormat | null>(null);
  readonly changed = output<BuilderChange>();
  readonly exportRequested = output<ExportFormat>();

  readonly formats = FORMATS;
  readonly focus = FOCUS;
  readonly field = FIELD;
  readonly maxDays = MAX_RANGE_DAYS;
  format: ExportFormat = 'xlsx';

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

  listKey = (key: string): ListKey => key as ListKey;
  isOn = (key: ListKey, value: string): boolean => this.form.controls[key].value.includes(value);
  rangeMessage = (): string => rangeError(this.form.errors);
  formatLabel = (): string => FORMATS.find((f) => f.id === this.format)?.label ?? '';
  compareEnabled = (): boolean => canCompare(this.definition(), this.values());

  toggle(key: ListKey, value: string): void {
    const control = this.form.controls[key];
    const next = control.value.includes(value) ? control.value.filter((v) => v !== value) : [...control.value, value];
    control.setValue(next);
  }

  reset(): void {
    this.form.reset({ ...EMPTY_VALUES, compare: false }, { emitEvent: false });
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
