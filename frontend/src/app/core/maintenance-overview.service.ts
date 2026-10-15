import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { apiBaseUrl } from './api.config';
import { Period } from './dashboard-kpis.service';

export interface WorkMix {
  preventive: number;
  corrective: number;
  other: number;
  /** n: registros del periodo. */
  sample_size: number;
  low_sample: boolean;
  preventive_pct: number | null;
  previous_preventive_pct: number | null;
  change_pct: number | null;
}

export interface Upcoming {
  overdue: number;
  next_7_days: number;
  next_30_days: number;
}

export interface WeekCompliance {
  /** Lunes 00:00 UTC. */
  week_start: string;
  planned: number;
  on_time: number;
  compliance_pct: number | null;
}

export interface PlanCompliance {
  weeks: WeekCompliance[];
  planned: number;
  on_time: number;
  sample_size: number;
  low_sample: boolean;
  compliance_pct: number | null;
  previous_compliance_pct: number | null;
  change_pct: number | null;
}

export interface DurationComparison {
  average_actual_hours: number | null;
  average_estimated_hours: number | null;
  /** Positivo: tardó más de lo estimado. */
  variance_pct: number | null;
  previous_variance_pct: number | null;
  sample_size: number;
  low_sample: boolean;
}

export interface CostSummary {
  /** Decimales como texto (la API usa `Decimal`). */
  total: string;
  previous_total: string;
  change_pct: number | null;
  records_with_cost: number;
  average_per_record: string | null;
  low_sample: boolean;
}

export interface Reschedules {
  count: number;
  previous: number;
  change_pct: number | null;
}

export interface MaintenanceOverview {
  generated_at: string;
  period: Period;
  window_start: string;
  window_end: string;
  mix: WorkMix;
  upcoming: Upcoming;
  compliance: PlanCompliance;
  duration: DurationComparison;
  cost: CostSummary;
  reschedules: Reschedules;
}

export type CalendarKind = 'planned' | 'overdue' | 'done';

export interface CalendarEvent {
  kind: CalendarKind;
  schedule_id: number;
  title: string;
  equipment_id: number;
  asset_tag: string;
  technician: string | null;
  at: string;
  completed_at: string | null;
  on_time: boolean | null;
}

export interface CalendarResponse {
  generated_at: string;
  start: string;
  end: string;
  truncated: boolean;
  events: CalendarEvent[];
}

/** Resumen y calendario del módulo de Mantenimiento (`/maintenance/overview`, `/calendar`). */
@Injectable({ providedIn: 'root' })
export class MaintenanceOverviewService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/maintenance`;

  overview(period: Period): Observable<MaintenanceOverview> {
    return this.http.get<MaintenanceOverview>(`${this.url}/overview`, {
      params: new HttpParams().set('period', period),
    });
  }

  /** Rango `[start, end)`; el servidor lo limita a 62 días. */
  calendar(start: Date, end: Date): Observable<CalendarResponse> {
    const params = new HttpParams().set('start', start.toISOString()).set('end', end.toISOString());
    return this.http.get<CalendarResponse>(`${this.url}/calendar`, { params });
  }
}
