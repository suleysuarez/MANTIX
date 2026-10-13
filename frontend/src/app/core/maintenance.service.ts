import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

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
  status: string;
  created_at: string;
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
  status?: string;
  priority?: string;
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
    let params = new HttpParams();
    if (query.status) {
      params = params.set('status', query.status);
    }
    if (query.priority) {
      params = params.set('priority', query.priority);
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
    return this.http.get<MaintenanceListItem[]>(this.url, { params });
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
