import { ChangeDetectionStrategy, Component, HostListener, inject, input, output, signal } from '@angular/core';

import { saveBlob } from '../../core/download';
import { ImportResult } from '../../core/inventory.service';
import { InventoryStore } from '../../core/inventory.store';
import { toCsv } from '../../core/csv';
import { validateImportFile } from './inventory-ui';

const TEMPLATE = toCsv([
  ['sku', 'name', 'category', 'unit', 'unit_cost', 'stock', 'min_stock', 'max_stock', 'location', 'supplier'],
  ['SSD-512', 'SSD 512 GB', 'spare_part', 'unidad', '64.90', '12', '5', '40', 'Bodega A', 'Proveedor S.A.'],
]);

/** Importación todo-o-nada desde CSV o Excel: primero se valida (sin escribir) y luego se confirma. */
@Component({
  selector: 'app-import-modal',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
      <div class="absolute inset-0 bg-brand-navy/50" (click)="closed.emit()" aria-hidden="true"></div>
      <section class="glass relative max-h-[92vh] w-full max-w-xl overflow-y-auto rounded-t-2xl sm:rounded-2xl" role="dialog" aria-modal="true" aria-labelledby="im-title">
        <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
          <h2 id="im-title" class="text-[16px] font-bold text-on-surface">Importar ítems</h2>
          <button type="button" (click)="closed.emit()" aria-label="Cerrar"
            class="rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">
            <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
          </button>
        </header>

        <div class="space-y-3 px-5 py-4">
          <p class="text-[13px] text-on-surface-variant">
            Archivo .csv o .xlsx de hasta 5 MB. Columnas obligatorias: <strong>sku</strong> y <strong>name</strong>.
            Si una fila tiene error no se importa nada.
            <button type="button" (click)="downloadTemplate()" class="bg-transparent p-0 font-semibold underline !text-brand-accentDeep">Descargar plantilla</button>
          </p>

          <div>
            <label for="im-file" class="text-[12px] font-bold text-on-surface">Archivo</label>
            <input id="im-file" type="file" accept=".csv,.xlsx" (change)="pick($any($event.target).files?.[0] ?? null)"
              class="mt-1 block w-full text-[13px] text-on-surface file:mr-3 file:rounded-lg file:border-0 file:bg-brand-accentLight file:px-3 file:py-2 file:text-[13px] file:font-semibold file:text-brand-accentDeep"
              [attr.aria-invalid]="fileError() !== ''" aria-describedby="im-file-err" />
            <p id="im-file-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ fileError() }}</p>
          </div>

          @if (result(); as r) {
            @if (r.success) {
              <p role="status" class="rounded-lg bg-primary-fixed px-3 py-2 text-[13px] font-semibold text-on-primary-fixed-variant">
                {{ r.total_rows }} filas válidas. Pulsa «Importar» para crearlas.
              </p>
            } @else {
              <div role="alert" class="rounded-lg bg-error-container px-3 py-2 text-on-error-container">
                <p class="text-[13px] font-semibold">{{ r.errors.length }} problema(s) en {{ r.total_rows }} filas. No se importó nada.</p>
                <ul class="mt-1 max-h-40 space-y-1 overflow-y-auto text-[12px]">
                  @for (e of r.errors.slice(0, 50); track $index) {
                    <li>Fila {{ e.row }}@if (e.field) { · <strong>{{ e.field }}</strong> }: {{ e.message }}</li>
                  }
                </ul>
                @if (r.errors.length > 50) { <p class="mt-1 text-[12px]">… y {{ r.errors.length - 50 }} más.</p> }
              </div>
            }
          }
        </div>

        <footer class="flex justify-end gap-2 border-t border-brand-grey/70 px-5 py-3">
          <button type="button" (click)="closed.emit()" [disabled]="busy()"
            class="rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep">Cancelar</button>
          <button type="button" (click)="run(true)" [disabled]="!file() || busy()"
            class="rounded-xl border border-brand-accentDeep bg-transparent px-4 py-2 text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-accentDeep disabled:opacity-50">Validar</button>
          <button type="button" (click)="run(false)" [disabled]="!result()?.success || busy()"
            class="glass-btn rounded-xl px-5 py-2 text-[13px] font-bold focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep">Importar</button>
        </footer>
      </section>
    </div>
  `,
})
export class ImportModalComponent {
  private readonly store = inject(InventoryStore);

  readonly busy = input(false);
  readonly closed = output<void>();

  readonly file = signal<File | null>(null);
  readonly fileError = signal('');
  /** Resultado de la última validación; cambiar de archivo lo descarta. */
  readonly result = signal<ImportResult | null>(null);

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closed.emit();
  }

  pick(file: File | null): void {
    this.result.set(null);
    const error = file ? validateImportFile(file) : '';
    this.fileError.set(error);
    this.file.set(file && !error ? file : null);
  }

  run(dryRun: boolean): void {
    const file = this.file();
    if (!file || this.busy()) {
      return;
    }
    this.store.importFile(file, dryRun).subscribe((result) => {
      if (!result) {
        return;
      }
      if (dryRun) {
        this.result.set(result);
      } else if (result.success) {
        this.closed.emit();
      } else {
        this.result.set(result);
      }
    });
  }

  downloadTemplate(): void {
    saveBlob(new Blob(['﻿' + TEMPLATE], { type: 'text/csv;charset=utf-8' }), 'plantilla-inventario.csv');
  }
}
