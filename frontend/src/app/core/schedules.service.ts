import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { apiBaseUrl } from './api.config';

export interface MaintenanceSchedule {
  id: number;
  equipment: { id: number; asset_tag: string; brand: string; model: string };
  technician: { id: number; user_id: number; full_name: string } | null;
  title: string;
  description: string | null;
  interval_days: number;
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
  remind_days_before: number;
  first_due_at: string;
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

  create(payload: SchedulePayload): Observable<MaintenanceSchedule> {
    return this.http.post<MaintenanceSchedule>(this.url, payload);
  }
}
