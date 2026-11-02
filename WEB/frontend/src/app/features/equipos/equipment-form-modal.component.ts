import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  EventEmitter,
  HostListener,
  Input,
  OnInit,
  Output,
  ViewChild,
  signal,
} from '@angular/core';
import {
  AbstractControl,
  FormControl,
  FormGroup,
  ReactiveFormsModule,
  ValidationErrors,
  Validators,
} from '@angular/forms';

import { EQUIPMENT_STATUSES, statusInfo } from '../../core/equipment-status';
import {
  CustodianCandidate,
  Equipment,
  EquipmentPayload,
  EquipmentType,
  LocationItem,
} from '../../core/equipment.service';
import { SaveRequest } from '../../core/equipment.store';
import { CustodianPickerComponent } from './custodian-picker.component';

export const ALLOWED_EXTENSIONS = ['.pdf', '.png', '.jpg', '.jpeg', '.txt'] as const;
export const MAX_FILE_BYTES = 10 * 1024 * 1024;
export const MAX_FILES = 5;

/** Valida un archivo contra las mismas reglas que aplica la API (tipo y tamaño). */
export function fileProblem(file: File): string | null {
  const name = file.name.toLowerCase();
  if (!ALLOWED_EXTENSIONS.some((extension) => name.endsWith(extension))) {
    return `«${file.name}»: tipo no permitido (usa ${ALLOWED_EXTENSIONS.join(', ')}).`;
  }
  if (file.size === 0) {
    return `«${file.name}»: el archivo está vacío.`;
  }
  if (file.size > MAX_FILE_BYTES) {
    return `«${file.name}»: supera los 10 MB.`;
  }
  return null;
}

/** El fin de la garantía no puede ser anterior a su inicio. */
export function warrantyOrder(group: AbstractControl): ValidationErrors | null {
  const start = group.get('warranty_start_date')?.value as string;
  const end = group.get('warranty_end_date')?.value as string;
  return start && end && end < start ? { warrantyOrder: true } : null;
}

const INPUT =
  'w-full rounded-xl !border bg-white p-2.5 text-xs text-slate-800 focus:outline-none focus:ring-2 disabled:bg-slate-100 disabled:text-slate-500';
const OK = ' !border-slate-200 focus:border-sky-500 focus:ring-sky-500/20';
const BAD = ' !border-rose-300 bg-rose-50/50 focus:border-rose-500 focus:ring-rose-500/20';

