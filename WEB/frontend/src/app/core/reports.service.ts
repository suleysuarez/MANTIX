import { HttpClient, HttpParams, HttpResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { apiBaseUrl } from './api.config';
import { Period } from './dashboard-kpis.service';

export type ReportKey =
  | 'equipment'
  | 'tickets'
  | 'summary'
  | 'maintenance_plans'
  | 'inventory_items'
  | 'inventory_movements';
export type ExportFormat = 'xlsx' | 'pdf' | 'csv';
export type FilterKey = 'statuses' | 'priorities' | 'categories' | 'kinds' | 'equipment_type_ids' | 'dates' | 'days';

export interface FilterOption {
  value: string;
  label: string;
}

export interface FilterDefinition {
  key: FilterKey;
  label: string;
  kind: 'multiselect' | 'dates' | 'days';
  options: FilterOption[];
}

export interface ReportDefinition {
  key: ReportKey;
  title: string;
  description: string;
  /** Nombre de icono de Material Symbols. */
  icon: string;
  filters: FilterDefinition[];
  supports_compare: boolean;
}

export interface Catalog {
  reports: ReportDefinition[];
  max_rows: number;
  max_range_days: number;
  formats: ExportFormat[];
}

/** Filtros tal como los espera la API (todo opcional; una lista vacía no se envía). */
export interface ReportFilters {
  statuses?: string[];
  priorities?: string[];
  categories?: string[];
  kinds?: string[];
  equipment_type_ids?: number[];
  date_from?: string;
  date_to?: string;
  days?: number;
}

export interface PreviewColumn {
  key: string;
  header: string;
}

export interface Comparison {
  current_total: number;
  previous_total: number;
  change_pct: number | null;
  previous_from: string;
  previous_to: string;
}

export interface ReportPreview {
  report: ReportKey;
  title: string;
  columns: PreviewColumn[];
  rows: Record<string, string>[];
  total_rows: number;
  /** Hay más filas que el límite de exportación. */
  truncated: boolean;
  comparison: Comparison | null;
}

export interface UsedReport {
  report: ReportKey;
  title: string;
  count: number;
}

export interface LastExport {
  report: ReportKey;
  title: string;
  export_format: ExportFormat;
  row_count: number;
  by: string | null;
  at: string;
}

export interface ReportsOverview {
  period: Period;
  generated: number;
  previous: number;
  change_pct: number | null;
  low_sample: boolean;
  most_used: UsedReport[];
  by_format: Record<string, number>;
  last_export: LastExport | null;
  people: number;
}

export interface ReportRun {
  id: number;
  report: ReportKey;
  title: string;
  export_format: ExportFormat;
  row_count: number;
  filters: Record<string, unknown>;
  by: string | null;
  at: string;
}

export interface GeneratedFile {
  blob: Blob;
  filename: string;
}

/** Nombre del archivo según `Content-Disposition`; si falta, uno razonable. */
export function filenameFrom(response: HttpResponse<Blob>, fallback: string): string {
  const header = response.headers.get('Content-Disposition') ?? '';
  const match = /filename\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(header);
  return match ? decodeURIComponent(match[1]) : fallback;
}

/** Galería de reportes: catálogo, vista previa con filtros, exportación y actividad (`/reports`). */
@Injectable({ providedIn: 'root' })
export class ReportsService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/reports`;

  catalog(): Observable<Catalog> {
    return this.http.get<Catalog>(`${this.url}/catalog`);
  }

  preview(report: ReportKey, filters: ReportFilters, compare: boolean): Observable<ReportPreview> {
    return this.http.post<ReportPreview>(`${this.url}/preview`, { report, filters, compare });
  }

  generate(report: ReportKey, format: ExportFormat, filters: ReportFilters): Observable<GeneratedFile> {
    return this.http
      .post(`${this.url}/generate`, { report, format, filters }, { observe: 'response', responseType: 'blob' })
      .pipe(map((response) => ({ blob: response.body as Blob, filename: filenameFrom(response, `${report}.${format}`) })));
  }

  overview(period: Period): Observable<ReportsOverview> {
    return this.http.get<ReportsOverview>(`${this.url}/overview`, { params: new HttpParams().set('period', period) });
  }

  history(page = 1, size = 8): Observable<{ items: ReportRun[]; total: number }> {
    const params = new HttpParams().set('page', page).set('size', size);
    return this.http.get<ReportRun[]>(`${this.url}/history`, { params, observe: 'response' }).pipe(
      map((response) => {
        const items = response.body ?? [];
        const total = Number(response.headers.get('X-Total-Count'));
        return { items, total: Number.isFinite(total) && total >= items.length ? total : items.length };
      }),
    );
  }
}
