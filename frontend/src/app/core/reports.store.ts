import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable } from 'rxjs';

import { toApiFilters, FilterValues } from '../features/reports/report-filters';
import { apiErrorMessage } from './api-errors';
import { Period } from './dashboard-kpis.service';
import { saveBlob } from './download';
import {
  Catalog,
  ExportFormat,
  ReportDefinition,
  ReportKey,
  ReportPreview,
  ReportRun,
  ReportsOverview,
  ReportsService,
} from './reports.service';
import { ToastService } from './toast.service';

export interface ReportsState {
  catalog: Catalog | null;
  catalogLoading: boolean;
  catalogError: string;
  selected: ReportKey | null;
  preview: ReportPreview | null;
  previewLoading: boolean;
  previewError: string;
  period: Period;
  overview: ReportsOverview | null;
  overviewLoading: boolean;
  history: ReportRun[];
  historyTotal: number;
  historyPage: number;
  exporting: ExportFormat | null;
}

const INITIAL: ReportsState = {
  catalog: null,
  catalogLoading: true,
  catalogError: '',
  selected: null,
  preview: null,
  previewLoading: false,
  previewError: '',
  period: '30d',
  overview: null,
  overviewLoading: true,
  history: [],
  historyTotal: 0,
  historyPage: 1,
  exporting: null,
};

export const HISTORY_PAGE_SIZE = 8;

/** Observer pattern store de la galería de reportes. */
@Injectable({ providedIn: 'root' })
export class ReportsStore {
  private readonly api = inject(ReportsService);
  private readonly toasts = inject(ToastService);
  private readonly subject = new BehaviorSubject<ReportsState>(INITIAL);
  /** Descarta la respuesta de una vista previa que ya no es la última pedida. */
  private previewToken = 0;

  readonly state$: Observable<ReportsState> = this.subject.asObservable();

  private get value(): ReportsState {
    return this.subject.value;
  }

  private patch(changes: Partial<ReportsState>): void {
    this.subject.next({ ...this.value, ...changes });
  }

  definition(): ReportDefinition | null {
    const { catalog, selected } = this.value;
    return catalog?.reports.find((report) => report.key === selected) ?? null;
  }

  load(): void {
    this.patch({ catalogLoading: true, catalogError: '' });
    this.api.catalog().subscribe({
      next: (catalog) =>
        this.patch({ catalog, catalogLoading: false, selected: this.value.selected ?? catalog.reports[0]?.key ?? null }),
      error: (error) =>
        this.patch({ catalogLoading: false, catalogError: apiErrorMessage(error, 'No se pudo cargar la galería de reportes.') }),
    });
    this.loadOverview();
    this.loadHistory(1);
  }

  select(key: ReportKey): void {
    this.previewToken++;
    this.patch({ selected: key, preview: null, previewError: '', previewLoading: false });
  }

  setPeriod(period: Period): void {
    this.patch({ period });
    this.loadOverview();
  }

  loadHistory(page: number): void {
    this.api.history(page, HISTORY_PAGE_SIZE).subscribe({
      next: ({ items, total }) => this.patch({ history: items, historyTotal: total, historyPage: page }),
      error: () => this.patch({ history: [], historyTotal: 0 }),
    });
  }

  /** Vista previa con los filtros ya validados por el formulario. */
  requestPreview(values: FilterValues, compare: boolean): void {
    const definition = this.definition();
    if (!definition) {
      return;
    }
    const token = ++this.previewToken;
    this.patch({ previewLoading: true, previewError: '' });
    this.api.preview(definition.key, toApiFilters(definition, values), compare && definition.supports_compare).subscribe({
      next: (preview) => {
        if (token === this.previewToken) {
          this.patch({ preview, previewLoading: false });
        }
      },
      error: (error) => {
        if (token === this.previewToken) {
          this.patch({ previewLoading: false, previewError: apiErrorMessage(error, 'No se pudo generar la vista previa.') });
        }
      },
    });
  }

  /** Genera y descarga el archivo; un segundo clic mientras se genera se ignora. */
  export(format: ExportFormat, values: FilterValues): void {
    const definition = this.definition();
    if (!definition || this.value.exporting) {
      return;
    }
    this.patch({ exporting: format });
    this.api.generate(definition.key, format, toApiFilters(definition, values)).subscribe({
      next: ({ blob, filename }) => {
        saveBlob(blob, filename);
        this.patch({ exporting: null });
        this.toasts.success(`Reporte generado: ${filename}`);
        this.loadOverview();
        this.loadHistory(1);
      },
      error: async (error) => {
        this.patch({ exporting: null });
        this.toasts.error(apiErrorMessage(await readableError(error), 'No se pudo generar el reporte.'));
      },
    });
  }

  private loadOverview(): void {
    this.patch({ overviewLoading: true });
    const period = this.value.period;
    this.api.overview(period).subscribe({
      next: (overview) => {
        if (this.value.period === period) {
          this.patch({ overview, overviewLoading: false });
        }
      },
      error: () => this.patch({ overview: null, overviewLoading: false }),
    });
  }
}

/**
 * Una descarga pide `blob`: el cuerpo de un error llega como Blob y hay que leerlo como JSON
 * para que `apiErrorMessage` vea su `code` y no un objeto opaco.
 */
export async function readableError(error: unknown): Promise<unknown> {
  const response = error as { error?: unknown; status?: number; headers?: unknown };
  if (response?.error instanceof Blob) {
    try {
      const body = JSON.parse(await response.error.text());
      return Object.assign(Object.create(Object.getPrototypeOf(error)), error, { error: body });
    } catch {
      return error;
    }
  }
  return error;
}
