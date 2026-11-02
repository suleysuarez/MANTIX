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
  /** Tamaño de muestra (n): tickets que respaldan el valor. */
  sample_size: number;
  /** `true` con 0 < n < 5: se muestra el valor con la nota «pocos datos». */
  low_sample: boolean;
}

/** Tiempo de resolución en horas: `value` es la mediana, con el resto de la distribución. */
export interface ResolutionTimeKpi extends KpiValue {
  average_hours: number | null;
  p90_hours: number | null;
  min_hours: number | null;
  max_hours: number | null;
  /** Desviación estándar muestral; `null` con menos de 2 tickets. */
  stddev_hours: number | null;
}

export interface SlaKpi extends KpiValue {
  met: number;
  missed: number;
  excluded_no_sla: number;
}

export interface BacklogKpi {
  open: number;
  previous_open: number | null;
  change_pct: number | null;
  age_0_2_days: number;
  age_3_7_days: number;
  age_over_7_days: number;
}

export interface AvailabilityKpi {
  value: number | null;
  previous: number | null;
  change_pct: number | null;
  operational: number;
  total: number;
}

export interface KpisResponse {
  generated_at: string;
  scope: 'all' | 'own';
  period: Period;
  window_start: string;
  window_end: string;
  mttr_hours: ResolutionTimeKpi;
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

/** Rendimiento de un técnico en el periodo (`/dashboard/technicians`). */
export interface TechnicianPerformance {
  technician_id: number;
  full_name: string;
  specialization: string | null;
  is_available: boolean;
  open_tickets: number;
  resolved: number;
  mttr_median_hours: number | null;
  /** n del MTTR: tickets que resolvió en el periodo. */
  sample_size: number;
  low_sample: boolean;
  sla_compliance_pct: number | null;
  sla_sample_size: number;
  sla_low_sample: boolean;
  /** Resueltos cuya prioridad no tiene SLA: no cuentan como cumplidos ni incumplidos. */
  sla_excluded_no_sla: number;
  reopened: number;
}

export interface TechniciansPerformanceResponse {
  generated_at: string;
  scope: 'all' | 'own';
  period: Period;
  window_start: string;
  window_end: string;
  /** Ordenados por tickets abiertos (carga), nunca por desempeño. */
  technicians: TechnicianPerformance[];
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

/** Resumen operativo (`/dashboard/summary`): para quien solo ve lo suyo, el estado de sus solicitudes. */
export interface DashboardSummary {
  scope: 'all' | 'own';
  window_days: number;
  tickets: {
    total: number;
    open: number;
    overdue: number;
    by_status: { key: string; count: number }[];
    open_by_priority: { key: string; count: number }[];
  };
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

  technicians(period: Period): Observable<TechniciansPerformanceResponse> {
    return this.http.get<TechniciansPerformanceResponse>(`${this.url}/technicians`, {
      params: new HttpParams().set('period', period),
    });
  }

  summary(period: Period): Observable<DashboardSummary> {
    return this.http.get<DashboardSummary>(`${this.url}/summary`, { params: new HttpParams().set('days', PERIOD_DAYS[period]) });
  }

  alerts(): Observable<AlertsResponse> {
    return this.http.get<AlertsResponse>(`${this.url}/alerts`);
  }

  topFailingEquipment(period: Period, limit = 5): Observable<FailingEquipmentResponse> {
    const params = new HttpParams().set('days', PERIOD_DAYS[period]).set('limit', limit);
    return this.http.get<FailingEquipmentResponse>(`${this.url}/top-failing-equipment`, { params });
  }
}
