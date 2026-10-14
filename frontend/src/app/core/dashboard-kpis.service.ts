import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { apiBaseUrl } from './api.config';

export type Period = '7d' | '30d' | '12m';

/** Días que cubre cada periodo, para los endpoints que filtran por ventana en días. */
export const PERIOD_DAYS: Record<Period, number> = { '7d': 7, '30d': 30, '12m': 365 };

export interface KpiValue {
  /** `null` cuando ningún ticket respalda la cifra: estado vacío, nunca un 0 engañoso. */
  value: number | null;
  previous: number | null;
  change_pct: number | null;
  sample_size: number;
}

export interface SlaKpi extends KpiValue {
  met: number;
  missed: number;
  excluded_no_sla: number;
}

export interface BacklogKpi {
  open: number;
  age_0_2_days: number;
  age_3_7_days: number;
  age_over_7_days: number;
}

export interface AvailabilityKpi {
  value: number | null;
  operational: number;
  total: number;
}

export interface KpisResponse {
  generated_at: string;
  scope: 'all' | 'own';
  period: Period;
  window_start: string;
  window_end: string;
  mttr_hours: KpiValue;
  first_assignment_hours: KpiValue;
  sla_compliance_pct: SlaKpi;
  resolution_rate_pct: KpiValue;
  backlog: BacklogKpi;
  availability: AvailabilityKpi;
}

export interface TrendPoint {
  bucket: string;
  created: number;
  resolved: number;
  mttr_hours: number | null;
  sla_compliance_pct: number | null;
}

export interface TrendsResponse {
  generated_at: string;
  scope: 'all' | 'own';
  period: Period;
  granularity: 'day' | 'month';
  points: TrendPoint[];
}

export type AlertReason = 'unassigned_critical' | 'sla_breached' | 'sla_at_risk';

export interface TicketAlert {
  id: number;
  ticket_number: string;
  title: string;
  equipment_id: number;
  asset_tag: string;
  priority: string;
  status: string;
  assigned: boolean;
  sla_deadline: string | null;
  reason: AlertReason;
}

export interface DownEquipmentAlert {
  equipment_id: number;
  asset_tag: string;
  brand: string;
  model: string;
  status: string;
  down_since: string | null;
  down_hours: number | null;
}

export interface ScheduleAlert {
  id: number;
  equipment_id: number;
  asset_tag: string;
  title: string;
  next_due_at: string;
  overdue: boolean;
}

export interface AlertsResponse {
  generated_at: string;
  scope: 'all' | 'own';
  tickets: TicketAlert[];
  down_equipment: DownEquipmentAlert[];
  schedules: ScheduleAlert[];
}

export interface FailingEquipment {
  equipment_id: number;
  asset_tag: string;
  brand: string;
  model: string;
  tickets: number;
  last_ticket_at: string | null;
}

export interface FailingEquipmentResponse {
  window_days: number;
  equipment: FailingEquipment[];
}

/** Indicadores calculados por el backend (`/dashboard/kpis`, `/trends`, `/alerts`). */
@Injectable({ providedIn: 'root' })
export class DashboardKpisService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/dashboard`;

  kpis(period: Period): Observable<KpisResponse> {
    return this.http.get<KpisResponse>(`${this.url}/kpis`, { params: new HttpParams().set('period', period) });
  }

  trends(period: Period): Observable<TrendsResponse> {
    return this.http.get<TrendsResponse>(`${this.url}/trends`, { params: new HttpParams().set('period', period) });
  }

  alerts(): Observable<AlertsResponse> {
    return this.http.get<AlertsResponse>(`${this.url}/alerts`);
  }

  topFailingEquipment(period: Period, limit = 5): Observable<FailingEquipmentResponse> {
    const params = new HttpParams().set('days', PERIOD_DAYS[period]).set('limit', limit);
    return this.http.get<FailingEquipmentResponse>(`${this.url}/top-failing-equipment`, { params });
  }
}
