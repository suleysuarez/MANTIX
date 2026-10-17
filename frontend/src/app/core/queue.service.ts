import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { apiBaseUrl } from './api.config';
import { Period } from './dashboard-kpis.service';

export interface RequestCategory {
  code: string;
  name: string;
}

/** Fila de la tabla de prioridades; `level` más alto = más urgente. */
export interface PriorityRef {
  code: string;
  name: string;
  level: number;
}

export interface CountItem {
  key: string;
  count: number;
}

export interface TriageTimeKpi {
  /** Media en horas desde la creación hasta la primera decisión; `null` sin decisiones. */
  value: number | null;
  previous: number | null;
  change_pct: number | null;
  sample_size: number;
  low_sample: boolean;
  median_hours: number | null;
}

export interface DecisionKpi {
  approved: number;
  rejected: number;
  sample_size: number;
  low_sample: boolean;
  approval_rate_pct: number | null;
  rejection_rate_pct: number | null;
  previous_approval_rate_pct: number | null;
  change_pct: number | null;
}

export interface QueueSummary {
  generated_at: string;
  period: Period;
  window_start: string;
  window_end: string;
  /** Enviadas, clasificadas o asignadas que aún no se inician. */
  pending_total: number;
  unassigned: number;
  oldest_wait_hours: number | null;
  median_wait_hours: number | null;
  by_priority: CountItem[];
  by_category: CountItem[];
  triage_time: TriageTimeKpi;
  decisions: DecisionKpi;
}

/** Métricas y catálogo de la bandeja de solicitudes pendientes (`/maintenance/queue`). */
@Injectable({ providedIn: 'root' })
export class QueueService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/maintenance`;

  summary(period: Period): Observable<QueueSummary> {
    return this.http.get<QueueSummary>(`${this.url}/queue/summary`, {
      params: new HttpParams().set('period', period),
    });
  }

  categories(): Observable<RequestCategory[]> {
    return this.http.get<RequestCategory[]>(`${this.url}/categories`);
  }

  /** Prioridades activas de la tabla del servidor, de la más a la menos urgente. */
  priorities(): Observable<PriorityRef[]> {
    return this.http.get<PriorityRef[]>(`${apiBaseUrl()}/priorities`);
  }
}
