import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { apiBaseUrl } from './api.config';

export interface MaintenanceSchedule {
  id: number;
  equipment: { id: number; asset_tag: string; brand: string; model: string };
  technician: { id: number; user_id: number; full_name: string } | null;
  title: string;
  description: string | null;
  interval_days: number;
  /** Horas estimadas por servicio (decimal con 2 cifras); `null` si no se definió. */
  estimated_hours?: string | null;
  remind_days_before: number;
  next_due_at: string;
  last_reminded_at: string | null;
  is_active: boolean;
  created_at: string;
}

export interface SchedulePayload {
  equipment_id: number;
  title: string;
  description: string | null;
  interval_days: number;
  estimated_hours?: number | null;
  remind_days_before: number;
  first_due_at: string;
}

/** Cambios parciales de un plan; `reschedule_reason` solo con una nueva fecha. */
export interface ScheduleUpdatePayload {
  technician_id?: number | null;
  title?: string;
  description?: string | null;
  interval_days?: number;
  estimated_hours?: number | null;
  remind_days_before?: number;
  next_due_at?: string;
  reschedule_reason?: string | null;
  is_active?: boolean;
}

export interface ScheduleRun {
  id: number;
  due_at: string;
  completed_at: string;
  on_time: boolean;
  actual_hours: string | null;
}

export interface ScheduleReschedule {
  id: number;
  old_due_at: string;
  new_due_at: string;
  reason: string | null;
  changed_at: string;
}

export interface ScheduleHistory {
  runs: ScheduleRun[];
  reschedules: ScheduleReschedule[];
}

export type ScheduleStatusFilter = '' | 'overdue' | 'active' | 'inactive';

export interface ScheduleQuery {
  search?: string;
  technicianId?: number | null;
  equipmentId?: number | null;
  status?: ScheduleStatusFilter;
  /** ISO; el servidor filtra por la próxima fecha de servicio. */
  dueFrom?: string;
  dueTo?: string;
  sort?: string;
  /** Base 1. */
  page?: number;
  size?: number;
}

/** Planes de mantenimiento preventivo (`/maintenance/schedules`). */
@Injectable({ providedIn: 'root' })
export class SchedulesService {
  private readonly http = inject(HttpClient);
  private readonly url = `${apiBaseUrl()}/maintenance/schedules`;

  /** Planes activos del equipo, el más próximo primero. */
  listForEquipment(equipmentId: number): Observable<MaintenanceSchedule[]> {
    const params = new HttpParams()
      .set('equipment_id', equipmentId)
      .set('is_active', true)
      .set('sort', 'next_due_at')
      .set('size', 5);
    return this.http.get<MaintenanceSchedule[]>(this.url, { params });
  }

  /** Planes activos de todo el parque, el más próximo primero (para el dashboard). */
  listUpcoming(size = 50): Observable<MaintenanceSchedule[]> {
    const params = new HttpParams().set('is_active', true).set('sort', 'next_due_at').set('size', size);
    return this.http.get<MaintenanceSchedule[]>(this.url, { params });
  }

  /** Planes con filtros y paginación en el servidor; el total llega en `X-Total-Count`. */
  listPage(query: ScheduleQuery = {}): Observable<{ items: MaintenanceSchedule[]; total: number }> {
    let params = new HttpParams();
    if (query.search) {
      params = params.set('search', query.search);
    }
    if (query.technicianId) {
      params = params.set('technician_id', query.technicianId);
    }
    if (query.equipmentId) {
      params = params.set('equipment_id', query.equipmentId);
    }
    if (query.status === 'overdue') {
      params = params.set('overdue', true);
    } else if (query.status === 'active' || query.status === 'inactive') {
      params = params.set('is_active', query.status === 'active');
    }
    if (query.dueFrom) {
      params = params.set('due_from', query.dueFrom);
    }
    if (query.dueTo) {
      params = params.set('due_to', query.dueTo);
    }
    if (query.sort) {
      params = params.set('sort', query.sort);
    }
    if (query.page !== undefined) {
      params = params.set('page', query.page);
    }
    if (query.size !== undefined) {
      params = params.set('size', query.size);
    }
    return this.http.get<MaintenanceSchedule[]>(this.url, { params, observe: 'response' }).pipe(
      map((response) => {
        const items = response.body ?? [];
        const total = Number(response.headers.get('X-Total-Count'));
        return { items, total: Number.isFinite(total) && total >= items.length ? total : items.length };
      }),
    );
  }

  get(id: number): Observable<MaintenanceSchedule> {
    return this.http.get<MaintenanceSchedule>(`${this.url}/${id}`);
  }

  update(id: number, payload: ScheduleUpdatePayload): Observable<MaintenanceSchedule> {
    return this.http.patch<MaintenanceSchedule>(`${this.url}/${id}`, payload);
  }

  /** Marca el servicio como hecho; `actualHours` es opcional (alimenta real vs estimado). */
  complete(id: number, actualHours: number | null): Observable<MaintenanceSchedule> {
    return this.http.post<MaintenanceSchedule>(`${this.url}/${id}/complete`, { actual_hours: actualHours });
  }

  history(id: number): Observable<ScheduleHistory> {
    return this.http.get<ScheduleHistory>(`${this.url}/${id}/history`);
  }

  create(payload: SchedulePayload): Observable<MaintenanceSchedule> {
    return this.http.post<MaintenanceSchedule>(this.url, payload);
  }
}
