import { HttpClient, HttpResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { apiBaseUrl } from './api.config';

export type DocumentFormat = 'pdf' | 'xlsx';

/** Filtros del servidor para una exportación; solo viaja lo que el usuario eligió. */
export interface ExportApiFilters {
  statuses?: string[];
  priorities?: string[];
  categories?: string[];
  technician_ids?: number[];
  date_from?: string;
  date_to?: string;
  // Listado de técnicos
  search?: string;
  specialty?: string;
  /** Código del rol (listado de usuarios). */
  role?: string;
  is_active?: boolean;
  is_available?: boolean;
  load?: 'none' | 'low' | 'high';
}

export interface ExportRequest {
  filters: ExportApiFilters;
  /** Columnas a incluir; sin ella, el servidor usa el conjunto por defecto del formato. */
  columns?: string[];
  include_charts: boolean;
  include_summary: boolean;
}

export interface ExportColumnInfo {
  key: string;
  label: string;
  kind: string;
  default_pdf: boolean;
  default_xlsx: boolean;
}

export interface ExportOptions {
  report: string;
  title: string;
  columns: ExportColumnInfo[];
  formats: DocumentFormat[];
  max_rows: number;
  warn_rows: number;
  max_range_days: number;
}

export interface ExportCount {
  total: number;
  max_rows: number;
  warn_rows: number;
  over_limit: boolean;
  large: boolean;
}

export interface ExportedDocument {
  blob: Blob;
  filename: string;
}

function filenameOf(response: HttpResponse<Blob>, fallback: string): string {
  const header = response.headers.get('Content-Disposition') ?? '';
  const match = /filename\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(header);
  return match ? decodeURIComponent(match[1]) : fallback;
}

/** Exportación de reportes a PDF y Excel (`/reports/{reporte}/export`). */
@Injectable({ providedIn: 'root' })
export class ExportService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/reports`;

  options(report: string): Observable<ExportOptions> {
    return this.http.get<ExportOptions>(`${this.url}/${report}/export/options`);
  }

  count(report: string, filters: ExportApiFilters): Observable<ExportCount> {
    return this.http.post<ExportCount>(`${this.url}/${report}/export/count`, filters);
  }

  export(report: string, format: DocumentFormat, request: ExportRequest): Observable<ExportedDocument> {
    return this.http
      .post(`${this.url}/${report}/export`, request, { params: { format }, observe: 'response', responseType: 'blob' })
      .pipe(map((response) => ({ blob: response.body as Blob, filename: filenameOf(response, `mantix_${report}.${format}`) })));
  }
}