/** Dumb component: alta y edición de equipos. No conoce servicios, solo emite la solicitud. */
@Component({
  selector: 'app-equipment-form-modal',
  standalone: true,
  imports: [ReactiveFormsModule, CustodianPickerComponent],
  template: `
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4" role="dialog" aria-modal="true"
      aria-labelledby="equipment-form-title">
      <div class="fixed inset-0 bg-slate-900/60 backdrop-blur-sm" (click)="close()" aria-hidden="true"></div>
      <div #dialog tabindex="-1"
        class="relative z-10 flex max-h-[90vh] w-full max-w-2xl flex-col overflow-hidden rounded-2xl !border !border-slate-200 bg-white shadow-2xl focus:outline-none">
        <header class="flex items-center justify-between !border-b !border-slate-100 bg-slate-50/70 px-6 py-4">
          <div class="flex items-center gap-3">
            <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-sky-100 text-sky-700">
              <span class="material-symbols-outlined text-[22px]">{{ editing ? 'edit' : 'add' }}</span>
            </span>
            <div>
              <h2 id="equipment-form-title" class="text-base font-bold text-slate-900">
                {{ editing ? 'Editar equipo' : 'Registrar nuevo equipo' }}
              </h2>
              <p class="text-xs text-slate-500">
                {{ editing ? 'Actualiza la ficha técnica y el estado del dispositivo.' : 'Completa la ficha técnica, ubicación y estado del dispositivo.' }}
              </p>
            </div>
          </div>
          <button type="button" (click)="close()" [disabled]="saving" aria-label="Cerrar"
            class="bg-transparent flex h-8 w-8 items-center justify-center rounded-lg !text-slate-400 hover:bg-slate-100 hover:text-slate-600 disabled:opacity-50">
            <span class="material-symbols-outlined text-[20px]">close</span>
          </button>
        </header>

        <form [formGroup]="form" (ngSubmit)="submit()" class="flex-1 space-y-6 overflow-y-auto p-6 text-xs" novalidate>
          @if (error) {
            <p role="alert" class="rounded-xl !border !border-rose-200 bg-rose-50 px-3 py-2 font-medium text-rose-700">{{ error }}</p>
          }

          <section class="space-y-3">
            <div class="flex items-center justify-between !border-b !border-slate-100 pb-1">
              <h3 class="flex items-center gap-2 text-[11px] font-bold uppercase tracking-wider text-slate-900">
                <span class="flex h-5 w-5 items-center justify-center rounded-full bg-brand-sidebar text-[10px] font-bold text-brand-mustard">1</span>
                Información general
              </h3>
              <span class="text-[11px] text-slate-400"><span class="font-bold text-rose-500">*</span> Campos requeridos</span>
            </div>
            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
              <div>
                <label for="eq-asset" class="mb-1 block font-semibold text-slate-700">Código de activo <span class="text-rose-500">*</span></label>
                <input id="eq-asset" formControlName="asset_tag" placeholder="Ej: EQ-029" [class]="cls('asset_tag') + ' font-mono font-bold'" />
                @if (editing) {
                  <p class="mt-1 text-[11px] text-slate-400">El código no se puede cambiar después del registro.</p>
                }
                @if (invalid('asset_tag')) {
                  <p class="mt-1 text-[11px] font-medium text-rose-600">Indica el código de activo (máx. 50 caracteres).</p>
                }
              </div>
              <div>
                <label for="eq-type" class="mb-1 block font-semibold text-slate-700">Categoría <span class="text-rose-500">*</span></label>
                <select id="eq-type" formControlName="equipment_type_id" [class]="cls('equipment_type_id') + ' bg-white font-medium'">
                  <option [ngValue]="0">Seleccionar categoría</option>
                  @for (type of types; track type.id) {
                    <option [ngValue]="type.id">{{ type.name }}</option>
                  }
                </select>
                @if (invalid('equipment_type_id')) {
                  <p class="mt-1 text-[11px] font-medium text-rose-600">Elige una categoría.</p>
                }
              </div>
              <div>
                <label for="eq-brand" class="mb-1 block font-semibold text-slate-700">Marca <span class="text-rose-500">*</span></label>
                <input id="eq-brand" formControlName="brand" placeholder="Ej: Dell, HP, Lenovo" [class]="cls('brand')" />
                @if (invalid('brand')) {
                  <p class="mt-1 text-[11px] font-medium text-rose-600">Indica la marca.</p>
                }
              </div>
              <div>
                <label for="eq-model" class="mb-1 block font-semibold text-slate-700">Modelo <span class="text-rose-500">*</span></label>
                <input id="eq-model" formControlName="model" placeholder="Ej: Latitude 5540" [class]="cls('model')" />
                @if (invalid('model')) {
                  <p class="mt-1 text-[11px] font-medium text-rose-600">Indica el modelo.</p>
                }
              </div>
              <div class="md:col-span-2">
                <label for="eq-serial" class="mb-1 block font-semibold text-slate-700">Número de serie (SN)</label>
                <input id="eq-serial" formControlName="serial_number" placeholder="Ej: SN-DELL-882194" [class]="cls('serial_number') + ' font-mono'" />
                @if (invalid('serial_number')) {
                  <p class="mt-1 text-[11px] font-medium text-rose-600">Máximo 100 caracteres.</p>
                }
              </div>
              <div class="md:col-span-2">
                <label for="eq-desc" class="mb-1 block font-semibold text-slate-700">Descripción y especificaciones técnicas</label>
                <textarea id="eq-desc" formControlName="description" rows="2"
                  placeholder="Ej: Intel Core i7 13th Gen, 16GB RAM DDR5, 512GB SSD NVMe" [class]="cls('description')"></textarea>
              </div>
            </div>
          </section>

          @if (!editing) {
            <section class="space-y-3">
              <h3 class="flex items-center gap-2 !border-b !border-slate-100 pb-1 text-[11px] font-bold uppercase tracking-wider text-slate-900">
                <span class="flex h-5 w-5 items-center justify-center rounded-full bg-brand-sidebar text-[10px] font-bold text-brand-mustard">2</span>
                Asignación y ubicación
              </h3>
              <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                <div>
                  <label for="eq-location" class="mb-1 block font-semibold text-slate-700">Ubicación física o área</label>
                  <select id="eq-location" formControlName="location_id" [class]="cls('location_id') + ' bg-white font-medium'">
                    <option [ngValue]="0">Sin ubicación por ahora</option>
                    @for (location of locations; track location.id) {
                      <option [ngValue]="location.id">{{ location.name }}</option>
                    }
                  </select>
                </div>
                <div>
                  <span class="mb-1 block font-semibold text-slate-700">Responsable asignado / custodio</span>
                  <app-custodian-picker (picked)="custodian.set($event)" />
                </div>
              </div>
            </section>
          }

          <section class="space-y-3">
            <h3 class="flex items-center gap-2 !border-b !border-slate-100 pb-1 text-[11px] font-bold uppercase tracking-wider text-slate-900">
              <span class="flex h-5 w-5 items-center justify-center rounded-full bg-brand-sidebar text-[10px] font-bold text-brand-mustard">{{ editing ? 2 : 3 }}</span>
              Estado y garantía
            </h3>
            <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
              <div>
                <label for="eq-status" class="mb-1 block font-semibold text-slate-700">Estado <span class="text-rose-500">*</span></label>
                <select id="eq-status" formControlName="status" [class]="cls('status') + ' bg-white font-semibold'">
                  @for (status of statuses; track status) {
                    <option [value]="status">{{ label(status) }}</option>
                  }
                </select>
              </div>
              <div>
                <label for="eq-cost" class="mb-1 block font-semibold text-slate-700">Costo de adquisición</label>
                <input id="eq-cost" type="number" step="0.01" min="0" formControlName="purchase_cost" placeholder="0.00" [class]="cls('purchase_cost')" />
                @if (invalid('purchase_cost')) {
                  <p class="mt-1 text-[11px] font-medium text-rose-600">El costo no puede ser negativo.</p>
                }
              </div>
              <div>
                <label for="eq-purchase" class="mb-1 block font-semibold text-slate-700">Fecha de adquisición</label>
                <input id="eq-purchase" type="date" formControlName="purchase_date" [class]="cls('purchase_date')" />
              </div>
              <div class="grid grid-cols-2 gap-3">
                <div>
                  <label for="eq-war-start" class="mb-1 block font-semibold text-slate-700">Garantía desde</label>
                  <input id="eq-war-start" type="date" formControlName="warranty_start_date" [class]="cls('warranty_start_date')" />
                </div>
                <div>
                  <label for="eq-war-end" class="mb-1 block font-semibold text-slate-700">Garantía hasta</label>
                  <input id="eq-war-end" type="date" formControlName="warranty_end_date" [class]="warrantyBad ? bad : cls('warranty_end_date')" />
                </div>
              </div>
              @if (warrantyBad) {
                <p class="text-[11px] font-medium text-rose-600 md:col-span-2">La garantía no puede terminar antes de empezar.</p>
              }
            </div>
          </section>

          @if (!editing) {
            <section class="space-y-3">
              <h3 class="flex items-center gap-2 !border-b !border-slate-100 pb-1 text-[11px] font-bold uppercase tracking-wider text-slate-900">
                <span class="flex h-5 w-5 items-center justify-center rounded-full bg-brand-sidebar text-[10px] font-bold text-brand-mustard">4</span>
                Adjuntos
              </h3>
              <input #picker type="file" multiple class="hidden" [accept]="accept" (change)="addFiles(picker.files); picker.value = ''" />
              <div role="button" tabindex="0" (click)="picker.click()" (keydown.enter)="picker.click()" (keydown.space)="picker.click(); $event.preventDefault()"
                (dragover)="$event.preventDefault()" (drop)="$event.preventDefault(); addFiles($any($event).dataTransfer?.files ?? null)"
                class="cursor-pointer rounded-2xl !border-2 !border-dashed !border-slate-200 bg-slate-50/70 p-4 text-center transition-colors hover:border-sky-400 hover:bg-sky-50/40">
                <span class="material-symbols-outlined text-[28px] text-slate-400">upload_file</span>
                <p class="text-xs font-semibold text-slate-800">Arrastra una foto o ficha técnica, o <span class="text-sky-600 underline">explora tus archivos</span></p>
                <p class="mt-0.5 text-[10px] text-slate-400">PDF, JPG, PNG o TXT · hasta 10 MB · máximo {{ maxFiles }} archivos</p>
              </div>
              @for (problem of fileProblems(); track problem) {
                <p role="alert" class="text-[11px] font-medium text-rose-600">{{ problem }}</p>
              }
              @if (files().length > 0) {
                <ul class="m-0 list-none p-0 space-y-1.5">
                  @for (file of files(); track file; let index = $index) {
                    <li class="flex items-center justify-between rounded-lg !border !border-slate-200 bg-white px-3 py-1.5">
                      <span class="truncate font-medium text-slate-700">{{ file.name }} <span class="text-slate-400">· {{ sizeLabel(file.size) }}</span></span>
                      <button type="button" (click)="removeFile(index)" [attr.aria-label]="'Quitar ' + file.name"
                        class="bg-transparent !text-slate-400 hover:text-rose-600"><span class="material-symbols-outlined text-[18px]">close</span></button>
                    </li>
                  }
                </ul>
              }
            </section>
          }
        </form>

        <footer class="flex items-center justify-between gap-3 !border-t !border-slate-200/90 bg-slate-50 px-6 py-4">
          <span class="hidden items-center gap-1.5 text-[11px] font-medium text-slate-400 sm:flex">
            <span class="material-symbols-outlined text-[16px]">info</span>
            {{ editing ? 'Los cambios quedan registrados en la auditoría.' : 'El equipo se integra de inmediato al inventario.' }}
          </span>
          <div class="ml-auto flex items-center gap-2.5">
            <button type="button" (click)="close()" [disabled]="saving"
              class="rounded-xl !border !border-slate-200 bg-white px-4 py-2.5 !text-xs !font-semibold !text-slate-700 transition-colors hover:bg-slate-100 disabled:opacity-50">
              Cancelar
            </button>
            <button type="button" (click)="submit()" [disabled]="saving"
              class="flex items-center gap-2 rounded-xl !border !border-slate-700/60 bg-brand-sidebar px-5 py-2.5 !text-xs !font-bold !uppercase tracking-wider !text-white shadow-md transition-all hover:bg-slate-900 active:scale-95 disabled:opacity-60">
              <span class="material-symbols-outlined text-[18px] text-brand-mustard">save</span>
              {{ saving ? 'Guardando…' : editing ? 'Guardar cambios' : 'Guardar equipo' }}
            </button>
          </div>
        </footer>
      </div>
    </div>
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class EquipmentFormModalComponent implements OnInit, AfterViewInit {
  /** `null` para registrar uno nuevo. */
  @Input() equipment: Equipment | null = null;
  @Input() types: readonly EquipmentType[] = [];
  @Input() locations: readonly LocationItem[] = [];
  @Input() saving = false;
  @Input() error = '';
  @Output() readonly closed = new EventEmitter<void>();
  @Output() readonly submitted = new EventEmitter<SaveRequest>();

  @ViewChild('dialog', { static: true }) private dialog!: ElementRef<HTMLElement>;

  readonly statuses = EQUIPMENT_STATUSES;
  readonly accept = ALLOWED_EXTENSIONS.join(',');
  readonly maxFiles = MAX_FILES;
  readonly bad = INPUT + BAD;
  readonly files = signal<File[]>([]);
  readonly fileProblems = signal<string[]>([]);
  readonly custodian = signal<CustodianCandidate | null>(null);

  readonly form = new FormGroup(
    {
      asset_tag: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(50)] }),
      serial_number: new FormControl('', { nonNullable: true, validators: [Validators.maxLength(100)] }),
      equipment_type_id: new FormControl(0, { nonNullable: true, validators: [Validators.min(1)] }),
      brand: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(100)] }),
      model: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(100)] }),
      description: new FormControl('', { nonNullable: true }),
      status: new FormControl('in_storage', { nonNullable: true }),
      location_id: new FormControl(0, { nonNullable: true }),
      purchase_date: new FormControl('', { nonNullable: true }),
      purchase_cost: new FormControl<number | null>(null, { validators: [Validators.min(0)] }),
      warranty_start_date: new FormControl('', { nonNullable: true }),
      warranty_end_date: new FormControl('', { nonNullable: true }),
    },
    { validators: warrantyOrder },
  );

  get editing(): boolean {
    return this.equipment !== null;
  }

  get warrantyBad(): boolean {
    const end = this.form.controls.warranty_end_date;
    return this.form.hasError('warrantyOrder') && (end.touched || end.dirty);
  }

  ngOnInit(): void {
    const item = this.equipment;
    if (item) {
      this.form.patchValue({
        asset_tag: item.asset_tag,
        serial_number: item.serial_number ?? '',
        equipment_type_id: item.equipment_type_id,
        brand: item.brand,
        model: item.model,
        description: item.description ?? '',
        status: item.status,
        purchase_date: item.purchase_date ?? '',
        purchase_cost: item.purchase_cost === null ? null : Number(item.purchase_cost),
        warranty_start_date: item.warranty_start_date ?? '',
        warranty_end_date: item.warranty_end_date ?? '',
      });
      this.form.controls.asset_tag.disable();
    }
  }

  ngAfterViewInit(): void {
    // Lleva el foco al diálogo para que Escape y Tab actúen dentro de él.
    this.dialog.nativeElement.focus();
  }

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.close();
  }

  close(): void {
    if (!this.saving) {
      this.closed.emit();
    }
  }

  invalid(name: string): boolean {
    const control = this.form.get(name);
    return !!control && control.invalid && (control.touched || control.dirty);
  }

  cls(name: string): string {
    return INPUT + (this.invalid(name) ? BAD : OK);
  }

  label(status: string): string {
    return statusInfo(status).label;
  }

  addFiles(list: FileList | null): void {
    if (!list) {
      return;
    }
    const accepted = [...this.files()];
    const problems: string[] = [];
    for (const file of Array.from(list)) {
      const problem = fileProblem(file);
      if (problem) {
        problems.push(problem);
      } else if (accepted.length >= MAX_FILES) {
        problems.push(`«${file.name}»: máximo ${MAX_FILES} archivos por alta.`);
      } else if (!accepted.some((item) => item.name === file.name && item.size === file.size)) {
        accepted.push(file);
      }
    }
    this.files.set(accepted);
    this.fileProblems.set(problems);
  }

  removeFile(index: number): void {
    this.files.update((files) => files.filter((_, position) => position !== index));
  }

  sizeLabel(bytes: number): string {
    return bytes >= 1024 * 1024 ? `${(bytes / (1024 * 1024)).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
  }

  submit(): void {
    this.form.markAllAsTouched();
    if (this.form.invalid || this.saving) {
      return;
    }
    const value = this.form.getRawValue();
    const payload: EquipmentPayload = {
      asset_tag: value.asset_tag.trim(),
      serial_number: value.serial_number.trim() || null,
      equipment_type_id: value.equipment_type_id,
      brand: value.brand.trim(),
      model: value.model.trim(),
      description: value.description.trim() || null,
      status: value.status,
      purchase_date: value.purchase_date || null,
      purchase_cost: value.purchase_cost,
      warranty_start_date: value.warranty_start_date || null,
      warranty_end_date: value.warranty_end_date || null,
    };
    this.submitted.emit({
      id: this.equipment?.id ?? null,
      payload,
      locationId: value.location_id || null,
      custodianId: this.custodian()?.id ?? null,
      files: this.files(),
    });
  }
}
