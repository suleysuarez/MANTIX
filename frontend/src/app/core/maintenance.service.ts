import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { apiBaseUrl } from './api.config';

export const PRIORITIES = ['low', 'medium', 'high', 'critical'] as const;
export const REQUEST_STATUSES = [
  'submitted', 'triaged', 'assigned', 'in_progress', 'waiting', 'resolved', 'closed', 'cancelled',
] as const;
export const WORK_TYPES = [
  'corrective', 'preventive', 'inspection', 'installation', 'recovery', 'other',
] as const;

export interface MaintenanceListItem {
  id: number;
  ticket_number: string;
  equipment_id: number;
  title: string;
  priority: string;
  category?: string | null;
  status: string;
  created_at: string;
  /** La persona puede trabajar este ticket (los ve todos o está asignado a ella): solo esos se arrastran. */
  can_act?: boolean;
}

export interface TechnicianSummary {
  id: number;
  user_id: number;
  full_name: string;
}

export interface TicketAssignment {
  id: number;
  technician: TechnicianSummary;
  assigned_at: string;
  unassigned_at: string | null;
  notes: string | null;
}

export interface StatusHistoryEntry {
  id: number;
  from_status: string | null;
  to_status: string;
  changed_at: string;
  notes: string | null;
}

export interface MaintenanceRequest {
  id: number;
  ticket_number: string;
  equipment: { id: number; asset_tag: string; brand: string; model: string };
  requested_by: { id: number; full_name: string; email: string };
  title: string;
  description: string;
  priority: string;
  status: string;
  category?: string | null;
  resolution_summary: string | null;
  resolved_at: string | null;
  closed_at: string | null;
  created_at: string;
  updated_at: string;
  current_assignment: TicketAssignment | null;
  status_history: StatusHistoryEntry[];
  allowed_next_statuses: string[];
}

export interface MaintenanceRequestPayload {
  equipment_id: number;
  title: string;
  description: string;
  priority: string;
}

export interface MaintenanceRecordPayload {
  work_type: string;
  started_at: string;
  completed_at: string | null;
  diagnosis: string;
  actions_taken: string;
  result: string;
  labor_cost: number | null;
  parts_cost: number | null;
  notes: string | null;
}

export interface MaintenanceRecord {
  id: number;
  work_type: string;
  started_at: string;
  completed_at: string | null;
  diagnosis: string;
  actions_taken: string;
  result: string;
  labor_cost: string | null;
  parts_cost: string | null;
  total_cost: string | null;
  notes: string | null;
}

export interface MaintenanceQuery {
  /** Un estado o varios separados por comas (`submitted,triaged`). */
  status?: string;
  priority?: string;
  category?: string;
  /** `true`: sin técnico; `false`: con técnico. */
  unassigned?: boolean;
  /** Base 1; junto con `size` pagina en el servidor. */
  page?: number;
  size?: number;
  equipmentId?: number;
  search?: string;
  /** ISO datetimes; the API matches `created_at` between them. */
  dateFrom?: string;
  dateTo?: string;
  /** Campo de orden; prefijo `-` para descendente (p. ej. `-created_at`). */
  sort?: string;
  limit?: number;
  offset?: number;
}

@Injectable({ providedIn: 'root' })
export class MaintenanceService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/maintenance/requests`;

  list(query: MaintenanceQuery = {}): Observable<MaintenanceListItem[]> {
    return this.http.get<MaintenanceListItem[]>(this.url, { params: this.params(query) });
  }

  /** Como `list`, con el total que la API informa en la cabecera `X-Total-Count`. */
  listPage(query: MaintenanceQuery = {}): Observable<{ items: MaintenanceListItem[]; total: number }> {
    return this.http
      .get<MaintenanceListItem[]>(this.url, { params: this.params(query), observe: 'response' })
      .pipe(
        map((response) => {
          const items = response.body ?? [];
          const total = Number(response.headers.get('X-Total-Count'));
          return { items, total: Number.isFinite(total) && total >= items.length ? total : items.length };
        }),
      );
  }

  /** Triaje: fija categoría y prioridad (catálogos activos) y pasa una solicitud nueva a «clasificada». */
  classify(id: number, body: { category: string; priority: string; notes: string | null }): Observable<MaintenanceRequest> {
    return this.http.post<MaintenanceRequest>(`${this.url}/${id}/classify`, body);
  }

  /** Rechaza una solicitud que no ha iniciado; el motivo queda en el historial. */
  reject(id: number, reason: string): Observable<MaintenanceRequest> {
    return this.http.post<MaintenanceRequest>(`${this.url}/${id}/reject`, { reason });
  }

  private params(query: MaintenanceQuery): HttpParams {
    let params = new HttpParams();
    if (query.status) {
      params = params.set('status', query.status);
    }
    if (query.priority) {
      params = params.set('priority', query.priority);
    }
    if (query.category) {
      params = params.set('category', query.category);
    }
    if (query.unassigned !== undefined) {
      params = params.set('unassigned', query.unassigned);
    }
    if (query.page !== undefined) {
      params = params.set('page', query.page);
    }
    if (query.size !== undefined) {
      params = params.set('size', query.size);
    }
    if (query.equipmentId !== undefined) {
      params = params.set('equipment_id', query.equipmentId);
    }
    if (query.search) {
      params = params.set('search', query.search);
    }
    if (query.dateFrom) {
      params = params.set('date_from', query.dateFrom);
    }
    if (query.dateTo) {
      params = params.set('date_to', query.dateTo);
    }
    if (query.sort) {
      params = params.set('sort', query.sort);
    }
    if (query.limit !== undefined) {
      params = params.set('limit', query.limit);
    }
    if (query.offset !== undefined) {
      params = params.set('offset', query.offset);
    }
    return params;
  }

  get(id: number): Observable<MaintenanceRequest> {
    return this.http.get<MaintenanceRequest>(`${this.url}/${id}`);
  }

  create(payload: MaintenanceRequestPayload): Observable<MaintenanceRequest> {
    return this.http.post<MaintenanceRequest>(this.url, payload);
  }

  transition(
    id: number,
    status: string,
    notes: string | null,
    resolutionSummary: string | null,
  ): Observable<MaintenanceRequest> {
    return this.http.post<MaintenanceRequest>(`${this.url}/${id}/status`, {
      status,
      notes,
      resolution_summary: resolutionSummary,
    });
  }

  assign(id: number, technicianId: number, notes: string | null): Observable<MaintenanceRequest> {
    return this.http.post<MaintenanceRequest>(`${this.url}/${id}/assignment`, {
      technician_id: technicianId,
      notes,
    });
  }

  unassign(id: number): Observable<MaintenanceRequest> {
    return this.http.delete<MaintenanceRequest>(`${this.url}/${id}/assignment`);
  }

  listRecords(id: number): Observable<MaintenanceRecord[]> {
    return this.http.get<MaintenanceRecord[]>(`${this.url}/${id}/records`);
  }

  addRecord(id: number, payload: MaintenanceRecordPayload): Observable<MaintenanceRecord> {
    return this.http.post<MaintenanceRecord>(`${this.url}/${id}/records`, payload);
  }
}
