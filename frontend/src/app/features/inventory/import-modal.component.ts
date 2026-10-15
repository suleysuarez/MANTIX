import { ChangeDetectionStrategy, Component, HostListener, computed, inject, input, output, signal } from '@angular/core';

import { saveBlob } from '../../core/download';
import { ImportResult, InventoryService } from '../../core/inventory.service';
import { InventoryStore } from '../../core/inventory.store';
import { ToastService } from '../../core/toast.service';
import { IMPORT_MAX_ROWS, validateImportFile } from './inventory-ui';

const SHOWN_ERRORS = 50;
const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';

/**
 * Importación fila por fila: primero se valida sin escribir y se muestra un resumen (filas válidas,
 * filas con errores y cada problema con su fila y columna); luego se confirma. Con errores se puede
 * importar solo lo válido, pidiendo confirmación expresa.
 */
@Component({
  selector: 'app-import-modal',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="fixed inset-0 z-[55] flex items-end justify-center p-0 sm:items-center sm:p-4">
      <div class="absolute inset-0 bg-brand-navy/50" (click)="closed.emit()" aria-hidden="true"></div>
      <section class="glass relative max-h-[92vh] w-full max-w-2xl overflow-y-auto rounded-t-2xl sm:rounded-2xl" role="dialog" aria-modal="true" aria-labelledby="im-title">
        <header class="flex items-center justify-between gap-3 border-b border-brand-grey/70 px-5 py-3">
          <h2 id="im-title" class="text-[16px] font-bold text-on-surface">Importar ítems</h2>
          <button type="button" (click)="closed.emit()" aria-label="Cerrar"
            [class]="focus + ' rounded-lg bg-transparent p-1 !text-on-surface-variant hover:bg-surface-container'">
            <span class="material-symbols-outlined text-[20px]" aria-hidden="true">close</span>
          </button>
        </header>

        <div class="space-y-3 px-5 py-4">
          <div class="flex flex-wrap items-start justify-between gap-3 rounded-xl bg-surface-container-low p-3">
            <ul class="space-y-0.5 text-[12px] text-on-surface-variant">
              <li><strong class="text-on-surface">Formato:</strong> .csv o .xlsx (la plantilla es un Excel con listas y reglas)</li>
              <li><strong class="text-on-surface">Tamaño máximo:</strong> 5 MB · hasta {{ maxRows }} filas</li>
              <li><strong class="text-on-surface">Columnas obligatorias:</strong> sku y name</li>
              <li>Se revisa cada fila (negativos, tipos, códigos repetidos, mínimo mayor que máximo) antes de importar.</li>
            </ul>
            <button type="button" (click)="downloadTemplate()" [disabled]="downloading()"
              [class]="focus + ' flex shrink-0 items-center gap-1.5 rounded-lg border border-brand-accentDeep bg-transparent px-3 py-1.5 text-[12px] font-semibold !text-brand-accentDeep hover:bg-surface-container disabled:opacity-50'">
              <span class="material-symbols-outlined text-[16px]" aria-hidden="true">table_view</span> {{ downloading() ? 'Descargando…' : 'Descargar plantilla (Excel)' }}
            </button>
          </div>

          <div>
            <label for="im-file" class="text-[12px] font-bold text-on-surface">Archivo</label>
            <input id="im-file" type="file" accept=".csv,.xlsx" (change)="pick($any($event.target).files?.[0] ?? null)"
              class="mt-1 block w-full text-[13px] text-on-surface file:mr-3 file:rounded-lg file:border-0 file:bg-brand-accentLight file:px-3 file:py-2 file:text-[13px] file:font-semibold file:text-brand-accentDeep"
              [attr.aria-invalid]="fileError() !== ''" aria-describedby="im-file-err" />
            <p id="im-file-err" class="mt-1 min-h-[1rem] text-[12px] text-error" role="alert">{{ fileError() }}</p>
          </div>

          @if (result(); as r) {
            <section aria-label="Resumen de la validación" class="space-y-2">
              <dl class="grid grid-cols-3 gap-2 text-center">
                <div class="rounded-xl bg-surface-container px-2 py-2"><dd class="text-[20px] font-extrabold text-on-surface">{{ r.total_rows }}</dd><dt class="text-[11px] font-semibold text-on-surface-variant">Filas leídas</dt></div>
                <div class="rounded-xl bg-primary-fixed px-2 py-2 text-on-primary-fixed-variant"><dd class="text-[20px] font-extrabold">{{ valid() }}</dd><dt class="text-[11px] font-semibold">Válidas</dt></div>
                <div class="rounded-xl px-2 py-2" [class]="invalid() ? 'bg-error-container text-on-error-container' : 'bg-surface-container text-on-surface-variant'"><dd class="text-[20px] font-extrabold">{{ invalid() }}</dd><dt class="text-[11px] font-semibold">Con errores</dt></div>
              </dl>

              @if (r.errors.length === 0) {
                <p role="status" class="rounded-lg bg-primary-fixed px-3 py-2 text-[13px] font-semibold text-on-primary-fixed-variant">
                  Todas las filas son válidas. Pulsa «Importar» para crear {{ valid() }} {{ valid() === 1 ? 'ítem' : 'ítems' }}.
                </p>
              } @else {
                <div role="alert" class="rounded-lg bg-error-container px-3 py-2 text-on-error-container">
                  <p class="text-[13px] font-semibold">{{ r.errors.length }} {{ r.errors.length === 1 ? 'problema' : 'problemas' }} en {{ invalid() }} {{ invalid() === 1 ? 'fila' : 'filas' }}.</p>
                  <div class="mt-1 max-h-44 overflow-y-auto">
                    <table class="w-full text-left text-[12px]">
                      <caption class="sr-only">Errores por fila</caption>
                      <thead><tr class="text-[11px] uppercase tracking-wide"><th scope="col" class="w-14 py-0.5 pr-2">Fila</th><th scope="col" class="w-28 py-0.5 pr-2">Columna</th><th scope="col" class="py-0.5">Problema</th></tr></thead>
                      <tbody>
                        @for (e of r.errors.slice(0, shown); track $index) {
                          <tr class="border-t border-on-error-container/20 align-top"><td class="py-0.5 pr-2 font-semibold">{{ e.row }}</td><td class="py-0.5 pr-2 font-mono">{{ e.field ?? '—' }}</td><td class="py-0.5">{{ e.message }}</td></tr>
                        }
                      </tbody>
                    </table>
                    @if (r.errors.length > shown) { <p class="mt-1 text-[12px]">… y {{ r.errors.length - shown }} más.</p> }
                  </div>
                </div>

                @if (valid() > 0) {
                  <label class="flex items-start gap-2 rounded-lg border border-brand-grey bg-surface-container-lowest p-3 text-[13px] text-on-surface">
                    <input type="checkbox" class="mt-0.5 h-4 w-4 accent-brand-accentDeep" [checked]="confirmSkip()" (change)="confirmSkip.set($any($event.target).checked)" />
                    <span>Importar solo las {{ valid() }} filas válidas. Entiendo que las {{ invalid() }} filas con errores <strong>no se importarán</strong> y habrá que corregirlas y subirlas aparte.</span>
                  </label>
                } @else {
                  <p class="text-[12px] text-on-surface-variant">Ninguna fila es válida: corrige el archivo y vuelve a validarlo.</p>
                }
              }
            </section>
          }
        </div>

        <footer class="flex flex-wrap justify-end gap-2 border-t border-brand-grey/70 px-5 py-3">
          <button type="button" (click)="closed.emit()" [disabled]="busy()"
            [class]="focus + ' rounded-lg bg-transparent px-4 py-2 text-[13px] font-semibold !text-on-surface-variant hover:bg-surface-container'">Cancelar</button>
          <button type="button" (click)="run(true)" [disabled]="!file() || busy()"
            [class]="focus + ' rounded-xl border border-brand-accentDeep bg-transparent px-4 py-2 text-[13px] font-semibold !text-brand-accentDeep hover:bg-surface-container disabled:opacity-50'">{{ result() ? 'Validar de nuevo' : 'Validar' }}</button>
          @if (hasErrors()) {
            <button type="button" (click)="run(false, true)" [disabled]="!canImportValid() || busy()"
              [class]="focus + ' glass-btn rounded-xl px-5 py-2 text-[13px] font-bold disabled:opacity-50'">Importar solo las válidas ({{ valid() }})</button>
          } @else {
            <button type="button" (click)="run(false)" [disabled]="!canImportAll() || busy()"
              [class]="focus + ' glass-btn rounded-xl px-5 py-2 text-[13px] font-bold disabled:opacity-50'">Importar{{ canImportAll() ? ' (' + valid() + ')' : '' }}</button>
          }
        </footer>
      </section>
    </div>
  `,
})
export class ImportModalComponent {
  private readonly store = inject(InventoryStore);
  private readonly api = inject(InventoryService);
  private readonly toasts = inject(ToastService);

  readonly busy = input(false);
  readonly closed = output<void>();

  readonly focus = FOCUS;
  readonly shown = SHOWN_ERRORS;
  readonly maxRows = IMPORT_MAX_ROWS.toLocaleString('es-MX');
  readonly file = signal<File | null>(null);
  readonly fileError = signal('');
  /** Resultado de la última validación; cambiar de archivo lo descarta. */
  readonly result = signal<ImportResult | null>(null);
  /** Confirmación expresa para importar solo lo válido cuando hay errores. */
  readonly confirmSkip = signal(false);

  readonly valid = computed(() => this.result()?.valid_rows ?? (this.result()?.success ? (this.result()?.total_rows ?? 0) : 0));
  readonly invalid = computed(() => this.result()?.error_rows ?? new Set((this.result()?.errors ?? []).map((e) => e.row)).size);
  readonly hasErrors = computed(() => (this.result()?.errors.length ?? 0) > 0);
  readonly canImportAll = computed(() => !!this.result() && !this.hasErrors() && this.valid() > 0);
  readonly canImportValid = computed(() => this.hasErrors() && this.valid() > 0 && this.confirmSkip());

  @HostListener('document:keydown.escape')
  onEscape(): void {
    this.closed.emit();
  }

  pick(file: File | null): void {
    this.result.set(null);
    this.confirmSkip.set(false);
    const error = file ? validateImportFile(file) : '';
    this.fileError.set(error);
    this.file.set(file && !error ? file : null);
  }

  run(dryRun: boolean, skipInvalid = false): void {
    const file = this.file();
    if (!file || this.busy()) {
      return;
    }
    this.store.importFile(file, dryRun, skipInvalid).subscribe((result) => {
      if (!result) {
        return;
      }
      if (dryRun) {
        this.confirmSkip.set(false);
        this.result.set(result);
      } else if (result.created > 0) {
        this.closed.emit();
      } else {
        this.result.set(result);
      }
    });
  }

  /** Baja la plantilla de Excel que arma el servidor (columnas con color, listas y reglas, e instrucciones). */
  readonly downloading = signal(false);

  downloadTemplate(): void {
    if (this.downloading()) {
      return;
    }
    this.downloading.set(true);
    this.api.importTemplate().subscribe({
      next: (blob) => {
        this.downloading.set(false);
        saveBlob(blob, 'plantilla-inventario.xlsx');
      },
      error: () => {
        this.downloading.set(false);
        this.toasts.error('No se pudo descargar la plantilla. Inténtalo de nuevo.');
      },
    });
  }
}
